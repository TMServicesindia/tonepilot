import CryptoKit
import Foundation
import TonePilotCore

/// Real-instrument sound packs (CC0 recordings: VSCO 2 CE, VCSL), downloaded inside the app from the
/// project's `sounds-v1` release (published by .github/workflows/sound-packs.yml), checked against
/// the published size and SHA-256, and unpacked into the sample folder as `packs/<id>/` — the path
/// the pack's tones reference — so they play through the same multisample path as user samples.
final class SoundPackStore: @unchecked Sendable {
    static let baseURL = URL(string: "https://github.com/TMServicesindia/tonepilot/releases/download/sounds-v1/")!

    struct Manifest: Decodable {
        struct Pack: Decodable, Identifiable {
            var id: String { file.replacingOccurrences(of: ".aar", with: "") }
            let file: String
            let size: Int64
            let sha256: String
            let name: String
            let family: String
            let version: Int
            let license: String
            let tones: [String]
        }
        let packs: [String: Pack]
    }

    enum Failure: LocalizedError {
        case network(String), checksum, space, invalid(String)
        var errorDescription: String? {
            switch self {
            case .network(let m): return "The sound pack couldn't be downloaded (\(m)). Check the internet connection and try again."
            case .checksum: return "The downloaded sound pack was damaged. Please try again."
            case .space: return "Not enough free space on this iPhone for this sound pack."
            case .invalid(let m): return "The sound pack couldn't be used (\(m))."
            }
        }
    }

    /// `<sample folder>/packs` — zone file names are `packs/<id>/<file>` relative to the sample folder.
    let directory: URL

    init(sampleDirectory: URL) {
        directory = sampleDirectory.appendingPathComponent("packs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true      // downloadable again; not backed up to iCloud
        var dir = directory
        try? dir.setResourceValues(values)
    }

    private func folder(_ id: String) -> URL { directory.appendingPathComponent(id, isDirectory: true) }
    private func ready(_ id: String) -> URL { directory.appendingPathComponent(".ready-\(id)") }

    /// Installed, valid packs (read from their pack.json; small files, fine off the main thread).
    func installed() -> [SoundPack] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return ids.filter { !$0.hasPrefix(".") && FileManager.default.fileExists(atPath: ready($0).path) }.sorted().compactMap { id in
            guard let data = try? Data(contentsOf: folder(id).appendingPathComponent("pack.json")),
                  let pack = try? SoundPack.decode(data), pack.problems().isEmpty else { return nil }
            return pack
        }
    }

    func isInstalled(_ id: String) -> Bool { FileManager.default.fileExists(atPath: ready(id).path) }

    func installedSize(_ id: String) -> Int64 {
        var total: Int64 = 0
        if let e = FileManager.default.enumerator(at: folder(id), includingPropertiesForKeys: [.fileSizeKey]) {
            for case let url as URL in e { total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return total
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: ready(id))
        try? FileManager.default.removeItem(at: folder(id))
    }

    func manifest() async throws -> Manifest {
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.baseURL.appendingPathComponent("manifest.json"))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.network("no pack list") }
            return try JSONDecoder().decode(Manifest.self, from: data)
        } catch let f as Failure { throw f } catch {
            throw Failure.network(error.localizedDescription)
        }
    }

    /// Downloads, checks, unpacks and validates one pack. `progress` gets 0...1 (any thread).
    func install(_ info: Manifest.Pack, progress: @escaping @Sendable (Double) -> Void) async throws -> SoundPack {
        if let free = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < info.size * 3 { throw Failure.space }
        let file = try await download(info.file, size: info.size, progress: progress)
        defer { try? FileManager.default.removeItem(at: file) }
        guard try sha256(file) == info.sha256.lowercased() else { throw Failure.checksum }
        try? FileManager.default.removeItem(at: ready(info.id))
        try ModelArchive.extract(file, to: folder(info.id))
        guard let data = try? Data(contentsOf: folder(info.id).appendingPathComponent("pack.json")) else { throw Failure.invalid("no pack.json") }
        let pack: SoundPack
        do { pack = try SoundPack.decode(data) } catch { throw Failure.invalid("unreadable pack.json") }
        if let problem = pack.problems().first { throw Failure.invalid(problem) }
        for name in pack.files.keys where !FileManager.default.fileExists(atPath: folder(info.id).appendingPathComponent(name).path) {
            throw Failure.invalid("\(name) missing")
        }
        FileManager.default.createFile(atPath: ready(info.id).path, contents: Data())
        progress(1)
        return pack
    }

    private func download(_ name: String, size: Int64, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let url = Self.baseURL.appendingPathComponent(name)
        let keep = directory.appendingPathComponent(".download-\(UUID().uuidString)")
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PackDownloadDelegate(keep: keep, progress: { got in progress(min(0.95, Double(got) / Double(max(1, size)) * 0.95)) }) {
                continuation.resume(with: $0)
            }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            session.downloadTask(with: url).resume()
            session.finishTasksAndInvalidate()
        }
    }

    private func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private final class PackDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let keep: URL
    let progress: @Sendable (Int64) -> Void
    let done: (Result<URL, Error>) -> Void
    private var finished = false
    private let lock = NSLock()

    init(keep: URL, progress: @escaping @Sendable (Int64) -> Void, done: @escaping (Result<URL, Error>) -> Void) {
        self.keep = keep; self.progress = progress; self.done = done
    }

    private func finish(_ r: Result<URL, Error>) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        done(r)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            finish(.failure(SoundPackStore.Failure.network("HTTP \((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)"))); return
        }
        do {
            try? FileManager.default.removeItem(at: keep)
            try FileManager.default.moveItem(at: location, to: keep)
            finish(.success(keep))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(SoundPackStore.Failure.network(error.localizedDescription))) }
    }
}
