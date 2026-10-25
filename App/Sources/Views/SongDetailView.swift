import SwiftUI
import TonePilotCore

/// The song page. After import it shows analysis progress; afterwards the automatically built
/// arrangement — sections, tones, chord and melody guidance — with one button to start playing.
struct SongDetailView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let songId: UUID
    @State private var selectedSection: UUID?
    @State private var editingSection: SongSection?
    @State private var editingTone: ToneEditTarget?
    @State private var showLimitations = false
    @State private var showListen = false

    private var song: Song? { model.song(songId) }

    var body: some View {
        if let song {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(song)
                    statusCard(song)
                    if song.analysisStatus == .completed { overviewCard(song); arrangementSummary(song) }
                    if !song.sections.isEmpty || song.duration != nil {
                        Card(title: "Song timeline") {
                            SectionTimeline(song: song, selected: $selectedSection, playhead: model.activeSongId == songId ? model.songPosition : nil)
                        }
                    }
                    sectionsCard(song)
                    if song.analysisStatus == .completed { correctionsCard(song) }
                }
                .padding()
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showListen) { ListenModeView(songId: songId).environmentObject(model) }
            .sheet(item: $editingSection) { section in
                SectionEditorSheet(songId: songId, section: section).environmentObject(model)
            }
            .sheet(item: $editingTone) { target in
                NavigationStack { ArrangementEditorView(songId: songId, arrangementId: target.id) }
                    .environmentObject(model)
            }
        } else {
            ContentUnavailableView("Song not found", systemImage: "questionmark")
        }
    }

    // MARK: Header & status

    private func header(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([song.artist, song.album ?? song.film, song.composer, song.language].compactMap { $0 }.joined(separator: " · ").ifEmpty(" "))
                .font(.subheadline).foregroundStyle(.secondary)
            if song.sourceType == .youtubeLink, let link = song.sourceReference, let url = URL(string: link) {
                Link(destination: url) { Label("Open in YouTube", systemImage: "play.rectangle") }
                Text("Reference link only. Play it in YouTube Music and use Listen Mode to analyse it.").font(.caption).foregroundStyle(.secondary)
                Button { showListen = true } label: { Label("Listen while it plays", systemImage: "ear") }
            }
        }
    }

    private func startAnalysis(_ song: Song) {
        if song.sourceType == .listened || song.sourceType == .youtubeLink { showListen = true; return }
        model.analyze(songId: songId, useServer: model.serverSettings.enabled)
    }

    @ViewBuilder private func statusCard(_ song: Song) -> some View {
        switch song.analysisStatus {
        case .running:
            Card(title: "Building your arrangement") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: model.analysisProgress[songId] ?? 0) {
                        Text(model.analysisStage[songId] ?? "Analysing on this iPhone…").font(.subheadline)
                    }
                    Text("Tempo, key and chords → melody → sections and what plays in each → tones, layers and effects for every section.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Cancel") { model.cancelAnalysis(songId: songId) }.font(.caption)
                }
            }
        case .unavailable:
            EmptyView()
        case .notStarted, .failed:
            Card(title: "Analysis") {
                VStack(alignment: .leading, spacing: 8) {
                    if let e = song.analysisError { Text(e).foregroundStyle(Theme.bad).font(.footnote) }
                    if song.sourceType == .listened {
                        Button { showListen = true } label: { Label("Listen again to analyse", systemImage: "ear") }.buttonStyle(.borderedProminent)
                    } else if song.sourceType == .importedFile {
                        Button { startAnalysis(song) } label: {
                            Label(song.analysisStatus == .failed ? "Try again" : "Analyse & arrange", systemImage: "wand.and.stars")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("No audio. Add sections manually below.").foregroundStyle(.secondary)
                    }
                }
            }
        case .completed:
            EmptyView()
        }
    }

    private func arrangementSummary(_ song: Song) -> some View {
        Card(title: "Ready to play") {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        if let bpm = song.bpm { chip("\(Int(bpm.value.rounded())) BPM", bpm.confidence, bpm.provenance) }
                        if let key = song.key { chip(key.value.displayName, key.confidence, key.provenance) }
                        if let ts = song.timeSignature { chip("\(ts.value)/4", ts.confidence, ts.provenance) }
                        chip("\(song.sections.count) sections", 1, .user)
                        if let m = song.melody {
                            chip(m.source == .vocalStem ? "Melody from vocals" : "Melody from mix", m.source == .vocalStem ? 0.8 : 0.5, .algorithm)
                        }
                        if !(song.stems ?? []).isEmpty { chip("Stems: \((song.stems ?? []).map(\.kind.rawValue).joined(separator: ", "))", 0.8, .model) }
                    }
                }
                if let notice = model.analysisNotice[songId] { Text(notice).font(.caption).foregroundStyle(Theme.warn) }
                Button {
                    model.openStudio(songId)
                    dismiss()
                } label: {
                    Label("Play in Song Studio", systemImage: "pianokeys")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                NavigationLink {
                    MelodyChordGuideView(songId: songId)
                } label: {
                    Label("Melody & chord guide (Root → Fifth → Root)", systemImage: "music.quarternote.3")
                }
                DisclosureGroup("What the AI can and can't do", isExpanded: $showLimitations) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(limitations(song), id: \.self) { Text("• " + $0).font(.caption) }
                    }
                }
                .font(.footnote)
                Button(song.sourceType == .listened ? "Listen again to re-analyse" : "Re-analyse") { startAnalysis(song) }.font(.caption)
            }
        }
    }

    private func overviewCard(_ song: Song) -> some View {
        Card(title: "Song overview") {
            VStack(alignment: .leading, spacing: 6) {
                row("Key", song.key.map { k in
                    let scale = song.insights?.scaleNoteNames.joined(separator: " ") ?? ""
                    return "\(k.value.displayName) · tonic \(NoteName.sharpNames[k.value.tonic])\(scale.isEmpty ? "" : " · notes used: \(scale)")"
                })
                row("Tempo", song.bpm.map { "\(Int($0.value.rounded())) BPM" })
                row("Time", song.timeSignature.map { $0.value == 3 ? "3/4 or 6/8 (3-feel)" : "\($0.value)/4" })
                row("Feel", song.insights?.rhythmicFeel)
                row("Style", song.insights.map { $0.style.joined(separator: " · ") })
                if let movement = song.insights?.rootMovement(from: 0, to: 30), !movement.isEmpty { row("Bass (start)", movement) }
                if let gaps = song.insights?.gaps, !gaps.isEmpty {
                    Text("Not available for this audio: " + gaps.joined(separator: "; ")).font(.caption).foregroundStyle(Theme.warn)
                }
            }
        }
    }

    @ViewBuilder private func row(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top) {
                Text(label).foregroundStyle(.secondary).frame(width: 84, alignment: .leading)
                Text(value)
            }
            .font(.subheadline)
        }
    }

    private func limitations(_ song: Song) -> [String] {
        SongAnalyzer.baseLimitations + ((song.stems ?? []).isEmpty ? [SongAnalyzer.noStemsLimitation] : [
            "Separated stems contain artifacts and bleed; instrument roles are estimates."])
    }

    private func chip(_ text: String, _ confidence: Double, _ provenance: ValueProvenance) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.caption.weight(.semibold))
            if provenance != .user && confidence < 0.6 { Image(systemName: "questionmark.circle").font(.caption2).foregroundStyle(Theme.warn) }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.panelRaised, in: Capsule())
    }

    // MARK: Sections

    private func sectionsCard(_ song: Song) -> some View {
        Card(title: "Sections & AI tones") {
            VStack(spacing: 8) {
                ForEach(song.orderedSections) { section in
                    SectionToneRow(song: song, section: section, isSelected: selectedSection == section.id,
                                   onEditTone: { id in editingTone = ToneEditTarget(id: id) },
                                   onEditSection: { editingSection = section })
                        .onTapGesture { selectedSection = selectedSection == section.id ? nil : section.id }
                }
                Button {
                    let start = song.orderedSections.last?.endTime ?? 0
                    let end = min(song.duration ?? start + 30, start + 30)
                    var s = song
                    let new = SongSection(type: .custom, label: "New section", startTime: start, endTime: max(end, start + 1),
                                          arrangementId: song.arrangements.first?.id)
                    s.sections.append(new)
                    model.update(s)
                    editingSection = new
                } label: { Label("Add section", systemImage: "plus") }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Corrections

    private func correctionsCard(_ song: Song) -> some View {
        Card(title: "Correct the analysis") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Tempo").foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    if let bpm = song.bpm {
                        Text("\(bpm.value, specifier: "%.1f")").font(.body.monospacedDigit())
                        ConfidenceBadge(confidence: bpm.confidence, provenance: bpm.provenance)
                        Spacer()
                        Button("÷2") { setBPM(song, bpm.value / 2) }.buttonStyle(.bordered).controlSize(.small)
                        Button("×2") { setBPM(song, bpm.value * 2) }.buttonStyle(.bordered).controlSize(.small)
                    } else {
                        Text("Not detected").foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Key").foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    Menu(song.key?.value.displayName ?? "Set key") {
                        ForEach(0..<12, id: \.self) { tonic in
                            ForEach([MusicalKey.Mode.major, .minor], id: \.self) { mode in
                                let k = MusicalKey(tonic: tonic, mode: mode)
                                Button(k.displayName) { var s = song; s.key = .user(k); model.update(s) }
                            }
                        }
                    }
                    if let key = song.key { ConfidenceBadge(confidence: key.confidence, provenance: key.provenance) }
                    Spacer()
                }
                HStack {
                    Text("Meter").foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                    Picker("Meter", selection: Binding(get: { song.timeSignature?.value ?? 4 },
                                                       set: { var s = song; s.timeSignature = .user($0); model.update(s) })) {
                        Text("3/4 · 6/8").tag(3); Text("4/4").tag(4)
                    }
                    .pickerStyle(.segmented)
                }
                Text("Chords and melody notes are corrected in the Melody & chord guide; section timing via each section's ⋯ menu.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func setBPM(_ song: Song, _ value: Double) {
        var s = song
        s.bpm = .user((value * 10).rounded() / 10)
        model.update(s)
    }
}

struct ToneEditTarget: Identifiable { let id: UUID }

/// One section: its AI-built tone (My Version), why it was chosen, what was heard, and actions.
struct SectionToneRow: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let section: SongSection
    let isSelected: Bool
    let onEditTone: (UUID) -> Void
    let onEditSection: () -> Void

    private var tone: Arrangement? { song.arrangement(for: section) }
    private var isActive: Bool { model.activeSectionId == section.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(SectionTimeline.color(for: section)).frame(width: 6, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(section.label).font(.headline)
                        if section.isClimax == true { Text("CLIMAX").font(.caption2.bold()).padding(.horizontal, 5).background(Theme.accent.opacity(0.3), in: Capsule()) }
                        if section.provenance != .user { ConfidenceBadge(confidence: section.confidence, provenance: section.provenance) }
                    }
                    Text("\(section.startTime.mmss) – \(section.endTime.mmss)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                Button { model.activate(tone, songId: song.id, sectionId: section.id) } label: {
                    Image(systemName: isActive ? "pianokeys.inverse" : "pianokeys").foregroundStyle(isActive ? Theme.accent : .primary)
                }
                .accessibilityLabel("Use this section's tone on the keyboard")
                Menu {
                    if let tone { Button { onEditTone(tone.id) } label: { Label("Edit tone", systemImage: "slider.horizontal.3") } }
                    if song.sections.filter({ $0.arrangementId == tone?.id }).count > 1 {
                        Button { if let a = model.detachTone(songId: song.id, sectionId: section.id) { onEditTone(a.id) } } label: {
                            Label("Edit just this section", systemImage: "square.on.square.dashed")
                        }
                    }
                    Button { model.regenerateSection(songId: song.id, sectionId: section.id) } label: { Label("Regenerate this section", systemImage: "wand.and.stars") }
                    if song.aiOriginal(for: section) != nil {
                        Button { model.restoreAIOriginal(songId: song.id, sectionId: section.id) } label: { Label("Restore AI Original", systemImage: "arrow.uturn.backward") }
                    }
                    if model.audioURL(for: song) != nil {
                        Button {
                            model.ensurePerformance(songId: song.id)
                            model.playBackingTrack(from: section.startTime, to: section.endTime, loop: true)
                            model.activate(tone, songId: song.id, sectionId: section.id)
                        } label: { Label("Loop this section", systemImage: "repeat") }
                    }
                    Divider()
                    Menu("Use another tone") {
                        ForEach(song.arrangements.filter { $0.origin != .aiOriginal }) { a in Button(a.name) { assign(a.id) } }
                    }
                    Button { onEditSection() } label: { Label("Edit timing & name", systemImage: "timeline.selection") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
            .buttonStyle(.borderless)
            .font(.title3)

            HStack(spacing: 6) {
                Image(systemName: "dial.medium").font(.caption).foregroundStyle(.secondary)
                Text(toneSummary).font(.caption).lineLimit(2)
            }
            if let activity = section.activity, !activity.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(activity.prefix(5).enumerated()), id: \.offset) { _, a in
                            Text("\(a.role.displayName) \(Int(a.level * 100))%")
                                .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                .background((a.source == .stems ? Color.blue : Color.gray).opacity(0.25), in: Capsule())
                        }
                    }
                }
            }
            if isSelected { details }
        }
        .padding(10)
        .background(isSelected || isActive ? Theme.panelRaised : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }

    private var toneSummary: String {
        guard let tone else { return "No tone assigned" }
        let names = tone.layers.compactMap { l -> String? in
            guard let p = model.library.patch(id: l.patchId) else { return nil }
            let hand = l.keyRange.high < 60 ? "LH" : (l.keyRange.low >= 55 ? "RH" : "both")
            return "\(p.name) (\(hand))"
        }
        let edited = tone.origin == .myVersion && tone.updatedAt.timeIntervalSince(tone.createdAt) > 1 ? " · edited" : ""
        return names.joined(separator: " + ") + edited
    }

    @ViewBuilder private var details: some View {
        NavigationLink { SectionGuideView(songId: song.id, sectionId: section.id) } label: {
            Label("Section guide & practice", systemImage: "music.note.list")
        }
        if let rationale = song.aiOriginal(for: section)?.rationale ?? tone?.rationale {
            Text(rationale).font(.caption).foregroundStyle(.secondary)
        }
        if let a = section.activity, !a.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(a.enumerated()), id: \.offset) { _, item in Text("• \(item.evidence)").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        let chords = (song.chordGuide ?? []).filter { $0.time >= section.startTime && $0.time < section.endTime }
        if !chords.isEmpty {
            Text("Chords: " + chords.prefix(10).map(\.chord).joined(separator: "  ")).font(.caption.monospaced()).lineLimit(2)
        }
        let suggestions = song.toneSuggestions.filter { $0.sectionId == section.id }
        if !suggestions.isEmpty {
            Text("Other lead sounds to try (closest-match estimates, not instrument recognition):").font(.caption2).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(suggestions) { s in
                        Button(model.library.patch(id: s.patchId)?.name ?? s.family.displayName) { tryLead(s.patchId) }
                            .buttonStyle(.bordered).font(.caption)
                    }
                }
            }
        }
    }

    private func assign(_ id: UUID) {
        var s = song
        guard let i = s.sections.firstIndex(where: { $0.id == section.id }) else { return }
        s.sections[i].arrangementId = id
        model.update(s)
        if isActive { model.activateSection(section.id) }
    }

    /// Swaps the right-hand lead sound in this section's My Version and makes it audible.
    private func tryLead(_ patchId: UUID) {
        guard var tone, tone.origin != .aiOriginal else { return }
        if let i = tone.layers.firstIndex(where: { [.lead, .vocalMelody, .motif].contains($0.role) }) {
            tone.layers[i].patchId = patchId
            tone.layers[i].expressionOverride = nil
        } else {
            tone.layers.insert(Layer(patchId: patchId, volume: 0.75, keyRange: KeyRange(low: 60, high: 127), role: .lead), at: 0)
        }
        model.updateArrangement(tone, inSong: song.id)
        model.activate(tone, songId: song.id, sectionId: section.id)
    }
}
