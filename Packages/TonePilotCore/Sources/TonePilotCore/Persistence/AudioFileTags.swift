import Foundation

/// Reads display metadata (title, artist, album) from an MP3's ID3 tags without modifying the file.
/// Missing, stripped or odd tags are fine: the filename is used instead.
public struct AudioFileTags: Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?

    public init(title: String? = nil, artist: String? = nil, album: String? = nil) {
        self.title = title
        self.artist = artist
        self.album = album
    }

    /// Reads ID3v2.2/2.3/2.4 text frames, then falls back to an ID3v1 trailer.
    public static func read(_ data: Data) -> AudioFileTags {
        var tags = readID3v2(data) ?? AudioFileTags()
        if tags.title == nil || tags.artist == nil, let v1 = readID3v1(data) {
            tags.title = tags.title ?? v1.title
            tags.artist = tags.artist ?? v1.artist
            tags.album = tags.album ?? v1.album
        }
        return tags
    }

    public static func read(url: URL) -> AudioFileTags {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return AudioFileTags() }
        defer { try? handle.close() }
        // Tags live at the start (v2, rarely > 1 MB with cover art) and the last 128 bytes (v1).
        let head = (try? handle.read(upToCount: 1 << 20)) ?? Data()
        var tags = readID3v2(head) ?? AudioFileTags()
        if tags.title == nil || tags.artist == nil,
           let end = try? handle.seekToEnd(), end >= 128 {
            try? handle.seek(toOffset: end - 128)
            if let tail = try? handle.read(upToCount: 128), let v1 = readID3v1(tail) {
                tags.title = tags.title ?? v1.title
                tags.artist = tags.artist ?? v1.artist
                tags.album = tags.album ?? v1.album
            }
        }
        return tags
    }

    static func readID3v2(_ d: Data) -> AudioFileTags? {
        let b = [UInt8](d.prefix(10))
        guard b.count == 10, b[0] == 0x49, b[1] == 0x44, b[2] == 0x33 else { return nil } // "ID3"
        let version = Int(b[3])
        let size = Int(b[6]) << 21 | Int(b[7]) << 14 | Int(b[8]) << 7 | Int(b[9])
        let bytes = [UInt8](d.prefix(10 + size))
        var tags = AudioFileTags()
        var i = 10
        let headerLen = version == 2 ? 6 : 10
        while i + headerLen <= bytes.count {
            let idLen = version == 2 ? 3 : 4
            let id = String(bytes: bytes[i..<(i + idLen)], encoding: .ascii) ?? ""
            guard !id.isEmpty, id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else { break }
            let frameSize: Int
            if version == 2 {
                frameSize = Int(bytes[i + 3]) << 16 | Int(bytes[i + 4]) << 8 | Int(bytes[i + 5])
            } else if version == 4 {
                frameSize = Int(bytes[i + 4]) << 21 | Int(bytes[i + 5]) << 14 | Int(bytes[i + 6]) << 7 | Int(bytes[i + 7])
            } else {
                frameSize = Int(bytes[i + 4]) << 24 | Int(bytes[i + 5]) << 16 | Int(bytes[i + 6]) << 8 | Int(bytes[i + 7])
            }
            let start = i + headerLen
            guard frameSize > 0, start + frameSize <= bytes.count else { break }
            let body = Array(bytes[start..<(start + frameSize)])
            switch id {
            case "TIT2", "TT2": tags.title = decodeText(body)
            case "TPE1", "TP1": tags.artist = decodeText(body)
            case "TALB", "TAL": tags.album = decodeText(body)
            default: break
            }
            i = start + frameSize
        }
        return tags
    }

    static func decodeText(_ body: [UInt8]) -> String? {
        guard let enc = body.first else { return nil }
        let payload = Data(body.dropFirst())
        let s: String?
        switch enc {
        case 1: s = String(data: payload, encoding: .utf16)               // with BOM
        case 2: s = String(data: payload, encoding: .utf16BigEndian)
        case 3: s = String(data: payload, encoding: .utf8)
        default: s = String(data: payload, encoding: .isoLatin1)
        }
        let cleaned = s?.replacingOccurrences(of: "\u{0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    static func readID3v1(_ d: Data) -> AudioFileTags? {
        guard d.count >= 128 else { return nil }
        let t = [UInt8](d.suffix(128))
        guard t[0] == 0x54, t[1] == 0x41, t[2] == 0x47 else { return nil } // "TAG"
        func field(_ r: Range<Int>) -> String? {
            let s = String(bytes: t[r].prefix { $0 != 0 }, encoding: .isoLatin1)?.trimmingCharacters(in: .whitespaces)
            return s?.isEmpty == false ? s : nil
        }
        return AudioFileTags(title: field(3..<33), artist: field(33..<63), album: field(63..<93))
    }

    /// "Hukum_-_Thalaivar_Alappara (320 kbps).mp3" -> "Hukum - Thalaivar Alappara"
    public static func titleFromFilename(_ name: String) -> String {
        var t = (name as NSString).deletingPathExtension
        t = t.replacingOccurrences(of: "_", with: " ")
        for pattern in [#"\(\s*\d+\s*kbps\s*\)"#, #"\[\s*\d+\s*kbps\s*\]"#, #"\b\d+\s*kbps\b"#] {
            t = t.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        t = t.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " -_."))
    }

    /// Display title: tag title, else a cleaned filename.
    public func displayTitle(filename: String) -> String {
        title ?? Self.titleFromFilename(filename)
    }
}
