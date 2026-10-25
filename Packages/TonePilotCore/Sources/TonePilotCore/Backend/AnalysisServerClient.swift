import Foundation
// The Android app doesn't use the network clients, so it doesn't link FoundationNetworking (curl).
#if !os(Android)
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Settings for the optional analysis server (Demucs stems + Basic Pitch vocal melody).
/// Nothing is uploaded unless the user enables it *and* consents per song.
public struct AnalysisServerSettings: Codable, Hashable, Sendable {
    public var enabled: Bool
    /// e.g. http://192.168.1.20:8765 (your Mac on the same Wi-Fi) or an https URL you control.
    public var baseURL: String
    /// Optional shared token (TONEPILOT_TOKEN on the server). Stored in the Keychain by the app.
    public var model: String
    public var transcribeVocals: Bool

    public init(enabled: Bool = false, baseURL: String = "", model: String = "htdemucs", transcribeVocals: Bool = true) {
        self.enabled = enabled
        self.baseURL = baseURL
        self.model = model
        self.transcribeVocals = transcribeVocals
    }
}

public struct ServerHealth: Codable, Sendable {
    public var version: String
    public var demucs: Bool
    public var basicPitch: Bool
    public var models: [String]
    public var authRequired: Bool
    public var retentionHours: Double
}

public struct ServerJobStatus: Codable, Sendable {
    public var id: String?
    public var status: String
    public var progress: Double?
    public var error: String?
}

public struct ServerResult: Codable, Sendable {
    public struct Stem: Codable, Sendable {
        public var kind: String
        public var url: String
        public var model: String
    }
    public struct ModelLicense: Codable, Sendable {
        public var name: String
        public var license: String
        public var url: String
    }
    public var stems: [Stem]
    public var melody: MelodyTrack?
    public var models: [ModelLicense]
    public var retentionHours: Double
    public var notes: [String]
}

public enum AnalysisServerError: Error, LocalizedError, Equatable {
    case notConfigured
    case consentRequired
    case http(Int, String)
    case jobFailed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "The analysis server isn't set up (Settings › Analysis server)."
        case .consentRequired: return "Uploading needs your permission for this song."
        case let .http(code, msg): return "Server error \(code): \(msg)"
        case .jobFailed(let m): return "Server analysis failed: \(m)"
        case .timedOut: return "The server took too long."
        }
    }
}

/// HTTP client for `server/` (see server/README.md for the API).
public final class AnalysisServerClient: @unchecked Sendable {
    public let baseURL: URL
    private let token: String?
    private let session: URLSession

    public init?(settings: AnalysisServerSettings, token: String?, session: URLSession = .shared) {
        guard settings.enabled, let url = URL(string: settings.baseURL.trimmingCharacters(in: .whitespaces)),
              url.scheme == "http" || url.scheme == "https" else { return nil }
        baseURL = url
        self.token = token?.isEmpty == false ? token : nil
        self.session = session
    }

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent(path))
        r.httpMethod = method
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private func send(_ r: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: r)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw AnalysisServerError.http(code, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return data
    }

    public func health() async throws -> ServerHealth {
        try await JSONDecoder().decode(ServerHealth.self, from: send(request("v1/health")))
    }

    /// Uploads authorised audio. `consent` must come from an explicit user confirmation.
    public func submit(audioFile: URL, consent: Bool, model: String, transcribeVocals: Bool) async throws -> String {
        guard consent else { throw AnalysisServerError.consentRequired }
        let boundary = "TonePilot-\(UUID().uuidString)"
        var r = request("v1/jobs", method: "POST")
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        r.httpBody = try Self.multipart(boundary: boundary, fields: ["consent": "true", "model": model,
                                                                    "transcribe": transcribeVocals ? "vocals" : "none"],
                                        file: audioFile)
        let status = try await JSONDecoder().decode(ServerJobStatus.self, from: send(r))
        guard let id = status.id else { throw AnalysisServerError.jobFailed("no job id") }
        return id
    }

    public func status(job: String) async throws -> ServerJobStatus {
        try await JSONDecoder().decode(ServerJobStatus.self, from: send(request("v1/jobs/\(job)")))
    }

    /// Polls until done. `onProgress` gets 0...1.
    public func waitForResult(job: String, timeout: TimeInterval = 1800, onProgress: (Double) -> Void = { _ in }) async throws -> ServerResult {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            try Task.checkCancellation()
            let s = try await status(job: job)
            onProgress(s.progress ?? 0)
            if s.status == "done" { return try await Self.decodeResult(send(request("v1/jobs/\(job)/result"))) }
            if s.status == "failed" { throw AnalysisServerError.jobFailed(s.error ?? "unknown") }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        throw AnalysisServerError.timedOut
    }

    public func downloadStem(_ stem: ServerResult.Stem, to directory: URL) async throws -> URL {
        var r = URLRequest(url: URL(string: stem.url, relativeTo: baseURL)!.absoluteURL)
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let data = try await send(r)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dest = directory.appendingPathComponent("\(stem.kind).wav")
        try data.write(to: dest, options: .atomic)
        return dest
    }

    /// Deletes the upload's stems and results from the server.
    public func delete(job: String) async throws {
        _ = try await send(request("v1/jobs/\(job)", method: "DELETE"))
    }

    public static func decodeResult(_ data: Data) throws -> ServerResult {
        try JSONDecoder().decode(ServerResult.self, from: data)
    }

    static func multipart(boundary: String, fields: [String: String], file: URL) throws -> Data {
        var body = Data()
        func line(_ s: String) { body.append(Data((s + "\r\n").utf8)) }
        for (k, v) in fields.sorted(by: { $0.key < $1.key }) {
            line("--\(boundary)")
            line("Content-Disposition: form-data; name=\"\(k)\"")
            line("")
            line(v)
        }
        line("--\(boundary)")
        line("Content-Disposition: form-data; name=\"file\"; filename=\"\(file.lastPathComponent)\"")
        line("Content-Type: application/octet-stream")
        line("")
        body.append(try Data(contentsOf: file))
        line("")
        line("--\(boundary)--")
        return body
    }
}

#endif
