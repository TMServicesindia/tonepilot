import Foundation

/// A MIDI 1.0 channel-voice event. Channels are 1...16 (as shown to musicians).
public enum MIDIEvent: Hashable, Sendable {
    case noteOn(channel: UInt8, note: UInt8, velocity: UInt8)
    case noteOff(channel: UInt8, note: UInt8, velocity: UInt8)
    case controlChange(channel: UInt8, controller: UInt8, value: UInt8)
    case programChange(channel: UInt8, program: UInt8)
    /// 14-bit value 0...16383, centre 8192.
    case pitchBend(channel: UInt8, value: UInt16)
    case channelPressure(channel: UInt8, pressure: UInt8)
    case polyPressure(channel: UInt8, note: UInt8, pressure: UInt8)

    public var channel: UInt8 {
        switch self {
        case .noteOn(let c, _, _), .noteOff(let c, _, _), .controlChange(let c, _, _), .programChange(let c, _),
             .pitchBend(let c, _), .channelPressure(let c, _), .polyPressure(let c, _, _):
            return c
        }
    }

    public var debugDescription: String {
        switch self {
        case let .noteOn(c, n, v): return "ch\(c) Note On  \(NoteName.name(for: Int(n))) (\(n)) vel \(v)"
        case let .noteOff(c, n, v): return "ch\(c) Note Off \(NoteName.name(for: Int(n))) (\(n)) vel \(v)"
        case let .controlChange(c, cc, v): return "ch\(c) CC \(cc)\(MIDIController.name(cc).map { " \($0)" } ?? "") = \(v)"
        case let .programChange(c, p): return "ch\(c) Program \(p)"
        case let .pitchBend(c, v): return "ch\(c) Pitch bend \(Int(v) - 8192)"
        case let .channelPressure(c, p): return "ch\(c) Aftertouch \(p)"
        case let .polyPressure(c, n, p): return "ch\(c) Poly AT \(n) = \(p)"
        }
    }
}

public enum MIDIController {
    public static let modulation: UInt8 = 1
    public static let volume: UInt8 = 7
    public static let expression: UInt8 = 11
    public static let sustain: UInt8 = 64
    public static let sostenuto: UInt8 = 66
    public static let soft: UInt8 = 67
    public static let allSoundOff: UInt8 = 120
    public static let resetAllControllers: UInt8 = 121
    public static let allNotesOff: UInt8 = 123

    public static func name(_ cc: UInt8) -> String? {
        switch cc {
        case modulation: return "(Mod)"
        case volume: return "(Volume)"
        case expression: return "(Expression)"
        case sustain: return "(Sustain)"
        case sostenuto: return "(Sostenuto)"
        case soft: return "(Soft)"
        case allSoundOff: return "(All Sound Off)"
        case resetAllControllers: return "(Reset Controllers)"
        case allNotesOff: return "(All Notes Off)"
        default: return nil
        }
    }
}

/// Parses a raw MIDI 1.0 byte stream (with running status) into events.
/// System real-time bytes (clock, active sensing — the Casio sends active sensing)
/// may appear anywhere and are skipped; SysEx is skipped entirely.
public struct MIDIByteParser: Sendable {
    private var status: UInt8 = 0
    private var data: [UInt8] = []
    private var inSysEx = false

    public init() {}

    public mutating func parse(_ bytes: [UInt8]) -> [MIDIEvent] {
        var events: [MIDIEvent] = []
        for byte in bytes {
            if byte >= 0xF8 { continue } // real-time: does not affect running status
            if byte == 0xF0 { inSysEx = true; status = 0; data.removeAll(); continue }
            if byte == 0xF7 { inSysEx = false; continue }
            if inSysEx { if byte & 0x80 == 0 { continue } else { inSysEx = false } }
            if byte & 0x80 != 0 {
                // System common messages cancel running status; we don't use them.
                status = byte < 0xF0 ? byte : 0
                data.removeAll(keepingCapacity: true)
                continue
            }
            guard status != 0 else { continue }
            data.append(byte)
            if data.count == Self.dataLength(for: status) {
                if let e = Self.makeEvent(status: status, data1: data[0], data2: data.count > 1 ? data[1] : 0) {
                    events.append(e)
                }
                data.removeAll(keepingCapacity: true) // running status: keep `status`
            }
        }
        return events
    }

    static func dataLength(for status: UInt8) -> Int {
        switch status & 0xF0 {
        case 0xC0, 0xD0: return 1
        default: return 2
        }
    }

    static func makeEvent(status: UInt8, data1: UInt8, data2: UInt8) -> MIDIEvent? {
        let channel = (status & 0x0F) + 1
        switch status & 0xF0 {
        case 0x80: return .noteOff(channel: channel, note: data1, velocity: data2)
        case 0x90: return data2 == 0 ? .noteOff(channel: channel, note: data1, velocity: 64)
                                     : .noteOn(channel: channel, note: data1, velocity: data2)
        case 0xA0: return .polyPressure(channel: channel, note: data1, pressure: data2)
        case 0xB0: return .controlChange(channel: channel, controller: data1, value: data2)
        case 0xC0: return .programChange(channel: channel, program: data1)
        case 0xD0: return .channelPressure(channel: channel, pressure: data1)
        case 0xE0: return .pitchBend(channel: channel, value: UInt16(data2) << 7 | UInt16(data1))
        default: return nil
        }
    }

    /// Number of 32-bit words in a Universal MIDI Packet, from the message type nibble of its first word.
    public static func umpWordCount(_ firstWord: UInt32) -> Int {
        switch firstWord >> 28 {
        case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
        case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
        case 0xB, 0xC: return 3
        default: return 4 // 0x5, 0xD, 0xE, 0xF
        }
    }

    /// Decodes every MIDI 1.0 channel-voice message in a run of UMP words, skipping others.
    public static func parseUMPWords<C: Collection>(_ words: C) -> [MIDIEvent] where C.Element == UInt32, C.Index == Int {
        var events: [MIDIEvent] = []
        var i = words.startIndex
        while i < words.endIndex {
            let w = words[i]
            if let e = parseUMP(w) { events.append(e) }
            i += umpWordCount(w)
        }
        return events
    }

    /// Decodes a Universal MIDI Packet word carrying a MIDI 1.0 channel-voice message
    /// (message type 0x2), as delivered by CoreMIDI when the port uses `MIDIProtocolID._1_0`.
    public static func parseUMP(_ word: UInt32) -> MIDIEvent? {
        guard word >> 28 == 0x2 else { return nil }
        let status = UInt8((word >> 16) & 0xFF)
        let d1 = UInt8((word >> 8) & 0x7F)
        let d2 = UInt8(word & 0x7F)
        guard status & 0x80 != 0, status < 0xF0 else { return nil }
        return makeEvent(status: status, data1: d1, data2: d2)
    }
}
