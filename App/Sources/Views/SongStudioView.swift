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

/// The Song Studio's pages, always visible in a fixed segmented control at the top (UX audit C1).
/// `play` is the calm performance view; the others configure. Raw values are kept stable: they are
/// saved per user and used as accessibility identifiers ("page.keyboard" is the Tone page).
enum StudioPage: String, CaseIterable, Identifiable {
    case play, mix, keyboard, arpeggio, sections
    var id: String { rawValue }
    var title: String {
        switch self {
        case .play: return "Play"
        case .mix: return "Mix"
        case .keyboard: return "Tone"
        case .arpeggio: return "Arpeggio"
        case .sections: return "Sections"
        }
    }
    var symbol: String {
        switch self {
        case .play: return "play.fill"
        case .mix: return "slider.vertical.3"
        case .keyboard: return "waveform.path"
        case .arpeggio: return "chart.bar.fill"
        case .sections: return "rectangle.split.3x1"
        }
    }
}

/// One screen to play a song: timeline, your keyboard, the AI background band, the parts the AI
/// plays for you, and each section's tone. "You choose what to play. TonePilot fills in the rest."
struct SongStudioView: View {
    @EnvironmentObject var model: AppModel
    let songId: UUID
    @State private var pickingToneFor: SectionRef?
    @State private var editingTone: ToneEditTarget?
    /// The tone editor opens full height (its layers are its main content); it can be pulled down to half.
    @State private var toneDetent: PresentationDetent = .large
    /// Blind A/B listening test of two tones on the song's melody.
    @State private var comparing = false
    @State private var guideFor: UUID?
    @State private var editingSection: SongSection?
    @State private var showDetails = false
    @State private var showMelodyGuide = false
    /// The chord step being corrected (sheet).
    @State private var correctingChord: SectionRef?
    @State private var showSoundLibrary = false
    @State private var showListen = false
    @AppStorage("studioPage") private var page = StudioPage.play

