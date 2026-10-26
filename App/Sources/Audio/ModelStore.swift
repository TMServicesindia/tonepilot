import CryptoKit
import Foundation
import TonePilotCore

/// Separation models are downloaded inside the app the first time they're needed (instead of
/// being built into the install file), from the project's public release page, checked against
/// the published size and SHA-256, and kept in Application Support (not backed up to iCloud).
enum SeparationPack: String, CaseIterable, Identifiable, Sendable {
    case four = "4", six = "6"
    var id: String { rawValue }

    var title: String { self == .four ? "4 parts" : "6 parts" }
    var detail: String {
        self == .four ? "Vocals, drums, bass and music — the fastest."
                      : "Adds separate Piano and Guitar parts. A little slower."
    }
    /// demucs.cpp weights (CPU parts of the separation).
    var weightsFile: String { "ggml-model-htdemucs-\(rawValue)s-f16.bin" }
    /// Core ML network (GPU / Neural Engine).
    var coreMLFolder: String { self == .four ? "HTDemucs.mlmodelc" : "HTDemucs6.mlmodelc" }
    var coreMLArchive: String { coreMLFolder + ".aar" }
    var files: [String] { [weightsFile, coreMLArchive] }
}

final class ModelStore: @unchecked Sendable {
    /// Release with the model files and manifest.json (published by .github/workflows/coreml-convert.yml).
    static let baseURL = URL(string: "https://github.com/TMServicesindia/tonepilot/releases/download/models-v1/")!

    struct Manifest: Decodable {
        struct File: Decodable { let size: Int64; let sha256: String }
        let files: [String: File]
    }

    enum Failure: LocalizedError {
        case network(String), checksum(String), space
        var errorDescription: String? {
            switch self {
            case .network(let m): return "The separation model couldn't be downloaded (\(m)). Check the internet connection and try again."
            case .checksum(let f): return "The downloaded model (\(f)) was damaged. Please try again."
            case .space: return "Not enough free space on this iPhone for the separation model."
            }
        }
    }

    let directory: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var dir = support.appendingPathComponent("TonePilot/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        directory = dir
    }

    func weightsURL(_ pack: SeparationPack) -> URL { directory.appendingPathComponent(pack.weightsFile) }
    func coreMLURL(_ pack: SeparationPack) -> URL { directory.appendingPathComponent(pack.coreMLFolder, isDirectory: true) }
    private var readyMarker: (SeparationPack) -> URL { { self.directory.appendingPathComponent(".ready-\($0.rawValue)") } }

    func isInstalled(_ pack: SeparationPack) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: readyMarker(pack).path) && fm.fileExists(atPath: weightsURL(pack).path)
            && fm.fileExists(atPath: coreMLURL(pack).path)
    }

    /// Bytes on disk for an installed pack.
    func installedSize(_ pack: SeparationPack) -> Int64 {
        let fm = FileManager.default
        var total: Int64 = (try? fm.attributesOfItem(atPath: weightsURL(pack).path)[.size] as? Int64) ?? 0
        if let e = fm.enumerator(at: coreMLURL(pack), includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in e { total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return total
    }

    func delete(_ pack: SeparationPack) {
        let fm = FileManager.default
        try? fm.removeItem(at: readyMarker(pack))
        try? fm.removeItem(at: weightsURL(pack))
        try? fm.removeItem(at: coreMLURL(pack))
    }

    /// Total download size of a pack (from the manifest).
    func downloadSize(_ pack: SeparationPack) async -> Int64? {
        guard let m = try? await manifest() else { return nil }
        return pack.files.compactMap { m.files[$0]?.size }.reduce(0, +)
    }

    func manifest() async throws -> Manifest {
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.baseURL.appendingPathComponent("manifest.json"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.network("no model list") }
            return try JSONDecoder().decode(Manifest.self, from: data)
        } catch let f as Failure { throw f } catch {
            throw Failure.network(error.localizedDescription)
        }
    }

    /// Downloads, checks and unpacks a pack. `progress` gets 0...1 (main thread not required).
    func install(_ pack: SeparationPack, progress: @escaping @Sendable (Double) -> Void) async throws {
        if isInstalled(pack) { return }
        let manifest = try await manifest()
        let sizes = pack.files.map { manifest.files[$0]?.size ?? 0 }
        let total = max(1, sizes.reduce(0, +))
        if let free = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < total * 3 { throw Failure.space }
        var done: Int64 = 0
        for (i, name) in pack.files.enumerated() {
            guard let info = manifest.files[name] else { throw Failure.network("\(name) isn't published") }
            let base = done
            let file = try await download(name) { got in progress(Double(base + got) / Double(total) * 0.95) }
            defer { try? FileManager.default.removeItem(at: file) }
            guard try sha256(file) == info.sha256.lowercased() else { throw Failure.checksum(name) }
            if name.hasSuffix(".aar") {
                try ModelArchive.extract(file, to: coreMLURL(pack))
            } else {
                try? FileManager.default.removeItem(at: weightsURL(pack))
                try FileManager.default.moveItem(at: file, to: weightsURL(pack))
            }
            done += sizes[i]
        }
        FileManager.default.createFile(atPath: readyMarker(pack).path, contents: Data())
        progress(1)
    }

    private func download(_ name: String, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let url = Self.baseURL.appendingPathComponent(name)
        let keep = directory.appendingPathComponent("download-\(UUID().uuidString)")
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(keep: keep, progress: progress) { continuation.resume(with: $0) }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            session.downloadTask(with: url).resume()
            session.finishTasksAndInvalidate()
        }
    }

    private func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// One file download with progress; the finished file is moved to `keep` before iOS deletes it.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let keep: URL
    let progress: @Sendable (Int64) -> Void
    let done: (Result<URL, Error>) -> Void
    private var moved: Result<URL, Error>?

    init(keep: URL, progress: @escaping @Sendable (Int64) -> Void, done: @escaping (Result<URL, Error>) -> Void) {
        self.keep = keep
        self.progress = progress
        self.done = done
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { moved = .failure(ModelStore.Failure.network("HTTP \(status)")); return }
        do {
            try? FileManager.default.removeItem(at: keep)
            try FileManager.default.moveItem(at: location, to: keep)
            moved = .success(keep)
        } catch {
            moved = .failure(error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { done(.failure(ModelStore.Failure.network(error.localizedDescription))); return }
        done(moved ?? .failure(ModelStore.Failure.network("no file")))
    }
}
