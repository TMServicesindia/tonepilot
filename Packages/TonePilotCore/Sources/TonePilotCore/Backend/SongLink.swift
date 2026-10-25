import Foundation
// The Android app doesn't use the network clients, so it doesn't link FoundationNetworking (curl).
#if !os(Android)
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A link to a song on a streaming service. TonePilot only *opens* it (so the user's own app
/// plays it) and reads public title metadata via oEmbed. It never fetches the audio.
public struct SongLink: Hashable, Sendable {
    public enum Service: String, CaseIterable, Sendable {
        case youtube = "YouTube", youtubeMusic = "YouTube Music", spotify = "Spotify",
             jioSaavn = "JioSaavn", appleMusic = "Apple Music", other = "Other"
    }

    public let url: URL
    public let service: Service

    public init?(_ text: String) {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        guard let url = URL(string: t), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), host.contains(".") else { return nil }
        self.url = url
        if host == "music.youtube.com" { service = .youtubeMusic }
        else if host.hasSuffix("youtube.com") || host == "youtu.be" { service = .youtube }
        else if host.hasSuffix("spotify.com") || host == "spotify.link" { service = .spotify }
        else if host.hasSuffix("jiosaavn.com") { service = .jioSaavn }
        else if host == "music.apple.com" { service = .appleMusic }
        else { service = .other }
    }

    /// Public oEmbed endpoint for the title, where the service offers one.
    public var oEmbedURL: URL? {
        let encoded = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=?"))) ?? ""
        switch service {
        case .youtube, .youtubeMusic: return URL(string: "https://www.youtube.com/oembed?format=json&url=\(encoded)")
        case .spotify: return URL(string: "https://open.spotify.com/oembed?url=\(encoded)")
        default: return nil
        }
    }

    /// Cleans common video-title noise: "Hukum - Thalaivar Alappara | Jailer | Rajinikanth | Anirudh" -> "Hukum - Thalaivar Alappara".
    public static func cleanTitle(_ raw: String) -> String {
        var t = raw
        for sep in [" | ", " || ", " - Lyric", " (Lyric", " [Lyric", " (Official", " [Official", " Official Video", " Full Video", " Video Song", " Lyrical"] {
            if let r = t.range(of: sep, options: .caseInsensitive), r.lowerBound > t.startIndex { t = String(t[..<r.lowerBound]) }
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    public struct Metadata: Sendable {
        public var title: String
        public var author: String?
    }

    static func parseOEmbed(_ data: Data) -> Metadata? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = obj["title"] as? String, !title.isEmpty else { return nil }
        return Metadata(title: cleanTitle(title), author: obj["author_name"] as? String)
    }

    /// Fetches the public title (and channel/artist) for the link, or nil if unavailable.
    public func fetchMetadata(session: URLSession = .shared) async -> Metadata? {
        guard let endpoint = oEmbedURL else { return nil }
        do {
            let (data, response) = try await session.data(from: endpoint)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return Self.parseOEmbed(data)
        } catch { return nil }
    }
}

#endif