    var body: some View {
        if let song = model.song(songId) {
            VStack(spacing: 0) {
                // Fixed: which song, and the five pages — never scrolled away, never under the transport.
                DSSegmentedControl(items: StudioPage.allCases, selection: $page, title: \.title,
                                   identifier: { "page.\($0.rawValue)" }, symbol: \.symbol)
                .padding(.horizontal, DS.Space.screenMargin).padding(.top, DS.Space.xs).padding(.bottom, DS.Space.s)
                ScrollView {
                    VStack(spacing: DS.Space.m) {
                        switch page {
                        case .play:
                            StudioAnalysisStatus(song: song, onListen: { showListen = true })
                            SeparationCard(song: song)
                            PerformanceHeader(song: song)
                            SongMapTimeline(song: song)
                            if !(song.chordGuide ?? []).isEmpty {
                                ChordKeysCard(song: song) { stepId in
                                    if let stepId { correctingChord = SectionRef(id: stepId) } else { showMelodyGuide = true }
                                }
                            }
                            ToneRow(song: song) { page = .keyboard }
                        case .mix:
                            SongPartsCard(song: song)
                            AIPartsCard(song: song)
                        case .keyboard:
                            MyKeyboardCard(song: song, onChangeSound: changeSound, onEditSound: editSound, onEditTone: { editingTone = ToneEditTarget(id: $0) },
                                           onCompare: { comparing = true })
                        case .arpeggio:
                            SongArpeggioCard(song: song)
                        case .sections:
                            StudioSectionsCard(song: song, onChangeSound: changeSound, onEditSound: editSound,
                                               onGuide: { guideFor = $0 }, onEditTiming: { editingSection = $0 })
                        }
                    }
                    .padding(.horizontal, DS.Space.screenMargin).padding(.top, DS.Space.xs).padding(.bottom, DS.Space.xl)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { TransportBar(song: song, live: model.live) }
            .dsCanvas()
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar(song) }
            .sheet(item: $pickingToneFor) { ref in
                TonePickerSheet(songId: songId, sectionId: ref.id).environmentObject(model)
            }
            .sheet(item: $editingTone) { target in
                NavigationStack { ArrangementEditorView(songId: songId, arrangementId: target.id, onDone: { editingTone = nil }) }
                    .environmentObject(model)
                    .presentationDetents([.medium, .large], selection: $toneDetent)
                    .onAppear { toneDetent = .large }
            }
            .sheet(isPresented: $comparing) {
                NavigationStack { BlindCompareView(songId: songId, onDone: { comparing = false }) }
                    .environmentObject(model)
            }
            .sheet(item: $editingSection) { section in
                SectionEditorSheet(songId: songId, section: section).environmentObject(model)
            }
            .sheet(isPresented: $showListen) { ListenModeView(songId: songId).environmentObject(model) }
            .sheet(item: $correctingChord) { ref in ChordCorrectionSheet(songId: songId, stepId: ref.id).environmentObject(model) }
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

    @ToolbarContentBuilder
    private func toolbar(_ song: Song) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { model.selectedTab = .library } label: {
                HStack(spacing: DS.Space.xxs) {
                    Image(systemName: "chevron.left").font(DS.Text.body.weight(.semibold))
                    Text("Songs").font(DS.Text.body)
                }
            }
            .accessibilityLabel("Songs")
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: DS.Space.s) {
                SongCover(song: song, size: 26)
                Text(song.title).font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("studio.context")
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

/// The performance view's main readout: the section playing now, large, and the one after it —
/// legible at arm's length from the keyboard. Redraws with the song position (LiveState) only here.
struct PerformanceHeader: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View { PerformanceHeaderContent(song: song, live: model.live) }
}

private struct PerformanceHeaderContent: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    @ObservedObject var live: LiveState

    var body: some View {
        let pos = live.position ?? model.cursor
        let ordered = song.orderedSections
        let index = ordered.lastIndex { $0.startTime <= pos + 0.01 }
        let current = index.map { ordered[$0] }
        let next = index.flatMap { $0 + 1 < ordered.count ? ordered[$0 + 1] : nil } ?? (index == nil ? ordered.first : nil)
        let isHook = current.map { SongMapStyle.hookIds(song).contains($0.id) } ?? false
        let hasAudio = model.audioURL(for: song) != nil
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("NOW").font(DS.Text.metadata.weight(.semibold)).foregroundStyle(DS.Palette.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s) {
                        Text(current?.label ?? (ordered.isEmpty ? "No sections yet" : "Ready"))
                            .font(.system(.largeTitle, design: .default).weight(.heavy)).foregroundStyle(DS.Palette.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("★").font(.title2.weight(.bold)).foregroundStyle(DS.Palette.accent).opacity(isHook ? 1 : 0)
                            .accessibilityHidden(!isHook)
                    }
                }
                Spacer(minLength: DS.Space.s)
                // Always present (opacity, not `if`), so nothing moves while playing.
                VStack(alignment: .trailing, spacing: DS.Space.xxs) {
                    Text("NEXT").font(DS.Text.metadata.weight(.semibold)).foregroundStyle(DS.Palette.textSecondary)
                    Text(next?.label ?? "—").font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                    Text(next.map { "in \(max(0, $0.startTime - pos).mmss)" } ?? " ").font(DS.Text.numericSmall).foregroundStyle(DS.Palette.textSecondary)
                }
                .opacity(next == nil ? 0.4 : 1)
            }
            if !hasAudio {
                Text("No recording on this iPhone — Play starts the song clock.").font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now \(current?.label ?? "ready")\(isHook ? ", the hook" : ""). Next \(next?.label ?? "none")")
        .accessibilityIdentifier("play.section")
    }
}

/// Analysis progress, failures and notices (only shown when there's something to say).
struct StudioAnalysisStatus: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let onListen: () -> Void

    var body: some View {
        switch song.analysisStatus {
        case .running where song.sourceType != .listened, .failed where song.sourceType != .listened:
            // Imported songs: the step list (spec §2.3).
            AnalysisStepList(song: song, hasParts: !model.stemKinds(for: song).isEmpty)
        case .running:
            // Listen Mode runs as one step (no recording to play), so a single progress line.
            VStack(alignment: .leading, spacing: DS.Space.s) {
                Text("Analysing what TonePilot heard").font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary)
                ProgressView(value: model.analysisProgress[song.id] ?? 0).tint(DS.Palette.accent)
                Button("Cancel") { model.cancelAnalysis(songId: song.id) }
                    .buttonStyle(.dsSecondary).accessibilityIdentifier("analysis.cancel")
            }
            .dsSurface()
        case .failed, .notStarted:
            VStack(alignment: .leading, spacing: DS.Space.s) {
                if let e = song.analysisError { Text(e).font(DS.Text.caption).foregroundStyle(DS.Palette.error) }
                if song.sourceType == .listened {
                    Button("Listen again to analyse", action: onListen).buttonStyle(.dsPrimary)
                } else if model.audioURL(for: song) != nil {
                    Button("Analyse this song") { model.analyze(songId: song.id, useServer: model.serverSettings.enabled) }
                        .buttonStyle(.dsPrimary)
                        .accessibilityIdentifier("analysis.start")
                }
            }
            .dsSurface()
        default:
            if let notice = model.analysisNotice[song.id] {
                Label(notice, systemImage: "info.circle").font(DS.Text.metadata).foregroundStyle(DS.Palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: Tone mode and pages

/// Your keyboard's tone for this song: one main tone, or a tone per section. Saved with the song.
struct ToneModeSwitch: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View {
        let main = model.isUsingMainTone(song)
        HStack(spacing: 10) {
            Text("Tone").font(DS.Text.label).foregroundStyle(DS.Palette.textPrimary)
            Spacer(minLength: 4)
            HStack(spacing: 0) {
                option("Whole song", selected: main, id: "tonemode.main") { model.useMainTone(song.id) }
                option("Per section", selected: !main, id: "tonemode.sections") { model.useSectionTones(song.id) }
            }
            .padding(3)
            .background(DS.Palette.elevated, in: Capsule())
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func option(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(DS.Text.label)
                .padding(.horizontal, 12).frame(minHeight: 36)
                .background(selected ? DS.Palette.accent : Color.clear, in: Capsule())
                .foregroundStyle(selected ? .black : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Player bar

/// Always-visible player at the bottom of the Song Studio (like Moises and Apple Music):
/// progress, loop, back/forward 5 s, play and speed — reachable with one thumb.
struct TransportBar: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    @ObservedObject var live: LiveState

    var body: some View {
        let playing = model.isStudioPlaying
        let pos = live.position ?? model.cursor
        let duration = max(song.duration ?? song.sections.map(\.endTime).max() ?? 1, 1)
        let hasAudio = model.audioURL(for: song) != nil
        VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule().fill(DS.Palette.accent).frame(width: geo.size.width * min(1, max(0, pos / duration)))
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                    model.studioSeek(to: Double(max(0, min(1, v.location.x / max(1, geo.size.width)))) * duration)
                })
            }
            .frame(height: 16)
            .accessibilityElement()
            .accessibilityLabel("Position")
            .accessibilityValue("\(pos.mmss) of \(duration.mmss)")
            .accessibilityAdjustableAction { model.studioSeek(to: $0 == .increment ? pos + 10 : max(0, pos - 10)) }
            HStack {
                Text(pos.mmss)
                Spacer()
                Text(duration.mmss)
            }
            .font(.caption2.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
            HStack(spacing: 0) {
                barButton(model.loopSectionId == nil ? "repeat" : "repeat.1", label: model.loopSectionId == nil ? "Loop this section" : "Stop looping",
                          active: model.loopSectionId != nil) { model.studioToggleLoop() }
                    .disabled(song.sections.isEmpty || !hasAudio)
                Spacer()
                barButton("gobackward.5", label: "Back 5 seconds") { model.studioSeek(to: max(0, pos - 5)) }
                Spacer()
                Button { model.studioTogglePlay() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .frame(width: DS.Size.transportPlay, height: DS.Size.transportPlay)
                        .background(DS.accentGradient, in: Circle())
                        .shadow(color: DS.Palette.accentGlow, radius: 12, y: 5)
                        .foregroundStyle(DS.Palette.onAccent)
                }
                .accessibilityLabel(playing ? "Pause" : (hasAudio ? "Play" : "Start song clock"))
                .accessibilityIdentifier("transport.play")
                .disabled(song.sections.isEmpty && !hasAudio)
                Spacer()
                barButton("goforward.5", label: "Forward 5 seconds") { model.studioSeek(to: min(duration, pos + 5)) }
                Spacer()
                Menu {
                    ForEach([Float(0.5), 0.75, 0.9, 1], id: \.self) { r in
                        Button { model.setStudioRate(r) } label: {
                            if model.studioRate == r { Label("\(Int(r * 100))%", systemImage: "checkmark") } else { Text("\(Int(r * 100))%") }
                        }
                    }
                } label: {
                    Text(model.studioRate == 1 ? "1×" : "\(Int(model.studioRate * 100))%")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(width: 48, height: 48)
                        .foregroundStyle(model.studioRate == 1 ? Color.primary : DS.Palette.accent)
                }
                .accessibilityLabel("Speed \(Int(model.studioRate * 100)) percent")
                .disabled(!hasAudio)
            }
        }
        .padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func barButton(_ symbol: String, label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3.weight(.semibold))
                .frame(width: 48, height: 48)
                .foregroundStyle(active ? DS.Palette.accent : .primary)
        }
        .accessibilityLabel(label)
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
                .frame(height: 64)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(song.orderedSections) { s in
                            let isCurrent = current?.id == s.id
                            Button { model.studioJump(to: s.id) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.label).font(DS.Text.label).lineLimit(1)
                                    Text(s.startTime.mmss).font(.caption2.monospacedDigit())
                                }
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(isCurrent ? DS.Palette.accent : DS.Palette.elevated, in: RoundedRectangle(cornerRadius: 10))
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
        }
        .padding(14)
        .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 14))
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
                ctx.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(DS.Palette.accent))
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
        // Always shown (at the cursor when paused), so the screen doesn't jump on play/pause.
        LiveGuideStrip(song: song, time: live.position ?? model.cursor, melodyOffset: AutoArranger.guideOffset(for: model.activeArrangement))
            .animation(nil, value: live.position)
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Separating vocals, drums, bass & music").font(DS.Text.label)
                        Text(timeText(p)).font(.caption.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
                    }
                    Spacer()
                    Button("Cancel") { model.cancelSeparation(song.id) }.font(DS.Text.metadata.weight(.semibold))
                }
                ProgressView(value: p).tint(DS.Palette.accent)
                Text("You can already play with the full recording. Keep TonePilot open.")
                    .font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
            }
            .padding(14)
            .background(DS.Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        } else if let d = model.modelDownloadProgress[model.separationPack] {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Downloading the separation model (one time)…").font(DS.Text.label)
                    Spacer()
                    Text("\(Int(d * 100))%").font(.caption.monospacedDigit())
                }
                ProgressView(value: d).tint(DS.Palette.accent)
                Text("Separation starts automatically when it's done. Wi-Fi recommended.").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
            }
            .padding(14)
            .background(DS.Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        } else if !separated, model.audioURL(for: song) != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "scissors").font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .background(DS.Palette.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(DS.Palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Separate the parts").font(DS.Text.label)
                        if let e = model.separationError[song.id] ?? model.modelDownloadError {
                            Text(e).font(DS.Text.metadata).foregroundStyle(DS.Palette.error).lineLimit(3)
                        } else {
                            Text(song.analysisStatus == .running ? "Starts after the analysis." : model.separationPack.detail)
                                .font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                        }
                    }
                    Spacer(minLength: 4)
                    Button(model.separationError[song.id] == nil ? "Start" : "Retry") { model.separateStems(song.id) }
                        .buttonStyle(.borderedProminent)
                        .disabled(song.analysisStatus == .running)
                        .accessibilityIdentifier("separate.start")
                }
                Picker("Parts", selection: $model.separationPack) {
                    ForEach(SeparationPack.allCases) { Text($0 == .four ? "4 parts" : "6 parts · + Piano & Guitar").tag($0) }
                }
                .pickerStyle(.segmented)
                if !model.models.isInstalled(model.separationPack) {
                    Text("The first time, the separation model is downloaded (Wi-Fi recommended).").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .padding(14)
            .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func timeText(_ p: Double) -> String {
        var t = "\(Int(p * 100))%"
        if let left = model.separationTimeLeft(song.id) {
            t += left < 60 ? " · less than a minute left" : " · about \(Int((left / 60).rounded(.up))) min left"
        }
        return t
    }
}

