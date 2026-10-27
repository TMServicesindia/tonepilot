import Foundation

public enum SectionType: String, Codable, CaseIterable, Sendable {
    case intro, instrumentalIntro, verse, preChorus, chorus, interlude, instrumentalBreak, bridge, outro, custom

    public var displayName: String {
        switch self {
        case .intro: return "Intro"
        case .instrumentalIntro: return "Instrumental intro"
        case .verse: return "Verse / Pallavi"
        case .preChorus: return "Pre-chorus"
        case .chorus: return "Chorus / Hook"
        case .interlude: return "Interlude"
        case .instrumentalBreak: return "Instrumental break"
        case .bridge: return "Bridge / Charanam"
        case .outro: return "Outro"
        case .custom: return "Custom"
        }
    }
}

public struct SongSection: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var type: SectionType
    /// User-visible label, e.g. "Interlude 2".
    public var label: String
    /// Seconds from the start of the audio.
    public var startTime: Double
    public var endTime: Double
    public var startBar: Int?
    public var endBar: Int?
    /// 0...1 confidence of the boundary/label; 1 for user-created sections.
    public var confidence: Double
    public var provenance: ValueProvenance
    /// Arrangement (composite tone) to load when this section is selected.
    public var arrangementId: UUID?
    /// Group id of sections the analyser thinks repeat each other (A, B, ...).
    public var repetitionGroup: String?
    public var notes: String?
    /// What the analysis heard in this section (lead line, pad, bass, percussion…).
    public var activity: [SectionActivity]?
    /// Local key when it differs from the song key (key change).
    public var key: Estimate<MusicalKey>?
    /// Sound-character measurements, kept so a section can be re-arranged without re-analysis.
    public var timbre: SectionTimbre?
    /// The song's peak section (loudest, late, clearly above the rest).
    public var isClimax: Bool?
    /// Instrument families heard in this section (family → 0...1), from on-device recognition
    /// of its separated Lead / Music parts. Keys: `InstrumentEvidence` families.
    public var instruments: [String: Double]?

    public init(id: UUID = UUID(), type: SectionType, label: String? = nil, startTime: Double, endTime: Double,
                startBar: Int? = nil, endBar: Int? = nil, confidence: Double = 1,
                provenance: ValueProvenance = .user, arrangementId: UUID? = nil,
                repetitionGroup: String? = nil, notes: String? = nil) {
        self.id = id
        self.type = type
        self.label = label ?? type.displayName
        self.startTime = min(startTime, endTime)
        self.endTime = max(startTime, endTime)
        self.startBar = startBar
        self.endBar = endBar
        self.confidence = confidence
        self.provenance = provenance
        self.arrangementId = arrangementId
        self.repetitionGroup = repetitionGroup
        self.notes = notes
    }

    public var duration: Double { endTime - startTime }
}

public struct ChordEvent: Codable, Hashable, Sendable {
    public var time: Double
    public var duration: Double
    /// e.g. "Am", "C", "N" for no chord.
    public var symbol: String
    public var confidence: Double
    /// Next-best readings, most likely first.
    public var alternatives: [String]?

    public init(time: Double, duration: Double, symbol: String, confidence: Double, alternatives: [String]? = nil) {
        self.time = time
        self.duration = duration
        self.symbol = symbol
        self.confidence = confidence
        self.alternatives = alternatives
    }
}

public enum SongSourceType: String, Codable, Sendable {
    /// Audio file the user imported from Files (MP3, M4A, WAV, AIFF...).
    case importedFile
    /// Only a link + metadata; no audio is downloaded or analysed.
    case youtubeLink
    /// A song entry with no audio (user only wants to store tones/sections).
    case manual
    /// Analysed by listening (microphone) while it played from a streaming service the user is
    /// licensed to use. No audio is stored; `sourceReference` may hold the service name or link.
    case listened
}

public enum AnalysisStatus: String, Codable, Sendable {
    case notStarted, running, completed, failed, unavailable
}

