import SwiftUI
import TonePilotCore

/// A song's cover (screen spec §0 "Song covers"): the artwork embedded in the song's own file when it has
/// one, otherwise a generated TonePilot cover — mood sets the colours, sections the shapes, the hook is
/// amber. Large (≥ 90 pt): D2 "Ring over Aura"; small: D3 "Halo". Drawn in a Canvas, flattened with
/// `drawingGroup` (cheap in lists).
struct SongCover: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let image = model.artworks[song.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                GeneratedCover(song: song, large: size >= 90)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .onAppear { model.loadArtwork(for: song) }
        .accessibilityHidden(true)
    }
}

/// The generated cover. Deterministic per song (same song, same cover).
struct GeneratedCover: View {
    let song: Song
    let large: Bool

    var body: some View {
        let m = CoverModel(song: song)
        Canvas { ctx, size in
            let S = min(size.width, size.height)
            // Mood background: dark base → mood light top-right → warm glow bottom-left.
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [m.mood[0], Color(hex: 0x0C0C12)]), startPoint: .zero, endPoint: CGPoint(x: S, y: S)))
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [m.mood[1].opacity(0.8), m.mood[1].opacity(0)]), center: CGPoint(x: S * 0.75, y: S * 0.2), startRadius: 2, endRadius: S * 0.85))
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [m.mood[2].opacity(0.4), m.mood[2].opacity(0)]), center: CGPoint(x: S * 0.1, y: S * 0.95), startRadius: 1, endRadius: S * 0.6))
            if large { drawRingOverAura(ctx, S, m) } else { drawHalo(ctx, S, m) }
        }
        .drawingGroup()
    }

    private func drawRingOverAura(_ ctx: GraphicsContext, _ S: CGFloat, _ m: CoverModel) {
        let mid = S * 0.62, n = 64
        for i in 0..<n {
            let f = Double(i) / Double(n)
            let sec = m.section(at: f)
            let h = CGFloat(m.wave(i, sec.energy)) * S * 0.36
            let x = S * 0.04 + CGFloat(i) * (S * 0.92 / CGFloat(n))
            let r = CGRect(x: x, y: mid - h / 2, width: S * 0.92 / CGFloat(n) * 0.55, height: h)
            ctx.fill(Path(roundedRect: r, cornerRadius: 1), with: .color(sec.color.opacity(0.6)))
        }
        let c = CGPoint(x: S * 0.72, y: mid), R = S * 0.15
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - R - S * 0.05, y: c.y - R - S * 0.05, width: 2 * (R + S * 0.05), height: 2 * (R + S * 0.05))), with: .color(Color(hex: 0x08080C).opacity(0.75)))
        var a = -Double.pi / 2
        for s in m.sections {
            let a1 = a + s.share * 2 * .pi
            var p = Path()
            p.addArc(center: c, radius: R, startAngle: .radians(a + 0.04), endAngle: .radians(a1 - 0.04), clockwise: false)
            ctx.stroke(p, with: .color(s.color), style: StrokeStyle(lineWidth: S * 0.02 + CGFloat(s.energy) * S * 0.035, lineCap: .round))
            a = a1
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - S * 0.016, y: c.y - S * 0.016, width: S * 0.032, height: S * 0.032)), with: .color(DS.Palette.accent))
    }

    private func drawHalo(_ ctx: GraphicsContext, _ S: CGFloat, _ m: CoverModel) {
        let c = CGPoint(x: S / 2, y: S / 2), R = S * 0.2, n = 90
        for i in 0..<n {
            let f = Double(i) / Double(n)
            let sec = m.section(at: f)
            let ang = -Double.pi / 2 + f * 2 * .pi
            let L = S * 0.04 + CGFloat(m.wave(i, sec.energy)) * S * 0.16
            var p = Path()
            p.move(to: CGPoint(x: c.x + cos(ang) * (R + S * 0.04), y: c.y + sin(ang) * (R + S * 0.04)))
            p.addLine(to: CGPoint(x: c.x + cos(ang) * (R + S * 0.04 + L), y: c.y + sin(ang) * (R + S * 0.04 + L)))
            ctx.stroke(p, with: .color(sec.color.opacity(0.8)), lineWidth: max(1, S * 0.012))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - R - S * 0.01, y: c.y - R - S * 0.01, width: 2 * (R + S * 0.01), height: 2 * (R + S * 0.01))), with: .color(Color(hex: 0x0A0A0E).opacity(0.9)))
        var a = -Double.pi / 2
        for s in m.sections {
            let a1 = a + s.share * 2 * .pi
            var p = Path()
            p.addArc(center: c, radius: R * 0.78, startAngle: .radians(a + 0.06), endAngle: .radians(a1 - 0.06), clockwise: false)
            ctx.stroke(p, with: .color(s.color), style: StrokeStyle(lineWidth: max(1.5, S * 0.03), lineCap: .round))
            a = a1
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - S * 0.025, y: c.y - S * 0.025, width: S * 0.05, height: S * 0.05)), with: .color(DS.Palette.accent))
    }
}

