import SwiftUI
import TonePilotCore
import UIKit

/// Stage view: big targets, song-aware tone switching, live chord/melody guide,
/// independent accompaniment toggles, layer mutes, master volume and panic.
struct PerformanceView: View {
    @EnvironmentObject var model: AppModel
    @State private var playlistId: UUID?
    @State private var showSongs = false
    @State private var showBacking = false
    @State private var showTones = false

    private var songs: [Song] {
        if let pid = playlistId, let p = model.library.playlists.first(where: { $0.id == pid }) {
            return p.songIds.compactMap { model.library.song(id: $0) }
        }
        return model.library.songs.sorted { ($0.isFavorite ? 0 : 1, $0.title) < ($1.isFavorite ? 0 : 1, $1.title) }
    }

    private var currentSong: Song? { model.song(model.activeSongId) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                topBar
                if AudioSessionSetup.isBuiltInSpeaker {
                    Label("Sound is going to the iPhone speaker, not the Casio. Connect the audio cable to AUDIO IN.", systemImage: "speaker.wave.2")
                        .font(.caption).foregroundStyle(Theme.warn).frame(maxWidth: .infinity, alignment: .leading)
                }
                toneHeader
                Button { showTones = true } label: {
                    Label("Choose tone", systemImage: "pianokeys").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                if let song = currentSong {
                    if let id = model.pendingSuggestion, let next = song.sections.first(where: { $0.id == id }) {
                        Button { model.confirmSuggestion() } label: {
                            HStack {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Next: \(next.label) — \(song.arrangement(for: next)?.name ?? "tone")").lineLimit(1)
                                Spacer()
                                Text("TAP TO SWITCH").font(.caption.bold())
                            }
                            .padding().frame(maxWidth: .infinity)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black)
                        }
                    }
                    sectionButtons(song)
                    transport(song)
                    LiveGuideStrip(song: song, time: model.songPosition, melodyOffset: AutoArranger.guideOffset(for: model.activeArrangement))
                    accompaniment(song)
                }
                layerControls
                OutputMeter()
                Button { showSongs = true } label: { Label(currentSong == nil ? "Play along with a song (optional)" : "Change song", systemImage: "music.note.list").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showSongs) { songPicker }
        .sheet(isPresented: $showTones) { NavigationStack { ToneSelectorView(inSheet: true) }.environmentObject(model) }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            if let id = model.activeSongId { model.ensurePerformance(songId: id) }
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var topBar: some View {
        HStack {
            ConnectionStatus(midi: model.midi)
            Spacer()
            Button(role: .destructive) { model.panic() } label: {
                Text("PANIC").font(.headline.bold()).padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.bad, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.white)
            }
            .accessibilityLabel("All notes off")
        }
    }

