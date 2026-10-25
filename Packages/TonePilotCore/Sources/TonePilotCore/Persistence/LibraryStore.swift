import Foundation

public enum LibraryStoreError: Error, Equatable {
    case unsupportedFutureSchema(Int)
    case corrupt(String)
}

/// Encodes/decodes the library and migrates older schema versions.
/// Migrations operate on the raw JSON object so old files never need old Swift types.
public enum LibraryCodec {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Date's native reference-date seconds round-trip exactly; ISO-8601 would drop
        // sub-second precision and 1970-based seconds pick up floating-point error.
        e.dateEncodingStrategy = .deferredToDate
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        // Accept both numeric dates (current) and ISO-8601 strings (v1 files, hand-edited backups).
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let seconds = try? c.decode(Double.self) { return Date(timeIntervalSinceReferenceDate: seconds) }
            let string = try c.decode(String.self)
            guard let date = ISO8601DateFormatter().date(from: string) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date \(string)")
            }
            return date
        }
        return d
    }

    public static func encode(_ library: Library) throws -> Data {
        var lib = library
        lib.schemaVersion = Library.currentSchemaVersion
        return try encoder().encode(lib)
    }

    public static func decode(_ data: Data) throws -> Library {
        let parsed: Any
        do { parsed = try JSONSerialization.jsonObject(with: data) } catch {
            throw LibraryStoreError.corrupt("Invalid JSON: \(error.localizedDescription)")
        }
        guard var object = parsed as? [String: Any] else {
            throw LibraryStoreError.corrupt("Top level is not an object")
        }
        let version = object["schemaVersion"] as? Int ?? 1
        if version > Library.currentSchemaVersion {
            throw LibraryStoreError.unsupportedFutureSchema(version)
        }
        if version < 2 { object = migrateV1toV2(object) }
        // v2 -> v3 added only optional fields (melody, chord guide, stems, switching, layer
        // expression/filter/EQ, arrangement origin) which decode as absent; no rewrite needed.
        object["schemaVersion"] = Library.currentSchemaVersion
        let migrated = try JSONSerialization.data(withJSONObject: object)
        do {
            return try decoder().decode(Library.self, from: migrated)
        } catch {
            throw LibraryStoreError.corrupt(String(describing: error))
        }
    }

    /// v1 (pre-analysis prototype) had no beat times, tone suggestions or global arrangements.
    static func migrateV1toV2(_ input: [String: Any]) -> [String: Any] {
        var object = input
        if object["globalArrangements"] == nil { object["globalArrangements"] = [Any]() }
        if object["playlists"] == nil { object["playlists"] = [Any]() }
        if let songs = object["songs"] as? [[String: Any]] {
            object["songs"] = songs.map { song -> [String: Any] in
                var s = song
                if s["beatTimes"] == nil { s["beatTimes"] = [Any]() }
                if s["toneSuggestions"] == nil { s["toneSuggestions"] = [Any]() }
                if s["tags"] == nil { s["tags"] = [Any]() }
                return s
            }
        }
        return object
    }
}

/// File-backed persistence. Metadata is a single JSON file; audio and SoundFonts
/// are stored as files in sibling directories and referenced by name.
public final class LibraryStore: @unchecked Sendable {
    public let rootDirectory: URL
    private let queue = DispatchQueue(label: "TonePilot.LibraryStore")

    public var libraryURL: URL { rootDirectory.appendingPathComponent("library.json") }
    public var backupURL: URL { rootDirectory.appendingPathComponent("library.backup.json") }
    public var audioDirectory: URL { rootDirectory.appendingPathComponent("Audio", isDirectory: true) }
    public var soundFontDirectory: URL { rootDirectory.appendingPathComponent("SoundFonts", isDirectory: true) }
    /// Authorised user samples for sample-based patches.
    public var sampleDirectory: URL { rootDirectory.appendingPathComponent("Samples", isDirectory: true) }
    /// Separated stems per song: Stems/<song id>/vocals.wav …
    public func stemDirectory(for songId: UUID) -> URL {
        rootDirectory.appendingPathComponent("Stems", isDirectory: true).appendingPathComponent(songId.uuidString, isDirectory: true)
    }

    public init(rootDirectory: URL) throws {
        self.rootDirectory = rootDirectory
        let fm = FileManager.default
        for dir in [rootDirectory, audioDirectory, soundFontDirectory, sampleDirectory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Loads the library, falling back to the last good backup if the main file is corrupt.
    /// Returns an empty library when nothing has been saved yet.
    public func load() throws -> Library {
        try queue.sync {
            let fm = FileManager.default
            guard fm.fileExists(atPath: libraryURL.path) else { return Library() }
            do {
                return try LibraryCodec.decode(Data(contentsOf: libraryURL))
            } catch let error as LibraryStoreError {
                if case .unsupportedFutureSchema = error { throw error }
                guard fm.fileExists(atPath: backupURL.path) else { throw error }
                return try LibraryCodec.decode(Data(contentsOf: backupURL))
            }
        }
    }

    /// Atomically writes the library and keeps the previous version as a backup.
    public func save(_ library: Library) throws {
        let data = try LibraryCodec.encode(library)
        try queue.sync {
            let fm = FileManager.default
            if fm.fileExists(atPath: libraryURL.path) {
                if fm.fileExists(atPath: backupURL.path) { try fm.removeItem(at: backupURL) }
                try fm.copyItem(at: libraryURL, to: backupURL)
            }
            try data.write(to: libraryURL, options: .atomic)
        }
    }

    /// Copies an imported file into app storage with a collision-free name; returns the stored file name.
    public func importFile(from source: URL, into directory: URL) throws -> String {
        let fm = FileManager.default
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var name = source.lastPathComponent
        var n = 1
        while fm.fileExists(atPath: directory.appendingPathComponent(name).path) {
            n += 1
            name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
        }
        try fm.copyItem(at: source, to: directory.appendingPathComponent(name))
        return name
    }

    /// Copies metadata, samples and stems (not SoundFonts or imported songs unless asked) into
    /// `destination` for backup. Returns the backup folder.
    public func exportBackup(to destination: URL, includeSongAudio: Bool = false) throws -> URL {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = destination.appendingPathComponent("TonePilot Backup \(stamp)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if fm.fileExists(atPath: libraryURL.path) { try fm.copyItem(at: libraryURL, to: folder.appendingPathComponent("library.json")) }
        var dirs = [sampleDirectory, rootDirectory.appendingPathComponent("Stems")]
        if includeSongAudio { dirs.append(audioDirectory) }
        for dir in dirs where fm.fileExists(atPath: dir.path) {
            try fm.copyItem(at: dir, to: folder.appendingPathComponent(dir.lastPathComponent))
        }
        return folder
    }

    /// Deletes a song's separated stems.
    public func deleteStems(for songId: UUID) throws {
        let dir = stemDirectory(for: songId)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }

    /// Deletes a song's imported audio file (used by data-retention controls).
    public func deleteAudio(named name: String) throws {
        let url = audioDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
