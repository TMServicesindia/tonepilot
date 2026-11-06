import SwiftUI
import TonePilotCore

// The Play page (performance view, screen spec §2.4 / mockup v9 #5): section now and next, the Song Map
// timeline, the chord card with the Casio keys guide, and the tone row. Views that follow the song
// position observe `LiveState` only, with fixed heights, so nothing reflows while playing.

// MARK: Song Map helpers

enum SongMapStyle {
    /// Section energy 0...1: the analysis' mood energy, else loudness relative to the song.
    static func energies(_ song: Song) -> [UUID: Double] {
        let loud = song.sections.compactMap { $0.timbre?.loudness }
        let lo = loud.min() ?? 0, hi = loud.max() ?? 1
        var out: [UUID: Double] = [:]
        for s in song.sections {
            if let e = song.understanding?.moods[s.id.uuidString]?.energy { out[s.id] = e }
            else if let l = s.timbre?.loudness, hi > lo { out[s.id] = (l - lo) / (hi - lo) }
            else { out[s.id] = 0.6 }
        }
        return out
    }

    /// Colour per repetition group, in order of first appearance (repeats share a colour).
    static func groupColors(_ song: Song) -> [UUID: Color] {
        var order: [String] = []
        var out: [UUID: Color] = [:]
        for s in song.orderedSections {
            let key = s.repetitionGroup.map { "\($0)-\(s.type.rawValue)" } ?? s.id.uuidString
            if !order.contains(key) { order.append(key) }
            out[s.id] = DS.Palette.group[(order.firstIndex(of: key) ?? 0) % DS.Palette.group.count]
        }
        return out
    }

    /// Sections that are the hook (the hook section and its repeats).
    static func hookIds(_ song: Song) -> Set<UUID> {
        guard let hook = song.understanding?.hook, let h = song.sections.first(where: { $0.id == hook.sectionId }) else { return [] }
        return Set(song.sections.filter { $0.id == h.id || ($0.repetitionGroup != nil && $0.repetitionGroup == h.repetitionGroup && $0.type == h.type) }.map(\.id))
    }
}

// MARK: Song Map timeline

/// The song as blocks (width = length, height = energy, colour = repeats, amber = now, ★ = hook) with the
/// playhead. Tap a block to jump there; VoiceOver: swipe up / down to move between sections.
struct SongMapTimeline: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View { SongMapContent(song: song, live: model.live) }
}

private struct SongMapContent: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    @ObservedObject var live: LiveState

    var body: some View {
        let duration = max(song.duration ?? song.sections.map(\.endTime).max() ?? 1, 1)
        let pos = live.position ?? model.cursor
        let sections = song.orderedSections
        let current = sections.last { $0.startTime <= pos + 0.01 }
        let energy = SongMapStyle.energies(song)
        let colors = SongMapStyle.groupColors(song)
        let hooks = SongMapStyle.hookIds(song)
        VStack(spacing: DS.Space.xs) {
            GeometryReader { geo in
                Canvas { ctx, size in
                    let top: CGFloat = 14
                    for s in sections {
                        let x = size.width * s.startTime / duration
                        let w = max(2, size.width * (s.endTime - s.startTime) / duration - 2)
                        let h = (size.height - top) * (0.3 + 0.7 * min(1, max(0, energy[s.id] ?? 0.6)))
                        let rect = CGRect(x: x, y: size.height - h, width: w, height: h)
                        let isNow = current?.id == s.id
                        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(isNow ? DS.Palette.accent : (colors[s.id] ?? .gray)))
                        if hooks.contains(s.id) {
                            ctx.draw(Text("★").font(.caption2.weight(.bold)).foregroundColor(.white), at: CGPoint(x: x + w / 2, y: size.height - h - 7))
                        }
                    }
                    let px = size.width * min(1, max(0, pos / duration))
                    ctx.fill(Path(CGRect(x: px - 1, y: top - 4, width: 2, height: size.height - top + 4)), with: .color(.white))
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    let t = Double(location.x / max(1, geo.size.width)) * duration
                    if let s = sections.last(where: { $0.startTime <= t }) { model.studioJump(to: s.id) }
                }
            }
            .frame(height: 64)
            HStack {
                Text(pos.mmss)
                Spacer()
                Text("Tap the map to jump").foregroundStyle(DS.Palette.textTertiary)
                Spacer()
                Text(duration.mmss)
            }
            .font(DS.Text.numericSmall).foregroundStyle(DS.Palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Song map")
        .accessibilityValue("\(current?.label ?? "Start"), \(pos.mmss) of \(duration.mmss)")
        .accessibilityHint("Swipe up or down to jump between sections")
        .accessibilityAdjustableAction { direction in
            guard let i = sections.firstIndex(where: { $0.id == current?.id }) ?? (sections.isEmpty ? nil : 0) else { return }
            let j = direction == .increment ? min(sections.count - 1, i + 1) : max(0, i - 1)
            model.studioJump(to: sections[j].id)
        }
        .accessibilityIdentifier("play.map")
    }
}

// MARK: Chord card + Casio keys guide

/// Chord now (large), the next three, and the keys to press lit on a Casio-style keyboard strip:
/// left-hand chord keys in amber, the next melody note in teal. Tap to correct the chord.
struct ChordKeysCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    /// The chord step under the playhead (nil when there is none).
    let onCorrect: (UUID?) -> Void

    var body: some View { ChordKeysContent(song: song, live: model.live, onCorrect: onCorrect) }
}