// MARK: My keyboard

/// P3.3: what the 4-part and 6-part separations heard for the main tone, and which matches are used.
struct FusionLine: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View {
        if let p = model.fusionProgress[song.id] {
            Text("Checking the tone with the \(model.separatedPack(song) == .six ? "4" : "6")-part model… \(Int(p * 100))%")
                .font(.caption2.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
                .accessibilityIdentifier("fusion.status")
        } else if let f = song.fusion, f.isCurrent(song) {
            Menu {
                ForEach(PartFusion.Choice.allCases, id: \.self) { c in
                    Button { model.setFusionChoice(c, songId: song.id) } label: {
                        if c == f.choice { Label(c.title, systemImage: "checkmark") } else { Text(c.title) }
                    }
                }
            } label: {
                let e = f.mainEntry(song)
                Label(e.map(PartFusion.describe) ?? "Tone checked with both separations", systemImage: e?.agreement == .different ? "arrow.triangle.branch" : "checkmark.seal")
                    .font(DS.Text.metadata).lineLimit(2).multilineTextAlignment(.leading)
            }
            .accessibilityIdentifier("tone.fusion")
        } else if let e = model.fusionError[song.id] {
            Text(e).font(DS.Text.metadata).foregroundStyle(DS.Palette.warning).lineLimit(2)
        } else if model.fusionEnabled, let pack = model.separatedPack(song), song.partMatches?.isEmpty == false, !model.isSeparating(song.id) {
            Button { model.startFusionIfNeeded(song.id) } label: {
                Label("Check the tone with the \(pack == .six ? "4" : "6")-part model too", systemImage: "square.stack.3d.up")
                    .font(DS.Text.metadata)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("fusion.start")
        }
    }
}

// MARK: Song parts (from the recording)

struct SongPartsCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View {
        let tracks = model.studioTracks(for: song).filter { $0.group == .songParts }
        let acc = song.accompaniment ?? AccompanimentSettings()
        let stems = tracks.filter { $0.id != SongStudio.original }
        let clearSolo: (title: String, id: String, run: () -> Void)? = stems.contains(where: \.soloed)
            ? (title: "Clear solo", id: "parts.clearSolo", run: { stems.filter(\.soloed).forEach { model.toggleSolo($0.id, songId: song.id) } })
            : nil
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                DSSectionHeader(title: "Parts", action: clearSolo)
                if stems.isEmpty {
                    Text("The full recording. Separate the parts to turn the vocals, drums, bass and music on and off.")
                        .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
                    ForEach(tracks) { TrackRow(track: $0, songId: song.id) }
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(stems.enumerated()), id: \.element.id) { i, t in
                            PartRow(track: t, songId: song.id, gated: SongStudio.isGated(t.id, acc))
                            if i < stems.count - 1 { Divider().overlay(DS.Palette.divider).padding(.leading, 68) }
                        }
                    }
                    .dsSurface(padding: 0)
                    Label("Mute a part to play it yourself.", systemImage: "info.circle")
                        .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
                    musicSplit
                    if let full = tracks.first(where: { $0.id == SongStudio.original }) {
                        DisclosureGroup("Full recording") { TrackRow(track: full, songId: song.id).padding(.top, 6) }
                            .font(DS.Text.bodySecondary).tint(DS.Palette.textSecondary)
                    }
                }
            }
        }
    }
}

