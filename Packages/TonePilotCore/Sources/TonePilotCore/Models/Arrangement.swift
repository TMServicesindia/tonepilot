import Foundation

/// The job a sound does in the arrangement. Drives patch choice, key range and effects.
public enum MusicalRole: String, Codable, CaseIterable, Sendable {
    case lead, vocalMelody, harmony, pad, keys, accent, bass, percussion, texture, motif

    public var displayName: String {
        switch self {
        case .lead: return "Lead"
        case .vocalMelody: return "Vocal melody"
        case .harmony: return "Harmony"
        case .pad: return "Sustained pad / strings"
        case .keys: return "Piano / keys"
        case .accent: return "Plucked / bell accents"
        case .bass: return "Bass"
        case .percussion: return "Percussion"
        case .texture: return "Background texture"
        case .motif: return "Instrumental motif"
        }
    }
}

public enum ArrangementOrigin: String, Codable, Sendable {
    case aiOriginal, myVersion, user
}

/// One voice inside a composite tone. Several layers can sound on the same key
/// (stacking), or cover different key ranges (splits) or velocity ranges.
public struct Layer: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var patchId: UUID
    /// Linear gain 0...1 before master gain.
    public var volume: Double
    /// -1 (left) ... 1 (right).
    public var pan: Double
    /// -3...3 octaves.
    public var octave: Int
    /// -12...12 semitones.
    public var transpose: Int
    /// -100...100 cents.
    public var fineTuneCents: Double
    public var keyRange: KeyRange
    public var velocityRange: VelocityRange
    public var enabled: Bool
    public var muted: Bool
    public var solo: Bool
    /// MIDI channel 1...16 this layer listens to; nil = any channel (omni).
    public var midiChannel: UInt8?
    /// Overrides the patch's envelope (attack/release) when set.
    public var envelopeOverride: Envelope?
    /// Overrides the patch's effects when set.
    public var effectsOverride: EffectSettings?
    /// Overrides the patch's filter when set.
    public var filterOverride: FilterSettings?
    /// Overrides the patch's mono/glide/vibrato/bend behaviour when set.
    public var expressionOverride: ExpressionSettings?
    /// What this layer does in the arrangement (set by the AutoArranger, editable).
    public var role: MusicalRole?

    public init(id: UUID = UUID(), patchId: UUID, volume: Double = 0.8, pan: Double = 0, octave: Int = 0,
                transpose: Int = 0, fineTuneCents: Double = 0, keyRange: KeyRange = .full,
                velocityRange: VelocityRange = .full, enabled: Bool = true, muted: Bool = false,
                solo: Bool = false, midiChannel: UInt8? = nil, envelopeOverride: Envelope? = nil,
                effectsOverride: EffectSettings? = nil, filterOverride: FilterSettings? = nil,
                expressionOverride: ExpressionSettings? = nil, role: MusicalRole? = nil) {
        self.filterOverride = filterOverride
        self.expressionOverride = expressionOverride
        self.role = role
        self.id = id
        self.patchId = patchId
        self.volume = max(0, min(1, volume))
        self.pan = max(-1, min(1, pan))
        self.octave = max(-3, min(3, octave))
        self.transpose = max(-12, min(12, transpose))
        self.fineTuneCents = max(-100, min(100, fineTuneCents))
        self.keyRange = keyRange
        self.velocityRange = velocityRange
        self.enabled = enabled
        self.muted = muted
        self.solo = solo
        self.midiChannel = midiChannel
        self.envelopeOverride = envelopeOverride
        self.effectsOverride = effectsOverride
    }

    /// Total semitone offset applied to incoming notes.
    public var semitoneOffset: Int { octave * 12 + transpose }
}

/// A saved composite tone: a stack of layers plus master gain.
/// Several song sections may point at the same arrangement.
public struct Arrangement: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var layers: [Layer]
    /// Linear master gain 0...1.
    public var masterGain: Double
    public var isFavorite: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// Master EQ / effect returns (nil = defaults).
    public var master: MasterEffects?
    /// AI Original (kept unchanged) vs My Version (user-editable copy) vs plain user tone.
    public var origin: ArrangementOrigin?
    /// For My Version: the AI Original it was copied from.
    public var derivedFrom: UUID?
    /// Why the AutoArranger built it this way (shown in the UI).
    public var rationale: String?

    public init(id: UUID = UUID(), name: String, layers: [Layer] = [], masterGain: Double = 0.8,
                isFavorite: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date(),
                master: MasterEffects? = nil, origin: ArrangementOrigin? = nil, derivedFrom: UUID? = nil,
                rationale: String? = nil) {
        self.master = master
        self.origin = origin
        self.derivedFrom = derivedFrom
        self.rationale = rationale
        self.id = id
        self.name = name
        self.layers = layers
        self.masterGain = max(0, min(1, masterGain))
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Layers that should currently make sound, honouring enable, mute and solo.
    /// If any enabled layer is soloed, only soloed layers sound.
    public var audibleLayers: [Layer] {
        let enabled = layers.filter { $0.enabled }
        let soloed = enabled.filter { $0.solo }
        if !soloed.isEmpty { return soloed }
        return enabled.filter { !$0.muted }
    }

    public var masterEffects: MasterEffects { master ?? MasterEffects() }

    /// Editable copy of an AI Original, keeping layer ids so section links stay valid.
    public func makeMyVersion() -> Arrangement {
        var copy = self
        copy.id = UUID()
        copy.origin = .myVersion
        copy.derivedFrom = id
        copy.name = name.replacingOccurrences(of: " (AI)", with: "") + " (My Version)"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        return copy
    }

    /// Duplicate with fresh ids (for "Duplicate tone").
    public func duplicated(name newName: String? = nil) -> Arrangement {
        var copy = self
        copy.id = UUID()
        copy.name = newName ?? name + " copy"
        copy.origin = .user
        copy.derivedFrom = nil
        copy.layers = layers.map { var l = $0; l.id = UUID(); return l }
        copy.createdAt = Date()
        copy.updatedAt = Date()
        return copy
    }
}
