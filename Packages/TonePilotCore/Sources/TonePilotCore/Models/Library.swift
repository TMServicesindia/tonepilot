import Foundation

/// A suggested patch for a song or section. `method` tells the UI how the
/// suggestion was produced so heuristics are never presented as AI recognition.
public struct ToneSuggestion: Codable, Hashable, Identifiable, Sendable {
    public enum Method: String, Codable, Sendable {
        /// Rules over DSP features (spectral brightness, onset density...). Milestone 1.
        case featureHeuristic
        /// Instrument-recognition model output. Milestone 5.
        case instrumentModel
    }

    public var id: UUID
    public var sectionId: UUID?
    public var family: InstrumentFamily
    public var patchId: UUID
    public var reason: String
    public var confidence: Double
    public var method: Method

    public init(id: UUID = UUID(), sectionId: UUID?, family: InstrumentFamily, patchId: UUID, reason: String,
                confidence: Double, method: Method) {
        self.id = id
        self.sectionId = sectionId
        self.family = family
        self.patchId = patchId
        self.reason = reason
        self.confidence = max(0, min(1, confidence))
        self.method = method
    }
}

/// Everything the user owns, persisted as one versioned JSON document.
/// Large audio files live in separate directories and are referenced by file name.
public struct Library: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 3

    public var schemaVersion: Int
    public var songs: [Song]
    public var patches: [InstrumentPatch]
    public var playlists: [Playlist]
    /// Arrangements not tied to a song (user's general-purpose tones).
    public var globalArrangements: [Arrangement]

    public init(songs: [Song] = [], patches: [InstrumentPatch] = [], playlists: [Playlist] = [],
                globalArrangements: [Arrangement] = []) {
        self.schemaVersion = Library.currentSchemaVersion
        self.songs = songs
        self.patches = patches
        self.playlists = playlists
        self.globalArrangements = globalArrangements
    }

    public func patch(id: UUID) -> InstrumentPatch? { patches.first { $0.id == id } }

    public func song(id: UUID) -> Song? { songs.first { $0.id == id } }

    public mutating func upsert(_ song: Song) {
        var s = song
        s.updatedAt = Date()
        if let i = songs.firstIndex(where: { $0.id == song.id }) { songs[i] = s } else { songs.append(s) }
    }

    public mutating func upsert(_ patch: InstrumentPatch) {
        if let i = patches.firstIndex(where: { $0.id == patch.id }) { patches[i] = patch } else { patches.append(patch) }
    }

    public mutating func deleteSong(id: UUID) {
        songs.removeAll { $0.id == id }
        for i in playlists.indices { playlists[i].songIds.removeAll { $0 == id } }
    }

    /// Case-insensitive search over title, artist, film, composer, language and tags.
    public func searchSongs(_ query: String) -> [Song] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return songs }
        return songs.filter { song in
            let fields = [song.title, song.artist, song.film, song.composer, song.language].compactMap { $0 } + song.tags
            return fields.contains { $0.lowercased().contains(q) }
        }
    }

    /// Adds factory patches that are missing (by id) without touching user edits.
    public mutating func mergeFactoryPatches(_ factory: [InstrumentPatch]) {
        let existing = Set(patches.map(\.id))
        patches.append(contentsOf: factory.filter { !existing.contains($0.id) })
    }
}