private struct ChordKeysContent: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    @ObservedObject var live: LiveState
    let onCorrect: (UUID?) -> Void

    private static let melodyTeal = Color(hex: 0x6FE0D2)

    var body: some View {
        let t = live.position ?? model.cursor
        let steps = song.chordGuide ?? []
        let transpose = song.performanceTranspose ?? 0
        let current = ChordGuide.step(at: t, in: steps)
        let upcoming = Array(steps.filter { $0.time > t + 0.01 }.prefix(3))
        let left = (current?.pattern ?? []).map { $0 + transpose }
        let offset = AutoArranger.guideOffset(for: model.activeArrangement)
        let melodyNote = song.melody?.notes.first { $0.end > t }.map { $0.midi + offset + transpose }
        Button { onCorrect(current?.id) } label: {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("CHORD").font(DS.Text.metadata.weight(.semibold)).foregroundStyle(DS.Palette.textSecondary)
                        Text(current.map { name($0, transpose) } ?? "—")
                            .font(DS.Text.display).foregroundStyle(DS.Palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Spacer(minLength: DS.Space.s)
                    VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                        Text("then").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                        HStack(spacing: DS.Space.l) {
                            ForEach(Array(upcoming.enumerated()), id: \.element.id) { i, s in
                                Text(name(s, transpose)).font(.title3.weight(.semibold))
                                    .foregroundStyle(DS.Palette.textPrimary.opacity(1 - Double(i) * 0.3))
                            }
                        }
                    }
                }
                CasioKeysGuide(left: left, melody: melodyNote)
                    .frame(height: 50)
                HStack {
                    legend(DS.Palette.accent, current?.isDrone == true ? "Sa–Pa drone" : "Left hand " + left.map(Self.noteLetter).joined(separator: " · "))
                    Spacer()
                    if let m = melodyNote { legend(Self.melodyTeal, "Next melody note \(Self.noteLetter(m))") }
                }
                .opacity(current == nil ? 0 : 1)
            }
            .dsSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(current.map { "Chord \(name($0, transpose))" } ?? "No chord")
        .accessibilityHint("Opens chord correction")
        .accessibilityIdentifier("play.chord")
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: DS.Space.xs) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
        }
    }

    private func name(_ step: ChordGuideStep, _ transpose: Int) -> String {
        guard transpose != 0, let c = ChordSymbol(step.chord) else { return step.chord }
        return c.transposed(transpose).name
    }

    static func noteLetter(_ midi: Int) -> String { NoteName.sharpNames[((midi % 12) + 12) % 12] }
}

/// A 3-octave Casio-style keyboard strip that lights the left-hand chord keys (amber) and the next
/// melody note (teal). Drawn in one `Canvas` (cheap to redraw with the song position).
struct CasioKeysGuide: View {
    let left: [Int]
    let melody: Int?

    var body: some View {
        Canvas { ctx, size in
            let low = (left.min() ?? 48)
            let start = low - ((low % 12) + 12) % 12          // the C at or below the chord
            let whitePCs = [0, 2, 4, 5, 7, 9, 11]
            var whites: [Int] = []
            for octave in 0..<3 { for pc in whitePCs { whites.append(start + octave * 12 + pc) } }
            let kw = size.width / CGFloat(whites.count)
            let lit = Set(left)
            for (i, note) in whites.enumerated() {
                let r = CGRect(x: CGFloat(i) * kw + 0.5, y: 0, width: kw - 1, height: size.height)
                let color: Color = lit.contains(note) ? DS.Palette.accent : (note == melody ? Color(hex: 0x6FE0D2) : Color(hex: 0xF4F4F6))
                ctx.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(color))
            }
            // Black keys: after C, D, F, G, A of each octave.
            for (i, note) in whites.enumerated() where [0, 2, 5, 7, 9].contains(((note - start) % 12 + 12) % 12) && i < whites.count - 1 {
                let black = note + 1
                let r = CGRect(x: CGFloat(i + 1) * kw - kw * 0.3, y: 0, width: kw * 0.6, height: size.height * 0.58)
                let color: Color = lit.contains(black) ? DS.Palette.accent : (black == melody ? Color(hex: 0x6FE0D2) : Color(hex: 0x16161B))
                ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(color))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: Tone row

/// The tone playing now, with its instrument drawings; opens the Tone page.
struct ToneRow: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let action: () -> Void

    var body: some View {
        let tone = model.activeArrangement
        let drawings = Self.drawings(tone, library: model.library)
        Button(action: action) {
            HStack(spacing: DS.Space.m) {
                HStack(spacing: -12) {
                    ForEach(drawings.isEmpty ? [InstrumentDrawing.piano] : drawings, id: \.self) { d in
                        InstrumentTile(drawing: d, size: 40)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.Palette.surface, lineWidth: 3))
                    }
                }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(song.understanding?.hook != nil && model.isUsingMainTone(song) ? "Tone · from the hook" : "Tone")
                        .font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                    Text(tone?.name.replacingOccurrences(of: " (My Version)", with: "") ?? "Choose a tone")
                        .font(DS.Text.body.weight(.semibold)).foregroundStyle(DS.Palette.textPrimary).lineLimit(2)
                }
                Spacer(minLength: DS.Space.s)
                Image(systemName: "chevron.right").font(DS.Text.metadata.weight(.semibold)).foregroundStyle(DS.Palette.textTertiary)
            }
            .frame(minHeight: DS.Size.touchTarget)
            .dsSurface(padding: DS.Space.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the Tone page")
        .accessibilityIdentifier("play.tone")
    }

    /// Up to two distinct drawings for the tone's playing layers, in layer order.
    static func drawings(_ tone: Arrangement?, library: Library) -> [InstrumentDrawing] {
        var out: [InstrumentDrawing] = []
        for layer in tone?.layers ?? [] where !layer.muted {
            guard let family = library.patch(id: layer.patchId)?.family else { continue }
            let d = InstrumentDrawing.forFamily(family)
            if !out.contains(d) { out.append(d) }
            if out.count == 2 { break }
        }
        return out
    }
}
