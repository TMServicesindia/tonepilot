import SwiftUI
import TonePilotCore
import UIKit

// The Mix page's part rows (screen spec §2.5 / mockup v9 #6): instrument drawing + colour dot, name, one
// note line, a visible volume slider and labelled Mute / Solo buttons. Tapping the name (mute) and
// long-pressing it (solo) remain as shortcuts; every action has a visible button.

struct PartRow: View {
    @EnvironmentObject var model: AppModel
    let track: StudioTrack
    let songId: UUID
    let gated: Bool
    @State private var level: Double = 0
    @State private var dragging = false

    var body: some View {
        let on = track.enabled
        let kind = SongStudio.stemKind(track.id)
        let color = DS.Palette.part(kind?.rawValue ?? "")
        let match = kind.flatMap { model.song(songId)?.partMatches?[$0.rawValue] }
        let note: String = !on ? "Muted — you play it" : (track.soloed ? "Solo" : (gated ? "Plays in the sections you chose" : (match.map { "Closest: \($0.name)" } ?? "Playing")))
        HStack(alignment: .center, spacing: DS.Space.m) {
            InstrumentTile(drawing: kind.map(InstrumentDrawing.forPart) ?? .synth, size: 44)
                .opacity(on ? 1 : 0.55)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                // Name + note: tap = mute, long-press = solo (shortcuts; the buttons do the same).
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.s) {
                        Circle().fill(color).frame(width: 8, height: 8)
                        Text(track.name).font(DS.Text.body.weight(.semibold)).foregroundStyle(DS.Palette.textPrimary).lineLimit(2)
                    }
                    Text(note).font(DS.Text.caption).foregroundStyle(on ? DS.Palette.textSecondary : DS.Palette.accent).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { toggleMute(on) }
                .onLongPressGesture(minimumDuration: 0.4) { toggleSolo() }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stem.header.\(track.id)")
                Slider(value: $level, in: 0...1) { editing in
                    dragging = editing
                    if !editing { model.setTrackLevel(track.id, level, songId: songId) }
                }
                .tint(on ? color : DS.Palette.disabled)
                .accessibilityLabel("\(track.name) volume")
                .accessibilityValue("\(Int((level * 100).rounded())) percent")
                .accessibilityIdentifier("stem.volume.\(track.id)")
            }
            VStack(spacing: DS.Space.xs) {
                smallButton(on ? "Mute" : "Muted", active: !on, id: "stem.mute.\(track.id)") { toggleMute(on) }
                smallButton("Solo", active: track.soloed, id: "stem.solo.\(track.id)") { toggleSolo() }
            }
        }
        .padding(.horizontal, DS.Space.m).padding(.vertical, DS.Space.s)
        .accessibilityElement(children: .contain)
        .onAppear { level = track.volume }
        .onChange(of: track.volume) { _, v in if !dragging { level = v } }
        .onChange(of: level) { _, v in if dragging { model.previewTrackLevel(track.id, v, songId: songId) } }
    }

    private func smallButton(_ title: String, active: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(DS.Text.caption.weight(.semibold))
                .frame(minWidth: 60, minHeight: DS.Size.touchTarget - 8)
                .foregroundStyle(active ? DS.Palette.accent : DS.Palette.textSecondary)
                .background(active ? DS.Palette.accentMuted : DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(minHeight: DS.Size.touchTarget - 4)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    private func toggleMute(_ on: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        model.setTrack(track.id, on: !on, songId: songId)
    }

    private func toggleSolo() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        model.toggleSolo(track.id, songId: songId)
    }
}
