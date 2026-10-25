import SwiftUI
import TonePilotCore
import UIKit

/// Studio tab: the open song's Song Studio, or free play with any tone when no song is open.
struct StudioTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        // A new identity per song: pages pushed for the previous song are closed too.
        NavigationStack {
            if let id = model.activeSongId, model.song(id) != nil {
                SongStudioView(songId: id)
            } else {
                FreePlayView()
            }
        }
        .id(model.activeSongId)
    }
}

struct SectionRef: Identifiable, Hashable { let id: UUID }

/// One screen to play a song: timeline, your keyboard, the AI background band, the parts the AI
/// plays for you, and each section's tone. "You choose what to play. TonePilot fills in the rest."
struct SongStudioView: View {
    @EnvironmentObject var model: AppModel
    let songId: UUID
    @State private var pickingToneFor: SectionRef?
    @State private var editingTone: ToneEditTarget?
    @State private var guideFor: UUID?
    @State private var editingSection: SongSection?
    @State private var showDetails = false
    @State private var showMelodyGuide = false
    @State private var showSoundLibrary = false
    @State private var showListen = false
    @AppStorage("studioIntroDismissed") private var introDismissed = false

    var body: some View {
        if let song = model.song(songId) {
            ScrollView {
                VStack(spacing: 16) {
                    StudioHeader(song: song)
                    StudioAnalysisStatus(song: song, onListen: { showListen = true })
                    if !introDismissed { intro }
                    StudioTimeline(song: song)
                    if !(song.chordGuide ?? []).isEmpty { LiveGuideHost(song: song, live: model.live) }
                    SeparationCard(song: song)
                    MyKeyboardCard(song: song, onChangeSound: changeSound, onEditSound: editSound, onEditTone: { editingTone = ToneEditTarget(id: $0) })
                    SongPartsCard(song: song)
                    AIPartsCard(song: song)
                    StudioSectionsCard(song: song, onChangeSound: changeSound, onEditSound: editSound,
                                       onGuide: { guideFor = $0 }, onEditTiming: { editingSection = $0 })
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Song Studio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar(song) }
            .sheet(item: $pickingToneFor) { ref in
                TonePickerSheet(songId: songId, sectionId: ref.id).environmentObject(model)
            }
            .sheet(item: $editingTone) { target in
                NavigationStack { ArrangementEditorView(songId: songId, arrangementId: target.id) }
                    .environmentObject(model)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $editingSection) { section in
                SectionEditorSheet(songId: songId, section: section).environmentObject(model)
            }
            .sheet(isPresented: $showListen) { ListenModeView(songId: songId).environmentObject(model) }
            .navigationDestination(item: $guideFor) { SectionGuideView(songId: songId, sectionId: $0) }
            .navigationDestination(isPresented: $showDetails) { SongDetailView(songId: songId) }
            .navigationDestination(isPresented: $showMelodyGuide) { MelodyChordGuideView(songId: songId) }
            .navigationDestination(isPresented: $showSoundLibrary) { ToneStudioHomeView() }
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                model.ensurePerformance(songId: songId)
                model.loadWaveform(songId)
            }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        } else {
            ContentUnavailableView("Song not found", systemImage: "questionmark")
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("How Song Studio works", systemImage: "sparkles").font(.headline)
                Spacer()
                Button { introDismissed = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .accessibilityLabel("Dismiss")
            }
            Text("**You play** the parts you know on your Casio. **The song plays the rest**: TonePilot separates the recording into vocals, drums, bass and music — switch off what you want to play yourself, and let the original fill in the passages you can't play yet.")
                .font(.footnote)
        }
        .padding(14)
        .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
    }

