import Foundation

/// MIDI note number 0...127. Middle C (C4) is 60.
public typealias MIDINote = UInt8

public enum NoteName {
    public static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// "C4" style name for a MIDI note (60 -> "C4").
    public static func name(for note: Int) -> String {
        let pc = ((note % 12) + 12) % 12
        let octave = note / 12 - 1
        return "\(sharpNames[pc])\(octave)"
    }
}

/// Inclusive range of MIDI notes a layer responds to.
public struct KeyRange: Codable, Hashable, Sendable {
    public var low: MIDINote
    public var high: MIDINote

    public init(low: MIDINote = 0, high: MIDINote = 127) {
        self.low = min(low, high)
        self.high = max(low, high)
    }

    public static let full = KeyRange(low: 0, high: 127)
    /// The CT-X870IN has 61 keys: C2 (36) ... C7 (96) without keyboard transpose/octave shift.
    public static let casio61 = KeyRange(low: 36, high: 96)

    public func contains(_ note: MIDINote) -> Bool { note >= low && note <= high }
}

/// Inclusive velocity range 1...127 a layer responds to (velocity 0 is note-off).
public struct VelocityRange: Codable, Hashable, Sendable {
    public var low: UInt8
    public var high: UInt8

    public init(low: UInt8 = 1, high: UInt8 = 127) {
        self.low = min(low, high)
        self.high = max(low, high)
    }

    public static let full = VelocityRange()

    public func contains(_ velocity: UInt8) -> Bool { velocity >= low && velocity <= high }
}

/// A musical key estimate such as "A minor".
public struct MusicalKey: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Sendable { case major, minor }
    /// Pitch class 0 = C ... 11 = B.
    public var tonic: Int
    public var mode: Mode

    public init(tonic: Int, mode: Mode) {
        self.tonic = ((tonic % 12) + 12) % 12
        self.mode = mode
    }

    public var displayName: String { "\(NoteName.sharpNames[tonic]) \(mode.rawValue)" }
}

/// Where a value came from. User-entered values always win over estimates.
public enum ValueProvenance: String, Codable, Sendable {
    /// Produced by an on-device DSP algorithm.
    case algorithm
    /// Produced by a machine-learning model.
    case model
    /// Entered or corrected by the user; always trusted over estimates.
    case user
}

/// Any value produced by analysis is wrapped with how confident we are
/// and where it came from, so the UI never presents guesses as facts.
public struct Estimate<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    public typealias Provenance = ValueProvenance

    public var value: Value
    /// 0...1. Meaningless (1.0) for user-entered values.
    public var confidence: Double
    public var provenance: Provenance

    public init(_ value: Value, confidence: Double, provenance: Provenance) {
        self.value = value
        self.confidence = max(0, min(1, confidence))
        self.provenance = provenance
    }

    public static func user(_ value: Value) -> Estimate { Estimate(value, confidence: 1, provenance: .user) }
}
