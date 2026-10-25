import SwiftUI
import TonePilotCore

struct SongDetailView: View {
    @EnvironmentObject var model: AppModel
    let songId: UUID
    @State private var selectedSection: UUID?
    @State private var editingSection: SongSection?
    @State private var editingArrangement: Arrangement?
    @State private var loop = true
    @State private var showLimitations = false

    private var song: Song? { model.song(songId) }

    var body: some View {
        if let song {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(song)
                    analysisCard(song)
                    if !song.sections.isEmpty || song.duration != nil { timelineCard(song) }
                    sectionsCard(song)
                    arrangementsCard(song)
                }
                .padding()
            }
            .navigationTitle(song.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $editingSection) { section in
                SectionEditorSheet(songId: songId, section: section).environmentObject(model)
            }
            .sheet(item: $editingArrangement) { arrangement in
                NavigationStack { ArrangementEditorView(songId: songId, arrangementId: arrangement.id) }
                    .environmentObject(model)
            }
            .onDisappear { model.sectionPlayer.stop(); model.isSectionPlaying = false }
        } else {
            ContentUnavailableView("Song not found", systemImage: "questionmark")
        }
    }

    // MARK: Header

    private func header(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text([song.film, song.composer, song.language].compactMap { $0 }.joined(separator: " · ").ifEmpty("Add film, composer and language in Edit details"))
                .font(.subheadline).foregroundStyle(.secondary)
            if song.sourceType == .youtubeLink, let link = song.sourceReference, let url = URL(string: link) {
                Link(destination: url) { Label("Open in YouTube", systemImage: "play.rectangle") }
                Text("Reference link only — import an audio file you own to analyse this song.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Analysis

    private func analysisCard(_ song: Song) -> some View {
        Card(title: "Analysis") {
            switch song.analysisStatus {
            case .running:
                VStack(alignment: .leading) {
                    ProgressView(value: model.analysisProgress[songId] ?? 0) {
                        Text("Analysing on this iPhone…")
                    }
                    Button("Cancel") { model.cancelAnalysis(songId: songId) }.font(.caption)
                }
            case .unavailable:
                Text("Not available for link-only songs.").foregroundStyle(.secondary)
            case .notStarted, .failed:
                VStack(alignment: .leading, spacing: 8) {
                    if let e = song.analysisError { Text(e).foregroundStyle(Theme.bad).font(.footnote) }
                    if song.sourceType == .importedFile {
                        if song.userConfirmedRights {
                            Button { model.analyze(songId: songId) } label: { Label("Analyse song", systemImage: "waveform.badge.magnifyingglass") }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Text("Confirm you own or are authorised to process this audio before analysing.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("I confirm") { var s = song; s.userConfirmedRights = true; model.update(s) }
                        }
                    } else {
                        Text("No audio. Add sections manually below.").foregroundStyle(.secondary)
                    }
                }
            case .completed:
                VStack(alignment: .leading, spacing: 10) {
                    tempoRow(song)
                    keyRow(song)
                    if !song.chordEvents.isEmpty {
                        let preview = song.chordEvents.filter { $0.symbol != "N" }.prefix(12).map(\.symbol).joined(separator: "  ")
                        HStack(alignment: .top) {
                            Text("Chords").foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                            Text(preview).font(.callout.monospaced()).lineLimit(2)
                        }
                    }
                    DisclosureGroup("What this analysis can't do yet", isExpanded: $showLimitations) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(SongAnalyzer.limitations, id: \.self) { Text("• " + $0).font(.caption) }
                        }
                    }
                    .font(.footnote)
                    Button("Re-analyse") { model.analyze(songId: songId) }.font(.caption)
                }
            }
        }
    }

    private func tempoRow(_ song: Song) -> some View {
        HStack {
            Text("Tempo").foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            if let bpm = song.bpm {
                Text("\(bpm.value, specifier: "%.1f") BPM").font(.body.monospacedDigit())
                ConfidenceBadge(confidence: bpm.confidence, provenance: bpm.provenance)
                Spacer()
                Button("÷2") { setBPM(song, bpm.value / 2) }.buttonStyle(.bordered).controlSize(.small)
                Button("×2") { setBPM(song, bpm.value * 2) }.buttonStyle(.bordered).controlSize(.small)
                Stepper("", value: Binding(get: { bpm.value.rounded() }, set: { setBPM(song, $0) }), in: 30...260)
                    .labelsHidden()
            } else {
                Text("Not detected").foregroundStyle(.secondary)
            }
        }
    }

    private func setBPM(_ song: Song, _ value: Double) {
        var s = song
        s.bpm = .user((value * 10).rounded() / 10)
        model.update(s)
    }

    private func keyRow(_ song: Song) -> some View {
        HStack {
            Text("Key").foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Menu {
                ForEach(0..<12, id: \.self) { tonic in
                    ForEach([MusicalKey.Mode.major, .minor], id: \.self) { mode in
                        let k = MusicalKey(tonic: tonic, mode: mode)
                        Button(k.displayName) { var s = song; s.key = .user(k); model.update(s) }
                    }
                }
            } label: {
                Text(song.key?.value.displayName ?? "Set key")
            }
            if let key = song.key { ConfidenceBadge(confidence: key.confidence, provenance: key.provenance) }
            Spacer()
        }
    }

    // MARK: Timeline

    private func timelineCard(_ song: Song) -> some View {
        Card(title: "Structure") {
            VStack(alignment: .leading, spacing: 10) {
                SectionTimeline(song: song, selected: $selectedSection)
                if song.sections.isEmpty {
                    Text("No sections yet. Analyse the song or add sections manually.").font(.footnote).foregroundStyle(.secondary)
                }
                if model.audioURL(for: song) != nil {
                    HStack {
                        Toggle("Loop section", isOn: $loop).toggleStyle(.button).controlSize(.small)
                        Spacer()
                        if model.isSectionPlaying {
                            Button { model.sectionPlayer.stop(); model.isSectionPlaying = false } label: { Label("Stop", systemImage: "stop.fill") }
                        }
                    }
                }
            }
        }
    }

    // MARK: Sections

    private func sectionsCard(_ song: Song) -> some View {
        Card(title: "Sections & tones") {
            VStack(spacing: 8) {
                ForEach(song.orderedSections) { section in
                    SectionRow(song: song, section: section, isSelected: selectedSection == section.id,
                               isActive: model.activeSectionId == section.id,
                               onPlay: { play(song, section) },
                               onActivate: { activate(song, section) },
                               onEdit: { editingSection = section })
                        .onTapGesture { selectedSection = section.id }
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

    private func activate(_ song: Song, _ section: SongSection) {
        model.activate(song.arrangement(for: section), songId: song.id, sectionId: section.id)
    }

    private func play(_ song: Song, _ section: SongSection) {
        guard let url = model.audioURL(for: song) else { return }
        do {
            try model.sectionPlayer.load(url: url)
            model.sectionPlayer.play(from: section.startTime, to: section.endTime, loop: loop)
            model.isSectionPlaying = true
            activate(song, section)
        } catch {
            model.engineError = "Playback failed: \(error.localizedDescription)"
        }
    }

    // MARK: Arrangements

    private func arrangementsCard(_ song: Song) -> some View {
        Card(title: "Tones for this song") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(song.arrangements) { a in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(a.name).font(.headline)
                            Text(a.layers.compactMap { model.library.patch(id: $0.patchId)?.name }.joined(separator: " + "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { model.activate(a, songId: song.id) } label: {
                            Image(systemName: model.activeArrangement?.id == a.id ? "speaker.wave.2.fill" : "speaker.wave.2")
                        }
                        Button { editingArrangement = a } label: { Image(systemName: "slider.horizontal.3") }
                    }
                    .buttonStyle(.borderless)
                }
                Button {
                    var s = song
                    let a = Arrangement(name: "Tone \(song.arrangements.count + 1)",
                                        layers: [Layer(patchId: FactoryPatches.id(forProgram: 0))])
                    s.arrangements.append(a)
                    model.update(s)
                    editingArrangement = a
                } label: { Label("New tone", systemImage: "plus") }
            }
        }
    }
}

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

struct SectionRow: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let section: SongSection
    let isSelected: Bool
    let isActive: Bool
    let onPlay: () -> Void
    let onActivate: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3).fill(SectionTimeline.color(for: section)).frame(width: 6, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(section.label).font(.headline)
                        if section.provenance != .user {
                            ConfidenceBadge(confidence: section.confidence, provenance: section.provenance)
                        }
                    }
                    Text("\(section.startTime.mmss) – \(section.endTime.mmss)")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Spacer()
                if model.audioURL(for: song) != nil {
                    Button(action: onPlay) { Image(systemName: "play.circle") }.accessibilityLabel("Play section")
                }
                Button(action: onActivate) {
                    Image(systemName: isActive ? "pianokeys.inverse" : "pianokeys")
                        .foregroundStyle(isActive ? Theme.accent : .primary)
                }
                .accessibilityLabel("Use this section's tone on the keyboard")
                Button(action: onEdit) { Image(systemName: "ellipsis.circle") }.accessibilityLabel("Edit section")
            }
            .buttonStyle(.borderless)
            .font(.title3)

            HStack {
                Text("Tone").font(.caption).foregroundStyle(.secondary)
                Menu(song.arrangement(for: section)?.name ?? "None") {
                    Button("None") { assign(nil) }
                    ForEach(song.arrangements) { a in Button(a.name) { assign(a.id) } }
                }
                .font(.caption)
            }

            if isSelected {
                let suggestions = song.toneSuggestions.filter { $0.sectionId == section.id }
                if !suggestions.isEmpty { SuggestionList(song: song, section: section, suggestions: suggestions) }
            }
        }
        .padding(10)
        .background(isSelected ? Theme.panelRaised : Color.clear, in: RoundedRectangle(cornerRadius: 10))
    }

    private func assign(_ id: UUID?) {
        var s = song
        guard let i = s.sections.firstIndex(where: { $0.id == section.id }) else { return }
        s.sections[i].arrangementId = id
        model.update(s)
        if isActive { model.activate(s.arrangement(for: s.sections[i]), songId: s.id, sectionId: section.id) }
    }
}