/// The data behind a generated cover: mood colours and the section ribbon.
private struct CoverModel {
    struct Sec { let share: Double; let energy: Double; let color: Color }
    let mood: [Color]
    let sections: [Sec]
    private let seed: Int

    init(song: Song) {
        let ordered = song.orderedSections
        let total = max(1, ordered.reduce(0) { $0 + max(0, $1.endTime - $1.startTime) })
        let energy = SongMapStyle.energies(song)
        let colors = SongMapStyle.groupColors(song)
        let hooks = SongMapStyle.hookIds(song)
        seed = song.title.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        if ordered.isEmpty {
            // Not analysed yet: an even ribbon in the group colours.
            sections = (0..<5).map { Sec(share: 0.2, energy: 0.5, color: DS.Palette.group[$0 % 4]) }
        } else {
            sections = ordered.map { s in
                Sec(share: max(0, s.endTime - s.startTime) / total, energy: energy[s.id] ?? 0.6,
                    color: hooks.contains(s.id) ? DS.Palette.accent : (colors[s.id] ?? DS.Palette.group[0]))
            }
        }
        // Mood colours from the analysis (energy and major / minor); before analysis, from the title.
        let moods = song.understanding.map { Array($0.moods.values) } ?? []
        if !moods.isEmpty {
            let e = moods.map(\.energy).reduce(0, +) / Double(moods.count)
            let v = moods.map(\.valence).reduce(0, +) / Double(moods.count)
            switch (e > 0.55, v >= 0) {
            case (true, false): mood = [Color(hex: 0x3A0D12), Color(hex: 0xB8321F), Color(hex: 0xFFB347)]   // intense
            case (true, true): mood = [Color(hex: 0x0B2A2A), Color(hex: 0x1F9E8A), Color(hex: 0xFFD34D)]    // celebratory
            case (false, false): mood = [Color(hex: 0x1B1035), Color(hex: 0x7A4BB8), Color(hex: 0xFFB38A)]  // emotional
            case (false, true): mood = [Color(hex: 0x2A0B3A), Color(hex: 0xC2307A), Color(hex: 0xFF9F5A)]   // warm, bright
            }
        } else {
            let hue = Double(seed % 360) / 360
            mood = [Color(hue: hue, saturation: 0.7, brightness: 0.25), Color(hue: hue, saturation: 0.7, brightness: 0.7),
                    Color(hue: (hue + 0.1).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.95)]
        }
    }

    func section(at f: Double) -> Sec {
        var acc = 0.0
        for s in sections { acc += s.share; if f < acc { return s } }
        return sections.last ?? Sec(share: 1, energy: 0.5, color: DS.Palette.group[0])
    }

    /// A stable, waveform-like height per bar (0...1), scaled by the section's energy.
    func wave(_ i: Int, _ energy: Double) -> Double {
        let x = Double(i + seed % 17)
        return (0.35 + 0.65 * abs(sin(x * 0.37) * cos(x * 0.09))) * max(0.25, energy)
    }
}
