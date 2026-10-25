import SwiftUI
import TonePilotCore

enum Theme {
    static let accent = Color(red: 0.98, green: 0.62, blue: 0.20)
    static let panel = Color(white: 0.11)
    static let panelRaised = Color(white: 0.16)
    static let good = Color.green
    static let warn = Color.orange
    static let bad = Color.red
}

/// Shows how sure the analyser is, and whether a value came from the user, an algorithm or a model.
struct ConfidenceBadge: View {
    let confidence: Double
    let provenance: ValueProvenance

    var body: some View {
        let (text, color): (String, Color) = {
            if provenance == .user { return ("You set this", Theme.good) }
            switch confidence {
            case 0.7...: return ("Likely · \(pct)", Theme.good)
            case 0.4..<0.7: return ("Possible · \(pct)", Theme.warn)
            default: return ("Guess · \(pct)", Theme.bad)
            }
        }()
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel(provenance == .user ? "Set by you" : "Confidence \(pct)")
    }

    private var pct: String { "\(Int((confidence * 100).rounded()))%" }
}

struct SourceTypeBadge: View {
    let type: PatchSourceType
    var body: some View {
        Text(type.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((type == .experimentalExtraction ? Theme.warn : Color.blue).opacity(0.2), in: Capsule())
    }
}

/// Output level meter with clip indicator (tap to reset).
struct OutputMeter: View {
    @EnvironmentObject var model: AppModel

    var body: some View { MeterBar(model: model, live: model.live) }
}

/// Observes only the meter values, so the meter redraws without redrawing its screen.
private struct MeterBar: View {
    let model: AppModel
    @ObservedObject var live: LiveState

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(min(1, live.peak)))
                }
            }
            .frame(height: 8)
            Button { model.resetClip() } label: {
                Text("CLIP").font(.caption2.bold())
                    .foregroundStyle(live.clipped ? Color.white : Color.secondary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(live.clipped ? Theme.bad : Color.clear, in: RoundedRectangle(cornerRadius: 4))
            }
            .accessibilityLabel(live.clipped ? "Output clipped, tap to reset" : "No clipping")
        }
    }
}

/// Small MIDI/audio status pill used in headers.
struct ConnectionStatus: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var midi: MIDIInputManager

    var body: some View {
        let casio = midi.sources.first { $0.looksLikeCasio }
        let name = casio?.name ?? midi.sources.first?.name
        HStack(spacing: 6) {
            Circle().fill(name == nil ? Theme.bad : Theme.good).frame(width: 8, height: 8)
            Text(name ?? "No keyboard").font(.caption).lineLimit(1)
            if let last = midi.lastEventAt, Date().timeIntervalSince(last) < 0.5 {
                Image(systemName: "waveform").font(.caption2).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.panelRaised, in: Capsule())
    }
}

/// Visualises which keys of the 61-key Casio a layer covers.
struct KeyRangePreview: View {
    let ranges: [(KeyRange, Color)]
    private let low = Int(KeyRange.casio61.low), high = Int(KeyRange.casio61.high)

    var body: some View {
        GeometryReader { geo in
            let count = high - low + 1
            let w = geo.size.width / CGFloat(count)
            ZStack(alignment: .topLeading) {
                ForEach(0..<count, id: \.self) { i in
                    let note = low + i
                    let black = [1, 3, 6, 8, 10].contains(note % 12)
                    Rectangle()
                        .fill(black ? Color(white: 0.25) : Color(white: 0.85))
                        .frame(width: max(1, w - 0.5), height: geo.size.height)
                        .offset(x: CGFloat(i) * w)
                }
                ForEach(Array(ranges.enumerated()), id: \.offset) { idx, item in
                    let (range, color) = item
                    let a = max(low, Int(range.low)), b = min(high, Int(range.high))
                    if b >= a {
                        Rectangle().fill(color.opacity(0.55))
                            .frame(width: CGFloat(b - a + 1) * w, height: geo.size.height / CGFloat(max(1, ranges.count)))
                            .offset(x: CGFloat(a - low) * w, y: CGFloat(idx) * geo.size.height / CGFloat(max(1, ranges.count)))
                    }
                }
            }
        }
        .frame(height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
    }
}

/// One-octave-plus audition strip so tones can be checked without the keyboard attached.
/// Notes go through the same router as the Casio, so splits/layers behave identically.
struct AuditionStrip: View {
    @EnvironmentObject var model: AppModel
    @State private var base: Int = 60
    @State private var held: Set<Int> = []

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Audition").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { base = max(36, base - 12) } label: { Image(systemName: "chevron.left") }
                Text(NoteName.name(for: base)).font(.caption.monospaced())
                Button { base = min(84, base + 12) } label: { Image(systemName: "chevron.right") }
            }
            HStack(spacing: 2) {
                ForEach(0..<13, id: \.self) { i in
                    let note = base + i
                    let black = [1, 3, 6, 8, 10].contains(note % 12)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(held.contains(note) ? Theme.accent : (black ? Color(white: 0.2) : Color(white: 0.9)))
                        .frame(height: 54)
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !held.contains(note) { held.insert(note); model.audition(note: UInt8(note), on: true) }
                            }
                            .onEnded { _ in held.remove(note); model.audition(note: UInt8(note), on: false) })
                        .accessibilityLabel("Play \(NoteName.name(for: note))")
                }
            }
        }
    }
}

extension Double {
    var mmss: String {
        guard isFinite else { return "--:--" }
        let s = Int(self.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