/// Feature-based suggestions with an explicit "not instrument recognition" label.
struct SuggestionList: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    let section: SongSection
    let suggestions: [ToneSuggestion]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested from sound character (brightness, attack, sustain) — not instrument recognition yet.")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(suggestions) { s in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(model.library.patch(id: s.patchId)?.name ?? s.family.displayName).font(.subheadline.weight(.semibold))
                            ConfidenceBadge(confidence: s.confidence, provenance: .algorithm)
                        }
                        Text(s.reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Add layer") { addLayer(s.patchId) }.font(.caption).buttonStyle(.bordered)
                }
            }
        }
    }

    /// Adds the suggested patch as a new layer to this section's tone (creating one if needed).
    private func addLayer(_ patchId: UUID) {
        var s = song
        guard let si = s.sections.firstIndex(where: { $0.id == section.id }) else { return }
        let layer = Layer(patchId: patchId, volume: 0.6)
        if let aid = s.sections[si].arrangementId, let ai = s.arrangements.firstIndex(where: { $0.id == aid }) {
            guard s.arrangements[ai].layers.count < SoundEngine.maxLayers else { return }
            s.arrangements[ai].layers.append(layer)
        } else {
            let a = Arrangement(name: "\(section.label) tone", layers: [layer])
            s.arrangements.append(a)
            s.sections[si].arrangementId = a.id
        }
        model.update(s)
        model.activate(s.arrangement(for: s.sections[si]), songId: s.id, sectionId: section.id)
    }
}