    @ToolbarContentBuilder
    private func toolbar(_ song: Song) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { model.selectedTab = .library } label: { Label("Library", systemImage: "chevron.left").labelStyle(.titleAndIcon) }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showDetails = true } label: { Label("Analysis details & corrections", systemImage: "waveform.badge.magnifyingglass") }
                Button { showMelodyGuide = true } label: { Label("Melody & chord guide", systemImage: "music.quarternote.3") }
                Button { showSoundLibrary = true } label: { Label("Sound library (advanced)", systemImage: "slider.vertical.3") }
                if song.sourceType == .listened {
                    Button { showListen = true } label: { Label("Listen again", systemImage: "ear") }
                } else if model.audioURL(for: song) != nil {
                    Button { model.analyze(songId: songId, useServer: model.serverSettings.enabled) } label: { Label("Re-analyse", systemImage: "arrow.clockwise") }
                }
                Divider()
                Button { model.panic() } label: { Label("All notes off", systemImage: "speaker.slash") }
                Button { model.closeStudioSong() } label: { Label("Close song", systemImage: "xmark") }
            } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("More") }
        }
    }

    private func changeSound(_ sectionId: UUID) {
        model.activateSection(sectionId)
        pickingToneFor = SectionRef(id: sectionId)
    }

    private func editSound(_ sectionId: UUID) {
        guard let tone = model.editableTone(songId: songId, sectionId: sectionId) else { return }
        model.activateSection(sectionId)
        editingTone = ToneEditTarget(id: tone.id)
    }
}

// MARK: Header

struct StudioHeader: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View { StudioHeaderContent(song: song, live: model.live) }
}