extension SongPartsCard {
    /// Split the Music part into Lead instruments and Backing (automatic after separation).
    @ViewBuilder var musicSplit: some View {
        if let p = model.musicSplitProgress[song.id] {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Finding the lead instruments in the music… \(Int(p * 100))%").font(DS.Text.metadata)
            }
        } else if model.canSplitMusic(song) {
            Button { model.splitMusic(song.id) } label: {
                Label("Split Music into Lead & Backing", systemImage: "wand.and.rays").labelStyle(.titleAndIcon)
                    .font(DS.Text.label).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.dsSecondary)
            .accessibilityIdentifier("parts.split")
            .accessibilityHint("Separates the lead melodies from the pads and chords")
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
                        .font(DS.Text.body)
                        .frame(width: 28)
                        .foregroundStyle(track.enabled ? DS.Palette.accent : .secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(track.name).font(DS.Text.label)
                            TrackKindBadge(kind: track.kind)
                        }
                        Text(track.detail).font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if track.canSolo {
                        Button { model.toggleSolo(track.id, songId: songId) } label: {
                            Text("S").font(.caption.bold())
                                .frame(width: 32, height: 32)
                                .background(track.soloed ? DS.Palette.accent : DS.Palette.elevated, in: RoundedRectangle(cornerRadius: 8))
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
                    Image(systemName: "speaker.fill").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                    Slider(value: $level, in: 0...1) { editing in
                        dragging = editing
                        if !editing { model.setTrackLevel(track.id, level, songId: songId) }
                    }
                    .accessibilityLabel("\(track.name) volume")
                    Image(systemName: "speaker.wave.3.fill").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
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
            case .generated: return ("AI notes", DS.Palette.accent)
            case .live: return ("Live", DS.Palette.success)
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
        let sources = tracks.filter { [SongStudio.stem(.lead), SongStudio.stem(.other), SongStudio.stem(.vocals)].contains($0.id) }
        let current = acc.aiPartTrack.flatMap { id in sources.first { $0.id == id } } ?? sources.first
        let on = acc.aiPartTrack != nil && acc.aiPartsEnabled == true && current != nil
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if sources.isEmpty {
                Label("Original plays hard parts", systemImage: "wand.and.stars").font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary)
                Text("Available after the song is split into parts.").font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
            } else {
                // Spec: one toggle row, short copy; the details only when it's on.
                Toggle(isOn: Binding(get: { on }, set: { v in
                    if v, acc.aiPartTrack == nil, let first = current { model.setAIPartSource(first.id, songId: song.id) }
                    model.setAIParts(v, songId: song.id)
                })) {
                    HStack(spacing: DS.Space.m) {
                        Image(systemName: "wand.and.stars").foregroundStyle(on ? DS.Palette.accent : DS.Palette.textSecondary)
                            .frame(width: DS.Size.touchTarget - DS.Space.s, height: DS.Size.touchTarget - DS.Space.s)
                            .background(on ? DS.Palette.accentMuted : DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                        VStack(alignment: .leading, spacing: DS.Space.xxs) {
                            Text("Original plays hard parts").font(DS.Text.body.weight(.semibold)).foregroundStyle(DS.Palette.textPrimary)
                            Text("In the sections you pick. Everywhere else, it's you.").font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
                        }
                    }
                }
                .tint(DS.Palette.accent)
                .accessibilityIdentifier("aiparts.toggle")
                if on, let current {
                    Picker("Played by", selection: Binding(get: { current.id }, set: { model.setAIPartSource($0, songId: song.id) })) {
                        ForEach(sources) { t in
                            Text(t.id == SongStudio.stem(.vocals) ? "Vocals" : t.id == SongStudio.stem(.lead) ? "Lead instruments" : "All music").tag(t.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Plays in").font(DS.Text.caption.weight(.semibold)).foregroundStyle(DS.Palette.textSecondary)
                    FlowSections(song: song, selected: acc.guideSections) { model.toggleAIPart($0, songId: song.id) }
                    HStack {
                        Button("Suggested") { model.setAIPartSections(SongStudio.suggestedAIParts(song, source: acc.aiPartTrack), songId: song.id) }
                        Button("Whole song") { model.setAIPartSections(nil, songId: song.id) }
                        Spacer()
                    }
                    .font(DS.Text.caption).buttonStyle(.bordered).tint(DS.Palette.accent)
                    TrackRow(track: { var t = current; t.enabled = true; return t }(), songId: song.id, showHeader: false)
                }
            }
        }
        .dsSurface()
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
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").font(DS.Text.metadata)
                        Text(s.label).font(DS.Text.metadata).lineLimit(1)
                    }
                    .padding(.horizontal, 8).frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .background(on ? DS.Palette.accent.opacity(0.25) : DS.Palette.elevated, in: RoundedRectangle(cornerRadius: 8))
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
        // Spec §2.12: the Song Map full width, then one row per section (colour = repeat group, ★ hook).
        let colors = SongMapStyle.groupColors(song)
        let hooks = SongMapStyle.hookIds(song)
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if song.sections.isEmpty {
                DSEmptyState(symbol: "rectangle.split.3x1", title: "No sections yet",
                             message: song.analysisStatus == .running ? "Sections appear when the analysis finishes." : "Analyse the song to find its sections.")
            } else {
                SongMapTimeline(song: song)
                Text("Tap a section to jump there.").font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
                VStack(spacing: 0) {
                    ForEach(Array(song.orderedSections.enumerated()), id: \.element.id) { n, section in
                        StudioSectionRow(song: song, section: section, index: n,
                                         color: hooks.contains(section.id) ? DS.Palette.accent : (colors[section.id] ?? DS.Palette.group[0]),
                                         isHook: hooks.contains(section.id),
                                         onChangeSound: onChangeSound, onEditSound: onEditSound,
                                         onGuide: onGuide, onEditTiming: onEditTiming)
                        if n < song.sections.count - 1 { Divider().overlay(DS.Palette.divider).padding(.leading, DS.Space.l) }
                    }
                }
                .dsSurface(padding: DS.Space.s)
            }
        }
    }
}

struct StudioSectionRow: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let section: SongSection
    var index = 0
    var color: Color = DS.Palette.group[0]
    var isHook = false
    let onChangeSound: (UUID) -> Void
    let onEditSound: (UUID) -> Void
    let onGuide: (UUID) -> Void
    let onEditTiming: (SongSection) -> Void

    var body: some View {
        let tone = song.arrangement(for: section)
        let isCurrent = model.activeSectionId == section.id
        let acc = song.accompaniment ?? AccompanimentSettings()
        let aiPlays = SongStudio.aiPartsOn(acc) && (acc.guideSections?.contains(section.id) ?? true)
        let drawing = ToneRow.drawings(tone, library: model.library).first ?? .synth
        HStack(spacing: DS.Space.m) {
            RoundedRectangle(cornerRadius: DS.Space.xxs).fill(color).frame(width: DS.Space.xs)
                .padding(.vertical, DS.Space.xs)
            Button { model.studioJump(to: section.id) } label: {
                HStack(spacing: DS.Space.m) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        HStack(spacing: DS.Space.xs) {
                            Text(section.label).font(DS.Text.body.weight(.semibold))
                                .foregroundStyle(isCurrent ? DS.Palette.accent : DS.Palette.textPrimary).lineLimit(1)
                            if isHook { Image(systemName: "star.fill").font(DS.Text.metadata).foregroundStyle(DS.Palette.accent).accessibilityLabel("Hook") }
                            if aiPlays { Image(systemName: "wand.and.stars").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary).accessibilityLabel("TonePilot plays the melody here") }
                        }
                        Text("\(section.startTime.mmss) – \(section.endTime.mmss)")
                            .font(DS.Text.metadata.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
                    }
                    Spacer(minLength: DS.Space.s)
                    HStack(spacing: DS.Space.s) {
                        InstrumentTile(drawing: drawing, size: DS.Space.xxl)
                        Text(tone?.name.replacingOccurrences(of: " (My Version)", with: "") ?? "No tone")
                            .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary).lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Jumps to this section")
            .accessibilityIdentifier("sections.row.\(index)")
            Menu {
                Button { model.studioJump(to: section.id) } label: { Label("Play from here", systemImage: "play") }
                Button {
                    model.studioJump(to: section.id)
                    if model.loopSectionId != nil { model.studioToggleLoop() }   // clear any other loop first
                    model.studioToggleLoop()
                } label: {
                    Label("Loop this section", systemImage: "repeat")
                }
                Button { onChangeSound(section.id) } label: { Label("Change tone", systemImage: "music.note.list") }
                Button { onEditSound(section.id) } label: { Label("Edit tone", systemImage: "slider.horizontal.3") }
                if song.sections.filter({ $0.arrangementId == tone?.id }).count > 1 {
                    Button {
                        _ = model.detachTone(songId: song.id, sectionId: section.id)
                        onEditSound(section.id)
                    } label: { Label("Edit just this section", systemImage: "square.on.square.dashed") }
                }
                if song.aiOriginal(for: section) != nil, tone?.origin == .myVersion {
                    Button { model.restoreAIOriginal(songId: song.id, sectionId: section.id) } label: { Label("Back to TonePilot's tone", systemImage: "arrow.uturn.backward") }
                }
                Divider()
                Button { onGuide(section.id) } label: { Label("Section guide and practice", systemImage: "music.note.list") }
                Button { onEditTiming(section) } label: { Label("Edit timing and name", systemImage: "timeline.selection") }
            } label: {
                Image(systemName: "ellipsis.circle").font(DS.Text.screenTitle.weight(.regular))
                    .foregroundStyle(DS.Palette.textSecondary)
                    .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget).contentShape(Rectangle())
            }
            .accessibilityLabel("\(section.label) options")
            .accessibilityIdentifier("sections.more.\(index)")
        }
        .padding(.vertical, DS.Space.xs).padding(.horizontal, DS.Space.xs)
        .background(isCurrent ? DS.Palette.accentMuted : Color.clear, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
    }
}

// MARK: Tone picker (preview, then apply)

/// Sound browser (spec §2.8, GarageBand): search, this song's tones, family chips and a grid of tiles.
/// Tap a tile to hear it on your keyboard; nothing changes until **Use this**.
struct TonePickerSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let songId: UUID
    let sectionId: UUID
    @State private var search = ""
    @State private var family: InstrumentFamily?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: DS.Space.m)]

    var body: some View {
        let list = model.library.toneList(search: search)
        let sectionLabel = model.song(songId)?.sections.first { $0.id == sectionId }?.label ?? "this section"
        let previewing = model.previewingToneId.flatMap { model.tone(id: $0) }
        let fromSong = list.songTones.filter { $0.songId == songId }
        let families = list.instruments.map(\.family)
        let groups = list.instruments.filter { family == nil || $0.family == family }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    if !fromSong.isEmpty, family == nil {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            Text("From this song").font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary)
                            grid(fromSong, large: true)
                        }
                    }
                    if family == nil, !list.myTones.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            Text("My tones").font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary)
                            grid(list.myTones, large: false)
                        }
                    }
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            Text(g.family.displayName).font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary)
                            grid(g.entries, large: false)
                        }
                    }
                    if groups.isEmpty && fromSong.isEmpty && list.myTones.isEmpty {
                        DSEmptyState(symbol: "magnifyingglass", title: "No sounds match", message: "Try another name.")
                    }
                }
                .padding(.horizontal, DS.Space.screenMargin).padding(.vertical, DS.Space.m)
            }
            .safeAreaInset(edge: .top, spacing: 0) { chips(families) }
            .safeAreaInset(edge: .bottom, spacing: 0) { useBar(previewing, sectionLabel: sectionLabel) }
            .dsCanvas()
            .searchable(text: $search, prompt: "Search sounds")
            .navigationTitle("Sound for \(sectionLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { model.endTonePreview(); dismiss() }.accessibilityIdentifier("sounds.cancel")
                }
            }
        }
        .onDisappear { if model.previewingToneId != nil { model.endTonePreview() } }
    }

    private func chips(_ families: [InstrumentFamily]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s) {
                chip("All", selected: family == nil, id: "sounds.family.all") { family = nil }
                ForEach(families, id: \.self) { f in
                    chip(f.displayName, selected: family == f, id: "sounds.family.\(f.rawValue)") { family = f }
                }
            }
            .padding(.horizontal, DS.Space.screenMargin).padding(.vertical, DS.Space.s)
        }
        .background(DS.Palette.canvas)
    }

    private func chip(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(DS.Text.label)
                .padding(.horizontal, DS.Space.m).frame(minHeight: DS.Size.touchTarget - DS.Space.xs)
                .foregroundStyle(selected ? DS.Palette.onAccent : DS.Palette.textPrimary)
                .background(selected ? DS.Palette.accent : DS.Palette.elevated, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func grid(_ entries: [Library.ToneList.Entry], large: Bool) -> some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.l) {
            ForEach(entries) { tile($0, large: large) }
        }
    }

    private func tile(_ entry: Library.ToneList.Entry, large: Bool) -> some View {
        let selected = model.previewingToneId == entry.tone.id
        let drawing = ToneRow.drawings(entry.tone, library: model.library).first ?? .synth
        return Button { model.previewTone(entry.tone) } label: {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                InstrumentTile(drawing: drawing, size: large ? 96 : 80, selected: selected)
                Text(entry.tone.name).font(DS.Text.caption.weight(.semibold))
                    .foregroundStyle(selected ? DS.Palette.accent : DS.Palette.textPrimary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(entry.subtitle).font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.tone.name)\(selected ? ", playing on your keys" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("sounds.tile.\(entry.tone.name)")
    }

    private func useBar(_ previewing: Arrangement?, sectionLabel: String) -> some View {
        HStack(spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(previewing == nil ? "Tap a sound to hear it" : "On your keys now")
                    .font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                Text(previewing?.name ?? "Nothing changes until you choose").font(DS.Text.label)
                    .foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
            }
            Spacer(minLength: DS.Space.s)
            Button("Use this") {
                if let previewing { model.assignTone(previewing, songId: songId, sectionId: sectionId) }
                dismiss()
            }
            .buttonStyle(.dsPrimary)
            .frame(maxWidth: 150)
            .disabled(previewing == nil)
            .accessibilityHint("Uses it for \(sectionLabel)")
            .accessibilityIdentifier("sounds.use")
        }
        .padding(.horizontal, DS.Space.screenMargin).padding(.vertical, DS.Space.m)
        .background(.bar)
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
                    Text("NOW ON YOUR KEYBOARD").font(.caption2.weight(.bold)).foregroundStyle(DS.Palette.textSecondary)
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
                                    .font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
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
        .navigationTitle("Play")
    }
}
