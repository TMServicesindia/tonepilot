import Foundation

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

    public init(id: UUID = UUID(), patchId: UUID, volume: Double = 0.8, pan: Double = 0, octave: Int = 0,
                transpose: Int = 0, fineTuneCents: Double = 0, keyRange: KeyRange = .full,
                velocityRange: VelocityRange = .full, enabled: Bool = true, muted: Bool = false,
                solo: Bool = false, midiChannel: UInt8? = nil, envelopeOverride: Envelope? = nil,
                effectsOverride: EffectSettings? = nil) {
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

    public init(id: UUID = UUID(), name: String, layers: [Layer] = [], masterGain: Double = 0.8,
                isFavorite: Bool = false, createdAt: Date = Date(), updatedAt: Date = Date()) {
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
}