/// Redraws with the song position (LiveState), separately from the rest of the screen.
private struct StudioHeaderContent: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    @ObservedObject var live: LiveState

    var body: some View {
        let playing = model.isStudioPlaying
        let pos = live.position ?? model.cursor
        let section = song.orderedSections.last { $0.startTime <= pos + 0.01 }
        let hasAudio = model.audioURL(for: song) != nil
        HStack(spacing: 14) {
            Button { model.studioTogglePlay() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 28, weight: .bold))
                    .frame(width: 66, height: 66)
                    .background(Theme.accent, in: Circle())
                    .foregroundStyle(.black)
            }
            .accessibilityLabel(playing ? "Pause" : (hasAudio ? "Play" : "Start song clock"))
            .disabled(song.sections.isEmpty && !hasAudio)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.title).font(.headline).lineLimit(2)
                let meta = [song.artist, song.film, song.composer].compactMap { $0 }.joined(separator: " · ")
                if !meta.isEmpty { Text(meta).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                Text("\(playing ? "Playing" : "Paused") · \(section?.label ?? "Start") · \(pos.mmss)\(song.duration.map { " / \($0.mmss)" } ?? "")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(playing ? Theme.accent : .secondary)
                if !hasAudio {
                    Text("No recording on this iPhone: Play starts the song clock — begin on beat 1.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Analysis progress, failures and notices (only shown when there's something to say).
struct StudioAnalysisStatus: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let onListen: () -> Void

    var body: some View {
        switch song.analysisStatus {
        case .running:
            Card(title: "Building your arrangement") {
                ProgressView(value: model.analysisProgress[song.id] ?? 0) {
                    Text(model.analysisStage[song.id] ?? "Analysing on this iPhone…").font(.subheadline)
                }
                Text("Tempo, key and chords → melody → sections → a tone for every section. You can already play the recording.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Cancel analysis") { model.cancelAnalysis(songId: song.id) }.font(.caption)
            }
        case .failed, .notStarted:
            Card(title: "Analysis") {
                if let e = song.analysisError { Text(e).font(.footnote).foregroundStyle(Theme.bad) }
                if song.sourceType == .listened {
                    Button("Listen again to analyse", action: onListen).buttonStyle(.borderedProminent)
                } else if model.audioURL(for: song) != nil {
                    Button(song.analysisStatus == .failed ? "Try again" : "Analyse & arrange") {
                        model.analyze(songId: song.id, useServer: model.serverSettings.enabled)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        default:
            if let notice = model.analysisNotice[song.id] {
                Label(notice, systemImage: "info.circle").font(.caption).foregroundStyle(Theme.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: Timeline

struct StudioTimeline: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View { StudioTimelineContent(song: song, live: model.live) }
}

private struct StudioTimelineContent: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    @ObservedObject var live: LiveState

    var body: some View {
        let duration = max(song.duration ?? song.sections.map(\.endTime).max() ?? 1, 1)
        let pos = live.position ?? model.cursor
        let current = song.orderedSections.last { $0.startTime <= pos + 0.01 }
        VStack(alignment: .leading, spacing: 10) {
            WaveformTimeline(song: song, duration: duration, position: pos, peaks: model.waveforms[song.id] ?? [],
                             loopSection: model.loopSectionId) { model.studioSeek(to: $0) }
                .frame(height: 76)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(song.orderedSections) { s in
                            let isCurrent = current?.id == s.id
                            Button { model.studioJump(to: s.id) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(s.startTime.mmss).font(.caption2.monospacedDigit())
                                }
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(isCurrent ? Theme.accent : Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .top) {
                                    RoundedRectangle(cornerRadius: 2).fill(SectionTimeline.color(for: s)).frame(height: 3).padding(.horizontal, 8)
                                }
                                .foregroundStyle(isCurrent ? .black : .primary)
                            }
                            .id(s.id)
                            .accessibilityLabel("\(s.label), starts at \(s.startTime.mmss)")
                            .accessibilityHint("Jumps to this section")
                        }
                    }
                }
                .onChange(of: current?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            HStack(spacing: 10) {
                Button { model.studioToggleLoop() } label: {
                    Label(model.loopSectionId == nil ? "Loop section" : "Looping", systemImage: "repeat")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(model.loopSectionId == nil ? .gray : Theme.accent)
                .disabled(song.sections.isEmpty || model.audioURL(for: song) == nil)
                Menu {
                    ForEach([Float(0.5), 0.75, 0.9, 1], id: \.self) { r in
                        Button { model.setStudioRate(r) } label: {
                            if model.studioRate == r { Label("\(Int(r * 100))%", systemImage: "checkmark") } else { Text("\(Int(r * 100))%") }
                        }
                    }
                } label: {
                    Label("Speed \(Int(model.studioRate * 100))%", systemImage: "tortoise").font(.subheadline)
                }
                .buttonStyle(.bordered)
                .disabled(model.audioURL(for: song) == nil)
                Spacer()
            }
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Waveform with coloured section bands and the playhead. Tap or drag to move through the song.
struct WaveformTimeline: View {
    let song: Song
    let duration: Double
    let position: Double
    let peaks: [Float]
    let loopSection: UUID?
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                for s in song.orderedSections {
                    let x0 = size.width * s.startTime / duration
                    let w = size.width * (s.endTime - s.startTime) / duration
                    let rect = CGRect(x: x0, y: 0, width: max(1, w - 1), height: size.height)
                    let alpha = loopSection == s.id ? 0.5 : 0.22
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(SectionTimeline.color(for: s).opacity(alpha)))
                }
                if peaks.isEmpty {
                    ctx.fill(Path(CGRect(x: 0, y: size.height / 2 - 0.5, width: size.width, height: 1)), with: .color(.white.opacity(0.3)))
                } else {
                    let bw = size.width / CGFloat(peaks.count)
                    for (i, p) in peaks.enumerated() {
                        let h = max(1, CGFloat(p) * size.height * 0.9)
                        let rect = CGRect(x: CGFloat(i) * bw, y: (size.height - h) / 2, width: max(0.5, bw * 0.7), height: h)
                        ctx.fill(Path(rect), with: .color(.white.opacity(0.55)))
                    }
                }
                let x = size.width * min(1, max(0, position / duration))
                ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(Theme.accent))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                onSeek(Double(max(0, min(1, v.location.x / max(1, geo.size.width)))) * duration)
            })
        }
        .accessibilityElement()
        .accessibilityLabel("Song timeline")
        .accessibilityValue("\(position.mmss) of \(duration.mmss)")
        .accessibilityAdjustableAction { direction in
            onSeek(direction == .increment ? position + 10 : max(0, position - 10))
        }
    }
}

/// The left-hand chord guide while the song plays.
struct LiveGuideHost: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    @ObservedObject var live: LiveState

    var body: some View {
        if let t = live.position {
            LiveGuideStrip(song: song, time: t, melodyOffset: AutoArranger.guideOffset(for: model.activeArrangement))
        }
    }
}

// MARK: Separation

/// Moises-style separation status: separate the song into vocals, drums, bass and music.
struct SeparationCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View {
        let separated = !model.stemKinds(for: song).isEmpty
        if let p = model.separationProgress[song.id] {
            Card(title: "Separating the song") {
                ProgressView(value: p) {
                    Text("Vocals, drums, bass and music — on this iPhone").font(.subheadline)
                }
                HStack {
                    Text("\(Int(p * 100))%").monospacedDigit()
                    if let left = model.separationTimeLeft(song.id) {
                        Text("· about \(max(1, Int((left / 60).rounded(.up)))) min left")
                    }
                    Spacer()
                    Button("Cancel") { model.cancelSeparation(song.id) }
                }
                .font(.caption)
                Text("Keep TonePilot open (the screen stays on). You can already play with the full recording.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        } else if !separated, model.audioURL(for: song) != nil {
            Card(title: "Separate the parts") {
                Text("Split this song into **Vocals**, **Drums**, **Bass** and **Music** so you can switch off the singer and play along with the real band — like Moises, but on your iPhone.")
                    .font(.footnote)
                if let e = model.separationError[song.id] { Text(e).font(.caption).foregroundStyle(Theme.bad) }
                if model.canSeparate {
                    Button {
                        model.separateStems(song.id)
                    } label: {
                        Label(model.separationError[song.id] == nil ? "Separate parts" : "Try again", systemImage: "scissors")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(song.analysisStatus == .running)
                    Text(song.analysisStatus == .running ? "Starts automatically after the analysis." : "Takes a few minutes (about 1½× the song's length; about 6 min for a 4-minute song).")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("The separation model isn't included in this build.").font(.caption).foregroundStyle(Theme.warn)
                }
            }
        }
    }
}

// MARK: My keyboard

struct MyKeyboardCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let onChangeSound: (UUID) -> Void
    let onEditSound: (UUID) -> Void
    let onEditTone: (UUID) -> Void

    var body: some View {
        let switching = song.switching ?? SwitchingSettings()
        let sectionId = model.activeSectionId ?? song.orderedSections.first?.id
        let usingMain = model.isUsingMainTone(song)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("My keyboard", systemImage: "pianokeys").font(.headline)
                Spacer()
                ConnectionStatus(midi: model.midi)
            }
            if model.midi.sources.isEmpty {
                Text("Connect the Casio's USB TO HOST port to the iPhone. Settings › Connect your Casio shows how.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if AudioSessionSetup.isBuiltInSpeaker {
                Label("Sound is coming from the iPhone speaker. Connect the audio cable to the Casio's AUDIO IN to hear it there.", systemImage: "speaker.wave.2")
                    .font(.caption).foregroundStyle(Theme.warn)
            }
            if !song.sections.isEmpty {
                Picker("Tone", selection: Binding(get: { usingMain }, set: { main in
                    if main { model.useMainTone(song.id) } else { model.useSectionTones(song.id) }
                })) {
                    Text("Main tone").tag(true)
                    Text("Tone per section").tag(false)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Keyboard tone")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(model.activeArrangement?.name.replacingOccurrences(of: " (My Version)", with: "") ?? "No tone selected")
                    .font(.title3.weight(.bold)).lineLimit(2)
                if let a = model.activeArrangement {
                    Text(a.layers.filter { !$0.muted }.compactMap { model.library.patch(id: $0.patchId)?.name }.joined(separator: " + "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(usingMain ? "One tone for the whole song." : "The tone changes with each section.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                if usingMain, let main = model.mainTone(of: song) {
                    Button { onEditTone(main.id) } label: { Label("Edit main tone", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.borderedProminent)
                } else if let sectionId {
                    Button { onChangeSound(sectionId) } label: { Label("Change sound", systemImage: "music.note.list") }
                        .buttonStyle(.borderedProminent)
                    Button { onEditSound(sectionId) } label: { Label("Edit sound", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.bordered)
                }
            }
            if let track = model.studioTracks(for: song).first(where: { $0.id == SongStudio.keyboard }) {
                TrackRow(track: track, songId: song.id, showHeader: false)
            }
            if !usingMain, !song.sections.isEmpty {
                Toggle(isOn: Binding(get: { switching.mode == .automatic },
                                     set: { auto in
                                         var s = switching
                                         s.mode = auto ? .automatic : .assisted
                                         if model.audioURL(for: song) == nil, s.reference == .backingTrack { s.reference = .timer }
                                         model.updateSwitching(s)
                                     })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Switch automatically")
                        Text(switching.mode == .automatic ? "Follows the song position." : "TonePilot shows the next section's tone; tap it to switch.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let id = model.pendingSuggestion, let next = song.sections.first(where: { $0.id == id }) {
                    Button { model.confirmSuggestion() } label: {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Switch to \(next.label)").lineLimit(1)
                            Spacer()
                        }
                        .padding(12).frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(.black)
                    }
                }
            }
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: Song parts (from the recording)

struct SongPartsCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View {
        let tracks = model.studioTracks(for: song).filter { $0.group == .songParts }
        let acc = song.accompaniment ?? AccompanimentSettings()
        let separated = tracks.contains { $0.id != SongStudio.original }
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Label("Song parts", systemImage: "waveform").font(.headline)
                Text(separated
                     ? "The song's own parts, always in time with the music. Switch off what you want to play yourself."
                     : "The full recording. Separate the parts (above) to switch the vocals, drums, bass and music on and off.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(tracks) { track in
                    TrackRow(track: track, songId: song.id)
                    if SongStudio.isGated(track.id, acc) {
                        Label("Plays only in the sections chosen under “AI plays difficult parts”.", systemImage: "wand.and.stars")
                            .font(.caption2).foregroundStyle(Theme.accent).padding(.leading, 38)
                    }
                    if track.id != tracks.last?.id { Divider().overlay(Color.white.opacity(0.06)) }
                }
            }
            .padding(14)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// A mixer row: name, what it's made of, on/off, solo and volume.
struct TrackRow: View {
    @EnvironmentObject var model: AppModel
    let track: StudioTrack
    let songId: UUID
    var showHeader = true
    @State private var level: Double = 0
    @State private var dragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showHeader {
                HStack(spacing: 10) {
                    Image(systemName: track.symbol)
                        .font(.body)
                        .frame(width: 28)
                        .foregroundStyle(track.enabled ? Theme.accent : .secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(track.name).font(.subheadline.weight(.semibold))
                            TrackKindBadge(kind: track.kind)
                        }
                        Text(track.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if track.canSolo {
                        Button { model.toggleSolo(track.id, songId: songId) } label: {
                            Text("S").font(.caption.bold())
                                .frame(width: 32, height: 32)
                                .background(track.soloed ? Theme.accent : Theme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(track.soloed ? .black : .secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(track.soloed ? "Stop soloing \(track.name)" : "Solo \(track.name)")
                    }
                    Toggle(track.name, isOn: Binding(get: { track.enabled }, set: { model.setTrack(track.id, on: $0, songId: songId) }))
                        .labelsHidden()
                }
            }
            if track.enabled {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                    Slider(value: $level, in: 0...1) { editing in
                        dragging = editing
                        if !editing { model.setTrackLevel(track.id, level, songId: songId) }
                    }
                    .accessibilityLabel("\(track.name) volume")
                    Image(systemName: "speaker.wave.3.fill").font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.leading, showHeader ? 38 : 0)
            }
        }
        .onAppear { level = track.volume }
        .onChange(of: track.volume) { _, v in if !dragging { level = v } }
        .onChange(of: level) { _, v in if dragging { model.previewTrackLevel(track.id, v, songId: songId) } }
    }
}

struct TrackKindBadge: View {
    let kind: StudioTrack.Kind
    var body: some View {
        let (text, color): (String, Color) = {
            switch kind {
            case .audio: return ("Audio", .teal)
            case .generated: return ("AI notes", Theme.accent)
            case .live: return ("Live", Theme.good)
            }
        }()
        Text(text).font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.22), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel(kind == .audio ? "Audio from the recording" : kind == .generated ? "Notes generated by the AI" : "Live from your keyboard")
    }
}

// MARK: Original fills in difficult parts

/// "AI plays difficult parts", from the recording itself: the original vocals or music play only
/// in the sections you choose; everywhere else it's you.
struct AIPartsCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View {
        let tracks = model.studioTracks(for: song)
        let acc = song.accompaniment ?? AccompanimentSettings()
        let sources = tracks.filter { [SongStudio.stem(.other), SongStudio.stem(.vocals)].contains($0.id) }
        let current = acc.aiPartTrack.flatMap { id in sources.first { $0.id == id } } ?? sources.first
        let on = acc.aiPartTrack != nil && acc.aiPartsEnabled == true && current != nil
        VStack(alignment: .leading, spacing: 12) {
            Label("Original plays the difficult parts", systemImage: "wand.and.stars").font(.headline)
            if sources.isEmpty {
                Text("Available after the song is separated into parts.").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Can't play a passage yet? The recording's own part plays in the sections you pick. Everywhere else, it's you.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Fill in difficult parts", isOn: Binding(get: { on }, set: { v in
                    if v, acc.aiPartTrack == nil, let first = current { model.setAIPartSource(first.id, songId: song.id) }
                    model.setAIParts(v, songId: song.id)
                }))
                if on, let current {
                    Picker("Played by", selection: Binding(get: { current.id }, set: { model.setAIPartSource($0, songId: song.id) })) {
                        ForEach(sources) { t in Text(t.id == SongStudio.stem(.vocals) ? "The original vocals" : "The original music").tag(t.id) }
                    }
                    .pickerStyle(.segmented)
                    Text("Plays in").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    FlowSections(song: song, selected: acc.guideSections) { model.toggleAIPart($0, songId: song.id) }
                    HStack {
                        Button("Suggested") { model.setAIPartSections(SongStudio.suggestedAIParts(song, source: acc.aiPartTrack), songId: song.id) }
                        Button("Whole song") { model.setAIPartSections(nil, songId: song.id) }
                        Spacer()
                    }
                    .font(.footnote).buttonStyle(.bordered)
                    TrackRow(track: { var t = current; t.enabled = true; return t }(), songId: song.id, showHeader: false)
                }
            }
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Section chips that wrap onto several lines.
struct FlowSections: View {
    let song: Song
    /// nil = every section.
    let selected: [UUID]?
    let onToggle: (UUID) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(song.orderedSections) { s in
                let on = selected?.contains(s.id) ?? true
                Button { onToggle(s.id) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.caption)
                        Text(s.label).font(.caption).lineLimit(1)
                    }
                    .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .background(on ? Theme.accent.opacity(0.25) : Theme.panelRaised, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.label): AI \(on ? "plays" : "doesn't play") the melody")
            }
        }
    }
}

// MARK: Sections

struct StudioSectionsCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let onChangeSound: (UUID) -> Void
    let onEditSound: (UUID) -> Void
    let onGuide: (UUID) -> Void
    let onEditTiming: (SongSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Sections & tones", systemImage: "list.bullet.rectangle").font(.headline)
            if song.sections.isEmpty {
                Text(song.analysisStatus == .running ? "Sections appear when the analysis finishes." : "No sections yet.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Each section has its own tone. Tap a section to jump there.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(song.orderedSections) { section in
                StudioSectionRow(song: song, section: section, onChangeSound: onChangeSound, onEditSound: onEditSound,
                                 onGuide: onGuide, onEditTiming: onEditTiming)
            }
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StudioSectionRow: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let section: SongSection
    let onChangeSound: (UUID) -> Void
    let onEditSound: (UUID) -> Void
    let onGuide: (UUID) -> Void
    let onEditTiming: (SongSection) -> Void

    var body: some View {
        let tone = song.arrangement(for: section)
        let isCurrent = model.activeSectionId == section.id
        let acc = song.accompaniment ?? AccompanimentSettings()
        let aiPlays = SongStudio.aiPartsOn(acc) && (acc.guideSections?.contains(section.id) ?? true)
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(SectionTimeline.color(for: section)).frame(width: 6)
            Button { model.studioJump(to: section.id) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(section.label).font(.subheadline.weight(.semibold))
                        if section.isClimax == true { Text("CLIMAX").font(.caption2.bold()).foregroundStyle(Theme.accent) }
                        if aiPlays { Image(systemName: "wand.and.stars").font(.caption2).foregroundStyle(Theme.accent).accessibilityLabel("AI plays the melody here") }
                    }
                    Text("\(section.startTime.mmss) – \(section.endTime.mmss) · \(tone?.name.replacingOccurrences(of: " (My Version)", with: "") ?? "No tone")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Jumps to this section")
            Menu {
                Button { model.studioJump(to: section.id) } label: { Label("Play from here", systemImage: "play") }
                Button { onChangeSound(section.id) } label: { Label("Change sound…", systemImage: "music.note.list") }
                Button { onEditSound(section.id) } label: { Label("Edit sound…", systemImage: "slider.horizontal.3") }
                if song.sections.filter({ $0.arrangementId == tone?.id }).count > 1 {
                    Button {
                        _ = model.detachTone(songId: song.id, sectionId: section.id)
                        onEditSound(section.id)
                    } label: { Label("Edit just this section", systemImage: "square.on.square.dashed") }
                }
                if song.aiOriginal(for: section) != nil, tone?.origin == .myVersion {
                    Button { model.restoreAIOriginal(songId: song.id, sectionId: section.id) } label: { Label("Restore AI Original", systemImage: "arrow.uturn.backward") }
                }
                Divider()
                Button { onGuide(section.id) } label: { Label("Section guide & practice", systemImage: "music.note.list") }
                Button { onEditTiming(section) } label: { Label("Fix timing & name", systemImage: "timeline.selection") }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("\(section.label) options")
        }
        .padding(.vertical, 6).padding(.trailing, 2)
        .background(isCurrent ? Theme.panelRaised : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: Tone picker (preview, then apply)

struct TonePickerSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let songId: UUID
    let sectionId: UUID
    @State private var search = ""

    var body: some View {
        let list = model.library.toneList(search: search)
        let sectionLabel = model.song(songId)?.sections.first { $0.id == sectionId }?.label ?? "this section"
        let previewing = model.previewingToneId.flatMap { model.tone(id: $0) }
        NavigationStack {
            List {
                Section {
                    Text("Tap a tone to hear it on your keyboard. Nothing changes until you choose **Use for \(sectionLabel)**.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let previewing {
                        Button {
                            model.assignTone(previewing, songId: songId, sectionId: sectionId)
                            dismiss()
                        } label: {
                            Label("Use “\(previewing.name)” for \(sectionLabel)", systemImage: "checkmark.circle.fill").font(.headline)
                        }
                    }
                }
                if !list.songTones.isEmpty {
                    Section("Song tones") { ForEach(list.songTones) { row($0) } }
                }
                if !list.myTones.isEmpty {
                    Section("My tones") { ForEach(list.myTones) { row($0) } }
                }
                ForEach(list.instruments) { group in
                    Section(group.family.displayName) { ForEach(group.entries) { row($0) } }
                }
            }
            .searchable(text: $search, prompt: "Search sounds")
            .navigationTitle("Sound for \(sectionLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.endTonePreview(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use") {
                        if let previewing { model.assignTone(previewing, songId: songId, sectionId: sectionId) }
                        dismiss()
                    }
                    .disabled(previewing == nil)
                }
            }
        }
        .onDisappear { if model.previewingToneId != nil { model.endTonePreview() } }
    }

    private func row(_ entry: Library.ToneList.Entry) -> some View {
        Button { model.previewTone(entry.tone) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.tone.name)
                    Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if model.previewingToneId == entry.tone.id {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.accent).accessibilityLabel("Previewing")
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }
}

// MARK: Free play (no song open)

struct FreePlayView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let recent = model.library.songs.sorted { $0.updatedAt > $1.updatedAt }.prefix(6)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack { ConnectionStatus(midi: model.midi); Spacer() }
                    Text("NOW ON YOUR KEYBOARD").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(model.activeArrangement?.name ?? "No tone selected").font(.title2.weight(.bold))
                }
                .padding(.vertical, 4)
                NavigationLink { ToneSelectorView() } label: { Label("Choose a tone to play", systemImage: "pianokeys") }
            } footer: {
                Text("Play any tone from your Casio keys — like the keyboard's own Piano or Strings.")
            }
            Section("Play along with a song") {
                if recent.isEmpty {
                    Button { model.selectedTab = .library } label: { Label("Add a song in the Library", systemImage: "music.note.list") }
                }
                ForEach(Array(recent)) { song in
                    Button { model.openStudio(song.id) } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(song.title).lineLimit(1)
                                Text(song.analysisStatus == .completed ? "\(song.sections.count) sections · ready" : "Not analysed yet")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            Section {
                NavigationLink { ToneStudioHomeView() } label: { Label("Sound library & My Tones (advanced)", systemImage: "slider.vertical.3") }
            }
            Section("Try a tone") { AuditionStrip() }
        }
        .navigationTitle("Studio")
    }
}