/// Rename, retype, resize, split, merge or delete a section.
struct SectionEditorSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let songId: UUID
    @State var section: SongSection
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Section") {
                    TextField("Label", text: $section.label)
                    Picker("Type", selection: $section.type) {
                        ForEach(SectionType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section("Timing") {
                    Stepper("Start \(section.startTime.mmss).\(tenths(section.startTime))", value: $section.startTime, in: 0...max(0, section.endTime - 0.5), step: 0.5)
                    Stepper("End \(section.endTime.mmss).\(tenths(section.endTime))", value: $section.endTime, in: (section.startTime + 0.5)...max(section.startTime + 0.5, duration ?? 3600), step: 0.5)
                    Button("Snap to nearest beats") { snap() }.disabled(model.song(songId)?.beatTimes.isEmpty ?? true)
                }
                Section("Notes") {
                    TextField("e.g. play octave higher in 2nd interlude", text: Binding(get: { section.notes ?? "" }, set: { section.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
                }
                Section {
                    Button("Split in the middle") { mutate { try SectionEditor.split($0, id: section.id, at: (section.startTime + section.endTime) / 2) } }
                    Button("Merge with next section") { mergeNext() }
                    Button("Delete section", role: .destructive) {
                        mutate { list in list.filter { $0.id != section.id } }
                    }
                }
                if let error { Text(error).foregroundStyle(Theme.bad) }
            }
            .navigationTitle("Edit section")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
    }

    private var duration: Double? { model.song(songId)?.duration }

    private func tenths(_ t: Double) -> Int { Int((t * 10).rounded()) % 10 }

    private func snap() {
        guard let beats = model.song(songId)?.beatTimes, !beats.isEmpty else { return }
        func nearest(_ t: Double) -> Double { beats.min { abs($0 - t) < abs($1 - t) } ?? t }
        section.startTime = nearest(section.startTime)
        section.endTime = max(section.startTime + 0.5, nearest(section.endTime))
    }

    private func save() {
        guard var song = model.song(songId) else { return }
        do {
            var list = try SectionEditor.resize(song.sections, id: section.id, start: section.startTime,
                                                end: section.endTime, songDuration: song.duration)
            if let i = list.firstIndex(where: { $0.id == section.id }) {
                list[i].label = section.label
                list[i].type = section.type
                list[i].notes = section.notes
                list[i].provenance = .user
                list[i].confidence = 1
            }
            song.sections = list
            model.update(song)
            dismiss()
        } catch {
            self.error = "Sections can't overlap or be shorter than half a second."
        }
    }

    private func mergeNext() {
        guard let song = model.song(songId) else { return }
        let ordered = song.orderedSections
        guard let i = ordered.firstIndex(where: { $0.id == section.id }), i + 1 < ordered.count else {
            error = "This is the last section."; return
        }
        mutate { try SectionEditor.merge($0, section.id, ordered[i + 1].id) }
    }

    private func mutate(_ op: ([SongSection]) throws -> [SongSection]) {
        guard var song = model.song(songId) else { return }
        do {
            song.sections = try op(song.sections)
            model.update(song)
            dismiss()
        } catch {
            self.error = "That edit isn't possible here (\(error))."
        }
    }
}

/// Analyse tab: songs and their analysis state.
struct AnalyseHomeView: View {
    @EnvironmentObject var model: AppModel
    @State private var showImport = false

    var body: some View {
        List {
            Section {
                Button { showImport = true } label: { Label("Import an MP3 to analyse", systemImage: "square.and.arrow.down") }
            } footer: {
                Text("Analysis runs on this iPhone: tempo & beats, key, chords, section boundaries and repeated parts, plus tone suggestions.")
            }
            Section("Songs") {
                ForEach(model.library.songs.filter { $0.sourceType == .importedFile }) { song in
                    NavigationLink(value: song.id) {
                        HStack {
                            Text(song.title)
                            Spacer()
                            switch song.analysisStatus {
                            case .running: ProgressView(value: model.analysisProgress[song.id] ?? 0).frame(width: 60)
                            case .completed: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.bad)
                            default: Text("Not analysed").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Analyse")
        .navigationDestination(for: UUID.self) { SongDetailView(songId: $0) }
        .sheet(isPresented: $showImport) { ImportSongView().environmentObject(model) }
    }
}
