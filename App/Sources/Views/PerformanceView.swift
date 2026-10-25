import SwiftUI
import TonePilotCore
import UIKit

/// Stage view: big targets, fast song/section switching, layer mute, master volume, panic.
struct PerformanceView: View {
    @EnvironmentObject var model: AppModel
    @State private var playlistId: UUID?

    private var songs: [Song] {
        if let pid = playlistId, let p = model.library.playlists.first(where: { $0.id == pid }) {
            return p.songIds.compactMap { model.library.song(id: $0) }
        }
        return model.library.songs.sorted { ($0.isFavorite ? 0 : 1, $0.title) < ($1.isFavorite ? 0 : 1, $1.title) }
    }

    private var currentSong: Song? { model.song(model.activeSongId) }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                ConnectionStatus(midi: model.midi)
                Spacer()
                Menu {
                    Button("All songs") { playlistId = nil }
                    ForEach(model.library.playlists) { p in Button(p.name) { playlistId = p.id } }
                } label: {
                    Label(model.library.playlists.first { $0.id == playlistId }?.name ?? "All songs", systemImage: "list.bullet")
                }
                Button(role: .destructive) { model.panic() } label: {
                    Text("PANIC").font(.headline.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.bad, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
                }
                .accessibilityLabel("All notes off")
            }

            VStack(spacing: 4) {
                Text(model.activeArrangement?.name ?? "No tone selected")
                    .font(.system(size: 34, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5)
                Text(currentSong.map { s in
                    let section = s.sections.first { $0.id == model.activeSectionId }?.label
                    return [s.title, section].compactMap { $0 }.joined(separator: " · ")
                } ?? "Pick a song below")
                .font(.title3).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))

            if let song = currentSong, !song.sections.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(song.orderedSections) { section in
                            let active = model.activeSectionId == section.id
                            Button {
                                model.activate(song.arrangement(for: section), songId: song.id, sectionId: section.id)
                            } label: {
                                VStack(spacing: 4) {
                                    Text(section.label).font(.headline).lineLimit(1)
                                    Text(song.arrangement(for: section)?.name ?? "No tone").font(.caption).lineLimit(1)
                                }
                                .frame(width: 140, height: 72)
                                .background(active ? Theme.accent : Theme.panelRaised, in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(active ? .black : .primary)
                            }
                        }
                    }
                }
            }

            if let arrangement = model.activeArrangement {
                HStack(spacing: 10) {
                    ForEach(arrangement.layers) { layer in
                        let name = model.library.patch(id: layer.patchId)?.name ?? "?"
                        Button { toggleMute(layer.id) } label: {
                            Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(layer.muted ? Theme.panel : Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(layer.muted ? Color.clear : Theme.accent, lineWidth: 2))
                                .foregroundStyle(layer.muted ? .secondary : .primary)
                        }
                        .accessibilityLabel("\(name) \(layer.muted ? "muted" : "on")")
                    }
                }
                HStack {
                    Image(systemName: "speaker.wave.2")
                    Slider(value: Binding(get: { arrangement.masterGain }, set: { setMaster($0) }), in: 0...1)
                }
            }
            OutputMeter()

            List(songs) { song in
                Button {
                    let first = song.orderedSections.first
                    model.activate(first.flatMap { song.arrangement(for: $0) } ?? song.arrangements.first,
                                   songId: song.id, sectionId: first?.id)
                } label: {
                    HStack {
                        Text(song.title).font(.title3)
                        Spacer()
                        if model.activeSongId == song.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                    }
                    .padding(.vertical, 6)
                }
                .foregroundStyle(.primary)
            }
            .listStyle(.plain)
        }
        .padding()
        .background(Color.black.ignoresSafeArea())
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// Live changes in performance mode are saved back to the song's arrangement.
    private func edit(_ change: (inout Arrangement) -> Void) {
        guard var a = model.activeArrangement else { return }
        change(&a)
        let owner = model.library.songs.first { $0.arrangements.contains { $0.id == a.id } }?.id
        // updateArrangement re-activates it because it's the active tone.
        model.updateArrangement(a, inSong: owner)
    }

    private func toggleMute(_ id: UUID) {
        edit { a in if let i = a.layers.firstIndex(where: { $0.id == id }) { a.layers[i].muted.toggle() } }
    }

    private func setMaster(_ v: Double) { edit { $0.masterGain = v } }
}