    private var toneHeader: some View {
        VStack(spacing: 4) {
            Text(model.activeArrangement?.name.replacingOccurrences(of: " (My Version)", with: "") ?? "No tone selected")
                .font(.system(size: 32, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.5)
            Text(currentSong.map { s in
                let section = s.sections.first { $0.id == model.activeSectionId }?.label
                return [s.title, section, model.songPosition?.mmss].compactMap { $0 }.joined(separator: " · ")
            } ?? "Any music — pick a tone and play")
            .font(.title3).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sectionButtons(_ song: Song) -> some View {
        let switching = song.switching ?? SwitchingSettings()
        return VStack(alignment: .leading, spacing: 8) {
            Picker("Switching", selection: Binding(get: { switching.mode }, set: { var s = switching; s.mode = $0; model.updateSwitching(s) })) {
                ForEach(SwitchingSettings.Mode.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            if switching.effectiveMode != switching.mode {
                Text("Automatic switching needs a song clock — choose Backing track or Timer below.").font(.caption2).foregroundStyle(Theme.warn)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(song.orderedSections) { section in
                        let active = model.activeSectionId == section.id
                        let suggested = model.pendingSuggestion == section.id
                        Button { model.activateSection(section.id) } label: {
                            VStack(spacing: 4) {
                                Text(section.label).font(.headline).lineLimit(1)
                                Text(section.startTime.mmss).font(.caption2.monospacedDigit())
                            }
                            .frame(width: 130, height: 64)
                            .background(active ? Theme.accent : Theme.panelRaised, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(suggested ? Theme.accent : .clear, lineWidth: 3))
                            .foregroundStyle(active ? .black : .primary)
                        }
                    }
                }
            }
        }
    }

    private func transport(_ song: Song) -> some View {
        let switching = song.switching ?? SwitchingSettings()
        return VStack(alignment: .leading, spacing: 8) {
            Picker("Song clock", selection: Binding(get: { switching.reference }, set: { var s = switching; s.reference = $0; model.updateSwitching(s) })) {
                Text("Backing track").tag(SwitchingSettings.TimingReference.backingTrack)
                Text("Timer").tag(SwitchingSettings.TimingReference.timer)
                Text("None").tag(SwitchingSettings.TimingReference.none)
            }
            .pickerStyle(.segmented)
            HStack {
                switch switching.reference {
                case .backingTrack:
                    if model.audioURL(for: song) == nil {
                        Text("This song has no audio to use as a clock.").font(.caption).foregroundStyle(.secondary)
                    } else if model.isSectionPlaying {
                        Button { model.stopBackingTrack() } label: { Label("Stop", systemImage: "stop.fill") }.buttonStyle(.borderedProminent)
                    } else {
                        let start = song.sections.first { $0.id == model.activeSectionId }?.startTime ?? 0
                        Button { model.playBackingTrack(from: start) } label: { Label("Play from \(start.mmss)", systemImage: "play.fill") }.buttonStyle(.borderedProminent)
                        Button { model.playBackingTrack(from: 0) } label: { Label("From start", systemImage: "backward.end.fill") }.buttonStyle(.bordered)
                    }
                case .timer:
                    if model.songPosition == nil {
                        Button { model.startTimerClock() } label: { Label("Start clock on beat 1", systemImage: "metronome") }.buttonStyle(.borderedProminent)
                    } else {
                        Button { model.stopTimerClock() } label: { Label("Stop clock", systemImage: "stop.fill") }.buttonStyle(.borderedProminent)
                    }
                case .none:
                    Text("Tap a section to change tone.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(switching.reference == .timer
                 ? "Timer: tap Start exactly when you begin the song at its original tempo. Key presses alone can't tell TonePilot where you are."
                 : switching.reference == .backingTrack ? "The backing track's position drives switching and accompaniment. Turn its volume off below to use it as a silent clock." : "")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func accompaniment(_ song: Song) -> some View {
        let acc = song.accompaniment ?? AccompanimentSettings()
        func binding(_ path: WritableKeyPath<AccompanimentSettings, Bool>) -> Binding<Bool> {
            Binding(get: { acc[keyPath: path] }, set: { var a = acc; a[keyPath: path] = $0; model.updateAccompaniment(a) })
        }
        func level(_ path: WritableKeyPath<AccompanimentSettings, Double>) -> Binding<Double> {
            Binding(get: { acc[keyPath: path] }, set: { var a = acc; a[keyPath: path] = $0; model.updateAccompaniment(a) })
        }
        let supported = model.output.supportsAccompaniment
        return DisclosureGroup(isExpanded: $showBacking) {
            VStack(alignment: .leading, spacing: 8) {
                if !supported { Text("Accompaniment needs the TonePilot engine (Settings).").font(.caption).foregroundStyle(Theme.warn) }
                toggleRow("Backing track (original song)", binding(\.backingTrack), level(\.backingTrackLevel))
                toggleRow("Generated bass (root → fifth)", binding(\.bass), level(\.bassLevel)).disabled(!supported)
                toggleRow("Drums", binding(\.drums), level(\.drumLevel)).disabled(!supported)
                if acc.drums {
                    Picker("Style", selection: Binding(get: { acc.drumStyle }, set: { var a = acc; a.drumStyle = $0; model.updateAccompaniment(a) })) {
                        ForEach(AccompanimentSettings.DrumStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                toggleRow("Metronome", binding(\.metronome), level(\.metronomeLevel)).disabled(!supported)
                toggleRow("Melody guide (Reference Learning)", binding(\.melodyGuide), level(\.guideLevel)).disabled(!supported)
                Text("Everything here is optional and independent of your tones — switch it all off to play only the custom instrument sounds.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        } label: {
            Label("Backing & accompaniment\(acc.anyGenerated || acc.backingTrack ? " · on" : "")", systemImage: "music.mic")
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func toggleRow(_ title: String, _ on: Binding<Bool>, _ level: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(title, isOn: on)
            if on.wrappedValue { Slider(value: level, in: 0...1) }
        }
    }

    @ViewBuilder private var layerControls: some View {
        if let arrangement = model.activeArrangement {
            VStack(spacing: 10) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 10) {
                    ForEach(arrangement.layers) { layer in
                        let name = model.library.patch(id: layer.patchId)?.name ?? "?"
                        Button { toggleMute(layer.id) } label: {
                            VStack(spacing: 2) {
                                Text(name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(layer.keyRange.high < 60 ? "Left hand" : layer.keyRange.low >= 55 ? "Right hand" : "Both hands").font(.caption2)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(layer.muted ? Theme.panel : Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(layer.muted ? Color.clear : Theme.accent, lineWidth: 2))
                            .foregroundStyle(layer.muted ? .secondary : .primary)
                        }
                        .disabled(arrangement.origin == .aiOriginal)
                        .accessibilityLabel("\(name) \(layer.muted ? "muted" : "on")")
                    }
                }
                HStack {
                    Image(systemName: "speaker.wave.2")
                    Slider(value: Binding(get: { arrangement.masterGain }, set: { setMaster($0) }), in: 0...1)
                }
            }
        }
    }

    private var songPicker: some View {
        NavigationStack {
            List {
                if !model.library.playlists.isEmpty {
                    Picker("Playlist", selection: $playlistId) {
                        Text("All songs").tag(UUID?.none)
                        ForEach(model.library.playlists) { p in Text(p.name).tag(UUID?.some(p.id)) }
                    }
                }
                ForEach(songs) { song in
                    Button {
                        model.startPerformance(songId: song.id)
                        showSongs = false
                    } label: {
                        HStack {
                            Text(song.title).font(.title3)
                            Spacer()
                            if song.analysisStatus == .completed { Image(systemName: "wand.and.stars").foregroundStyle(.secondary) }
                            if model.activeSongId == song.id { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                        }
                        .padding(.vertical, 6)
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Songs")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showSongs = false } } }
        }
    }

    /// Live changes in performance mode are saved back to the tone (My Version).
    private func edit(_ change: (inout Arrangement) -> Void) {
        guard var a = model.activeArrangement, a.origin != .aiOriginal else { return }
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
