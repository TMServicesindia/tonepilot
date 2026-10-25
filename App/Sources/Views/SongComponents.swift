import SwiftUI
import TonePilotCore

struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Horizontal section map; width is proportional to section length, colour to repetition group.
struct SectionTimeline: View {
    let song: Song
    @Binding var selected: UUID?
    /// Current song position (backing track or timer), drawn as a line.
    var playhead: Double? = nil

    static let palette: [Color] = [.orange, .teal, .purple, .pink, .yellow, .mint, .indigo, .cyan]

    static func color(for section: SongSection) -> Color {
        guard let g = section.repetitionGroup?.unicodeScalars.first?.value else { return .gray }
        return palette[Int(g) % palette.count]
    }

    var body: some View {
        let duration = max(song.duration ?? song.sections.map(\.endTime).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06))
                    ForEach(song.orderedSections) { s in
                        let x = geo.size.width * s.startTime / duration
                        let w = max(2, geo.size.width * s.duration / duration - 1)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Self.color(for: s).opacity(selected == s.id ? 1 : 0.55))
                            .frame(width: w, height: geo.size.height)
                            .overlay(Text(s.repetitionGroup ?? "").font(.caption2.bold()).foregroundStyle(.black))
                            .offset(x: x)
                            .onTapGesture { selected = s.id }
                    }
                    if let playhead {
                        Rectangle().fill(Color.white).frame(width: 2, height: geo.size.height + 6)
                            .offset(x: geo.size.width * min(1, max(0, playhead / duration)) - 1)
                            .accessibilityLabel("Playing at \(playhead.mmss)")
                    }
                }
            }
            .frame(height: 34)
            HStack {
                Text("0:00"); Spacer(); Text(duration.mmss)
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
