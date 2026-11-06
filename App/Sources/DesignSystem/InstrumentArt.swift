import SwiftUI
import TonePilotCore

/// TonePilot's own instrument drawings (vector assets in Assets.xcassets/Instruments, drawn for the app:
/// licence-free, reusable on Android). Shaded drawings keep their colours; line drawings (guitar, brass,
/// pad) are templates tinted with the family ink.
enum InstrumentDrawing: String, CaseIterable {
    case violin, flute, piano, tabla, voice, drums, bass, synth, veena, guitar, brass, pad

    var asset: String { "instrument.\(rawValue)" }
    var isTemplate: Bool { self == .guitar || self == .brass || self == .pad }

    /// Family tint (design token `color.family`): radial gradient light → dark, and the ink for line drawings.
    var tint: (light: Color, dark: Color, ink: Color) {
        switch self {
        case .violin: return (Color(hex: 0x6A3C1C), Color(hex: 0x241309), Color(hex: 0xFFB866))
        case .flute, .pad: return (Color(hex: 0x1C5A54), Color(hex: 0x0C1F1D), Color(hex: 0x6FE0D2))
        case .piano: return (Color(hex: 0x34397A), Color(hex: 0x121330), Color(hex: 0xA9B2FF))
        case .veena, .guitar: return (Color(hex: 0x68244A), Color(hex: 0x220B18), Color(hex: 0xFF9CC8))
        case .tabla, .drums: return (Color(hex: 0x6A4416), Color(hex: 0x231606), Color(hex: 0xFFD27A))
        case .voice: return (Color(hex: 0x642656), Color(hex: 0x210B1C), Color(hex: 0xFF9BD9))
        case .bass: return (Color(hex: 0x43317A), Color(hex: 0x16102C), Color(hex: 0xC7B1FF))
        case .synth: return (Color(hex: 0x1F466A), Color(hex: 0x0A1724), Color(hex: 0x7FD0FF))
        case .brass: return (Color(hex: 0x62521A), Color(hex: 0x221C08), Color(hex: 0xFFE36E))
        }
    }

    static func forFamily(_ family: InstrumentFamily) -> InstrumentDrawing {
        switch family {
        case .piano, .electricPiano, .organ, .bell, .mallet: return .piano
        case .strings, .synthStrings: return .violin
        case .pad, .choir: return .pad
        case .flute, .reed: return .flute
        case .brass: return .brass
        case .guitar: return .guitar
        case .pluck, .ethnic: return .veena
        case .synthLead, .other: return .synth
        case .bass: return .bass
        case .percussion: return .tabla
        }
    }

    /// For a separated part (Mix).
    static func forPart(_ kind: StemInfo.Kind) -> InstrumentDrawing {
        switch kind {
        case .vocals: return .voice
        case .drums: return .drums
        case .bass: return .bass
        case .piano: return .piano
        case .guitar: return .guitar
        case .backing: return .pad
        case .lead, .other: return .violin
        }
    }
}

/// An instrument drawing on its family-tinted tile. Decorative: the name next to it carries the meaning.
struct InstrumentTile: View {
    let drawing: InstrumentDrawing
    var size: CGFloat = DS.Size.artwork
    var selected = false

    var body: some View {
        let t = drawing.tint
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(RadialGradient(colors: [t.light, t.dark], center: UnitPoint(x: 0.3, y: 0.25), startRadius: 0, endRadius: size * 0.9))
            Image(drawing.asset)
                .renderingMode(drawing.isTemplate ? .template : .original)
                .resizable().scaledToFit()
                .foregroundStyle(t.ink)
                .padding(size * (drawing.isTemplate ? 0.2 : 0.1))
                .shadow(color: .black.opacity(0.35), radius: size * 0.05, y: size * 0.04)
        }
        .frame(width: size, height: size)
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .strokeBorder(selected ? DS.Palette.accent : Color.white.opacity(0.06), lineWidth: selected ? 2 : 1)
        }
        .accessibilityHidden(true)
    }
}