public struct Song: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var artist: String?
    public var film: String?
    public var composer: String?
    public var language: String?
    public var tags: [String]
    public var sourceType: SongSourceType
    /// File name inside the app's Audio directory (importedFile) or URL string (youtubeLink).
    public var sourceReference: String?
    /// The user confirmed they own or are authorised to process this audio.
    public var userConfirmedRights: Bool
    public var duration: Double?
    public var analysisStatus: AnalysisStatus
    public var analysisError: String?
    public var bpm: Estimate<Double>?
    public var key: Estimate<MusicalKey>?
    public var chordEvents: [ChordEvent]
    /// Beat times in seconds from the analysis (empty if not analysed).
    public var beatTimes: [Double]
    public var sections: [SongSection]
    public var arrangements: [Arrangement]
    public var toneSuggestions: [ToneSuggestion]
    public var notes: String?
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Lead/vocal melody estimate (editable).
    public var melody: MelodyTrack?
    /// Left-hand Root → Fifth → Root guidance (editable).
    public var chordGuide: [ChordGuideStep]?
    /// Beats per bar estimate (3 or 4).
    public var timeSignature: Estimate<Int>?
    /// Separated stems produced by the optional backend.
    public var stems: [StemInfo]?
    /// How tones change while performing this song.
    public var switching: SwitchingSettings?
    /// Accompaniment the app can play along (all off by default).
    public var accompaniment: AccompanimentSettings?
    /// Semitones applied to guides and accompaniment (the user's chosen performance key).
    public var performanceTranspose: Int?
    /// Scale notes, rhythmic feel, style, bass line, and any analysis parts that failed.
    public var insights: SongInsights?
    /// Artist / album read from the file's tags (display only).
    public var album: String?
    /// Song Arpeggio: broken-chord patterns learned per section.
    public var arpeggio: SongArpeggio?

    public init(id: UUID = UUID(), title: String, artist: String? = nil, film: String? = nil,
                composer: String? = nil, language: String? = nil, tags: [String] = [],
                sourceType: SongSourceType = .manual, sourceReference: String? = nil,
                userConfirmedRights: Bool = false, duration: Double? = nil,
                analysisStatus: AnalysisStatus = .notStarted, analysisError: String? = nil,
                bpm: Estimate<Double>? = nil, key: Estimate<MusicalKey>? = nil, chordEvents: [ChordEvent] = [],
                beatTimes: [Double] = [], sections: [SongSection] = [], arrangements: [Arrangement] = [],
                toneSuggestions: [ToneSuggestion] = [], notes: String? = nil, isFavorite: Bool = false,
                createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.artist = artist
        self.film = film
        self.composer = composer
        self.language = language
        self.tags = tags
        self.sourceType = sourceType
        self.sourceReference = sourceReference
        self.userConfirmedRights = userConfirmedRights
        self.duration = duration
        self.analysisStatus = analysisStatus
        self.analysisError = analysisError
        self.bpm = bpm
        self.key = key
        self.chordEvents = chordEvents
        self.beatTimes = beatTimes
        self.sections = sections
        self.arrangements = arrangements
        self.toneSuggestions = toneSuggestions
        self.notes = notes
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func arrangement(for section: SongSection) -> Arrangement? {
        guard let id = section.arrangementId else { return nil }
        return arrangements.first { $0.id == id }
    }

    /// Sections sorted by start time.
    public var orderedSections: [SongSection] { sections.sorted { $0.startTime < $1.startTime } }
}

public struct Playlist: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var songIds: [UUID]

    public init(id: UUID = UUID(), name: String, songIds: [UUID] = []) {
        self.id = id
        self.name = name
        self.songIds = songIds
    }
}


/// Evidence-based description of what plays in a section.
public struct SectionActivity: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Inferred from spectral features of the full mix.
        case mixFeatures
        /// Measured on separated stems (backend).
        case stems
    }
    public var role: MusicalRole
    /// 0...1 how strongly the role is present.
    public var level: Double
    public var evidence: String
    public var source: Source

    public init(role: MusicalRole, level: Double, evidence: String, source: Source) {
        self.role = role
        self.level = max(0, min(1, level))
        self.evidence = evidence
        self.source = source
    }
}

public struct StemInfo: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case vocals, drums, bass, other, piano, guitar
        /// The Music part split in two (LeadSplitter): its main melodic line, and everything else.
        case lead, backing
    }
    public var kind: Kind
    /// File name in the song's stem folder.
    public var fileName: String
    /// Model that produced it, e.g. "htdemucs" or "htdemucs_6s".
    public var model: String
    /// Per-section RMS level (section id -> 0...1), for activity detection.
    public var sectionLevels: [UUID: Double]?

    public init(kind: Kind, fileName: String, model: String, sectionLevels: [UUID: Double]? = nil) {
        self.kind = kind
        self.fileName = fileName
        self.model = model
        self.sectionLevels = sectionLevels
    }
}
