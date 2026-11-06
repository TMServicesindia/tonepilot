import SwiftUI
import TonePilotCore

/// Song Arpeggio, step 1: the broken-chord pattern TonePilot learned for each section, a preview
/// on the song's own chords (its own clock — works with the song paused), and tap-to-correct.
struct SongArpeggioCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            stateLine
            if let arp = song.arpeggio, !model.arpeggioSections(song).isEmpty {
                learned(arp)
            } else {
                notLearned
            }
            if let arp = song.arpeggio { skippedSections(arp) }
        }
        .dsSurface()
        .onDisappear { if model.arpeggioPreview?.songId == song.id { model.stopArpeggioPreview() } }
    }

    // MARK: State (spec §2.11: one clear line)

    /// "Waiting for your chord" / "Playing the fill" / "Live fill-in is off". Fixed height, so nothing moves.
    private var stateLine: some View {
        let live = song.arpeggio?.liveFill == true && !model.arpeggioSections(song).isEmpty
        let chord = model.arpeggioLiveChord
        let previewing = model.arpeggioPreview?.songId == song.id
        let (title, detail, symbol, on): (String, String, String, Bool) = {
            if previewing { return ("Playing the preview", "On the song's own chords", "play.circle.fill", true) }
            if live, let chord { return ("Playing the fill", "Following \(chord)", "waveform", true) }
            if live { return ("Waiting for your chord", "Play the root with your left hand", "hand.raised", false) }
            return ("Live fill-in is off", "Preview it, or turn it on below", "pause.circle", false)
        }()
        return HStack(spacing: DS.Space.m) {
            Image(systemName: symbol).font(DS.Text.screenTitle)
                .foregroundStyle(on ? DS.Palette.accent : DS.Palette.textSecondary)
                .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
                .background(on ? DS.Palette.accentMuted : DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title).font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                Text(detail).font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("arpeggio.state")
    }

    // MARK: No fill unless sure

    /// Sections the song doesn't play broken chords in: no fill was made; you can add one anyway.
    @ViewBuilder private func skippedSections(_ arp: SongArpeggio) -> some View {
        let skipped = song.orderedSections.filter { arp.skipped?[$0.id.uuidString] != nil && arp.playable(for: $0.id) == nil }
        // Repeats share one row.
        let rows = skipped.filter { s in !skipped.contains { $0.id != s.id && $0.repetitionGroup != nil && $0.repetitionGroup == s.repetitionGroup && $0.type == s.type && $0.startTime < s.startTime } }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No fill in these sections").font(DS.Text.label).foregroundStyle(DS.Palette.textPrimary)
                ForEach(rows) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.label).font(DS.Text.bodySecondary).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                            Text(Self.heard(arp.skipped?[s.id.uuidString])).font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                        }
                        Spacer()
                        Button("Add a fill anyway") {
                            model.setArpeggioStyle(ArpeggioStyles.all.first?.id, songId: song.id, sectionId: s.id)
                            model.selectArpeggioSection(s.id, songId: song.id)
                        }
                        .font(DS.Text.caption.weight(.semibold)).buttonStyle(.bordered).tint(DS.Palette.accent)
                        .frame(minHeight: DS.Size.touchTarget)
                        .accessibilityIdentifier("arpeggio.addFill")
                    }
                }
            }
            .padding(DS.Space.m)
            .background(DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            .accessibilityIdentifier("arpeggio.skipped")
        }
    }

    static func heard(_ kind: String?) -> String {
        switch AccompanimentClassifier.Kind(rawValue: kind ?? "") {
        case .blockChords: return "The song plays block chords here"
        case .melodic: return "The song plays a melody here, not chords"
        case .some(.none): return "Too quiet or too short to tell"
        default: return "Not sure enough to fill"
        }
    }

    // MARK: Not learned yet

    @ViewBuilder private var notLearned: some View {
        let separated = !model.stemKinds(for: song).isEmpty
        Text("TonePilot learns each section's broken-chord pattern from the song's Music part.")
            .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
        if model.separationProgress[song.id] != nil || song.analysisStatus == .running {
            Label("Learning starts when the analysis finishes.", systemImage: "hourglass")
                .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
        } else if !separated {
            Button { model.separateStems(song.id) } label: { Label("Separate the parts first", systemImage: "scissors") }
                .buttonStyle(.dsPrimary)
                .disabled(!model.canSeparate || model.audioURL(for: song) == nil)
        } else {
            Button { model.analyze(songId: song.id, useServer: model.serverSettings.enabled) } label: {
                Label("Learn the patterns", systemImage: "sparkles")
            }
            .buttonStyle(.dsPrimary)
            Text("Your tones and corrections are kept.")
                .font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
        }
    }

    // MARK: Learned

    @ViewBuilder private func learned(_ arp: SongArpeggio) -> some View {
        let sections = model.arpeggioSections(song)
        let current = model.arpeggioSection(song) ?? sections[0]
        let style = arp.style(for: current.id)!
        let suggested = arp.pattern(for: current.id).map(ArpeggioStyles.suggested(for:))
        let pattern = arp.playable(for: current.id)!
        let previewing = model.arpeggioPreview == ArpeggioPreview(songId: song.id, sectionId: current.id)
        let live = arp.liveFill == true

        // 1. Live fill-in
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { live }, set: { model.setArpeggioLive($0, songId: song.id) })) {
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Live fill-in").font(DS.Text.section).foregroundStyle(DS.Palette.textPrimary)
                    Text("Start each bar with your chord. TonePilot plays the rest.")
                        .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
                }
            }
            .tint(DS.Palette.accent)
            .accessibilityIdentifier("arpeggio.live")
            if live, UITestSeed.enabled {
                // Speed & crash tests only: key presses through the real MIDI path.
                Button("Test: play R · 5 · 8") { model.uiTestPlayChordHand() }
                    .font(DS.Text.caption).accessibilityIdentifier("arpeggio.testKeys")
            }
            if live {
                HStack(spacing: 8) {
                    yourPart(pattern)
                    Spacer(minLength: 0)
                    Text(model.arpeggioLiveChord.map { "Heard: \($0)" } ?? "Play your root…")
                        .font(DS.Text.label).foregroundStyle(DS.Palette.accent).lineLimit(1)
                }
                Stepper(value: Binding(get: { arp.effectiveSplit }, set: { model.setArpeggioSplit($0, songId: song.id) }), in: 40...84) {
                    Text("Chord hand: below \(NoteName.name(for: arp.effectiveSplit))").font(DS.Text.bodySecondary)
                }
                Text("Play R · 5 and TonePilot continues above your hand. A full chord stops the fill.")
                    .font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                chordMemory(arp)
            }
        }
        .padding(DS.Space.m)
        .background(DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))

        // 2. Section
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Space.s) {
                ForEach(sections) { s in
                    let on = s.id == current.id
                    Button { model.selectArpeggioSection(s.id, songId: song.id) } label: {
                        Text(s.label).font(DS.Text.label).lineLimit(1)
                            .padding(.horizontal, DS.Space.m).frame(minHeight: DS.Size.touchTarget)
                            .background(on ? DS.Palette.accent : DS.Palette.elevated, in: Capsule())
                            .foregroundStyle(on ? DS.Palette.onAccent : DS.Palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }

        // 3. Pattern (a basic style, adjusted to the song)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(style.name).font(DS.Text.screenTitle).foregroundStyle(DS.Palette.textPrimary)
                Text(style.shape).font(DS.Text.bodySecondary.monospaced()).foregroundStyle(DS.Palette.accent)
                Text(style.id == suggested?.id ? "Learned from \(current.label) · \(style.meterName) · \(Int(arp.effectiveBPM.rounded())) BPM"
                                               : "Your choice · \(style.meterName) · \(Int(arp.effectiveBPM.rounded())) BPM")
                    .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
            }
            Spacer()
            Menu {
                let triplet = suggested.map { $0.stepsPerBeat == 3 } ?? false
                let beats = suggested?.beatsPerBar ?? 4
                Section("Fits this song (\(suggested?.meterName ?? "4/4"))") {
                    ForEach(ArpeggioStyles.styles(beatsPerBar: beats, triplet: triplet)) { s in styleButton(s, current: style, section: current.id) }
                }
                Section("Other feels") {
                    ForEach(ArpeggioStyles.all.filter { s in !ArpeggioStyles.styles(beatsPerBar: beats, triplet: triplet).contains(s) }) { s in
                        styleButton(s, current: style, section: current.id)
                    }
                }
                if style.id != suggested?.id {
                    Button { model.setArpeggioStyle(nil, songId: song.id, sectionId: current.id) } label: { Label("Back to the suggestion", systemImage: "arrow.uturn.backward") }
                }
            } label: {
                Label("Change", systemImage: "slider.horizontal.3").font(DS.Text.label)
                    .padding(.horizontal, DS.Space.m).frame(minHeight: DS.Size.touchTarget)
                    .background(DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
            }
            .accessibilityIdentifier("arpeggio.style")
        }
        PatternGrid(pattern: pattern, yours: live ? 2 : 0)

        // 4. Preview and sound
        HStack(spacing: DS.Space.m) {
            let preview = Button {
                if previewing { model.stopArpeggioPreview() } else { model.startArpeggioPreview(songId: song.id, sectionId: current.id) }
            } label: {
                Label(previewing ? "Stop preview" : "Preview", systemImage: previewing ? "stop.fill" : "play.fill")
                    .labelStyle(.titleAndIcon)
            }
            .accessibilityIdentifier("arpeggio.preview")
            // Preview is the one primary while live fill-in is off (spec §2.11).
            if live { preview.buttonStyle(.dsSecondary) } else { preview.buttonStyle(.dsPrimary) }
            Menu {
                Button { model.setArpeggioSound(nil, songId: song.id) } label: {
                    if arp.soundId == nil { Label("Same as my keys", systemImage: "checkmark") } else { Text("Same as my keys") }
                }
                Divider()
                ForEach(SongArpeggio.suggestedSounds, id: \.self) { id in
                    if let p = model.library.patch(id: id) {
                        Button { model.setArpeggioSound(id, songId: song.id) } label: {
                            if arp.soundId == id { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                        }
                    }
                }
            } label: {
                Label(arp.soundId.flatMap { model.library.patch(id: $0)?.name } ?? "My keys' tone", systemImage: "music.note")
                    .labelStyle(.titleAndIcon)
                    .font(DS.Text.bodySecondary).lineLimit(1).frame(minHeight: DS.Size.primaryButton).padding(.horizontal, DS.Space.m)
                    .background(DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
            }
            .accessibilityIdentifier("arpeggio.sound")
        }
        Text("Preview plays on the song's own chords. The song can stay paused.")
            .font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
        LabeledSlider(title: "Fill volume", value: arp.effectiveVolume, range: 0...1, format: { "\(Int(($0 * 100).rounded()))" }) {
            model.setArpeggioVolume($0, songId: song.id)
        }
        LabeledSlider(title: "Tempo", value: arp.tempoScale ?? 1, range: 0.5...1.25, format: { "\(Int((arp.bpm * $0).rounded())) BPM" }) {
            model.setArpeggioTempo($0, songId: song.id)
        }
    }

    /// The chords you taught TonePilot by playing their 3rd (or a full chord): they beat the analysis.
    @ViewBuilder private func chordMemory(_ arp: SongArpeggio) -> some View {
        let learned = arp.memory.sorted { $0.key < $1.key }
        HStack(spacing: 6) {
            Text("Your chords:").font(DS.Text.caption.weight(.semibold))
            if learned.isEmpty {
                Text("Play a chord once and TonePilot remembers it").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
            } else {
                ForEach(learned, id: \.key) { pc, q in DSChip(text: NoteName.sharpNames[pc] + (q == .minor ? "m" : ""), tone: .accent) }
                Spacer(minLength: DS.Space.xs)
                Button("Reset") { model.resetChordMemory(songId: song.id) }.font(DS.Text.caption.weight(.semibold))
                    .accessibilityIdentifier("arpeggio.resetChords")
            }
        }
    }

    private func styleButton(_ s: ArpeggioStyle, current: ArpeggioStyle, section: UUID) -> some View {
        Button { model.setArpeggioStyle(s.id, songId: song.id, sectionId: section) } label: {
            if s.id == current.id { Label("\(s.name)  \(s.shape)", systemImage: "checkmark") } else { Text("\(s.name)  \(s.shape)") }
        }
    }

    /// "You: R · 5 · 8 → TonePilot: 10 · 12 · 10 · 8 · 5"
    private func yourPart(_ p: ArpeggioPattern) -> some View {
        let hits = p.hits.sorted { $0.step < $1.step }
        let k = min(hits.count, 2)
        let you = hits.prefix(k).map { ArpeggioStyle.number($0.degree) }.joined(separator: "·")
        let ai = hits.dropFirst(k).map { ArpeggioStyle.number($0.degree) }.joined(separator: "·")
        return Text("You **\(you)** → TonePilot **\(ai.isEmpty ? "—" : ai)**").font(DS.Text.caption.monospaced())
    }
}

/// One bar of the pattern: a cell per step, grouped by beat, labelled with its chord position.
/// With live fill-in, the steps you play are outlined; the rest are TonePilot's.
struct PatternGrid: View {
    let pattern: ArpeggioPattern
    var yours = 0

    var body: some View {
        let sorted = pattern.hits.sorted { $0.step < $1.step }
        let yourSteps = Set(sorted.prefix(yours).map(\.step))
        let hits = Dictionary(sorted.map { ($0.step, $0) }, uniquingKeysWith: { a, _ in a })
        HStack(spacing: DS.Space.s) {
            ForEach(0..<pattern.beatsPerBar, id: \.self) { beat in
                HStack(spacing: DS.Space.xxs) {
                    ForEach(0..<pattern.stepsPerBeat, id: \.self) { sub in
                        let step = beat * pattern.stepsPerBeat + sub
                        let hit = hits[step]
                        Text(hit.map { ArpeggioStyle.number($0.degree) } ?? "·")
                            .font(DS.Text.label.monospacedDigit())
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, minHeight: DS.Size.primaryButton)
                            .background(hit == nil ? DS.Palette.elevated : DS.Palette.accent.opacity(0.35 + 0.6 * (hit?.velocity ?? 0)),
                                        in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous)
                                .stroke(yourSteps.contains(step) ? DS.Palette.textPrimary : .clear, lineWidth: 2))
                            .foregroundStyle(hit == nil ? DS.Palette.textSecondary : DS.Palette.onAccent)
                            .accessibilityLabel("Step \(step + 1): \(hit?.degree.label ?? "rest")\(yourSteps.contains(step) ? ", you play" : "")")
                    }
                }
            }
        }
    }
}

/// Slider with a title and value; commits when the drag ends.
struct LabeledSlider: View {
    let title: String
    let value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    let onCommit: (Double) -> Void
    @State private var current: Double = 0
    @State private var editing = false

    var body: some View {
        HStack(spacing: DS.Space.m) {
            Text(title).font(DS.Text.bodySecondary).foregroundStyle(DS.Palette.textSecondary).frame(minWidth: 84, alignment: .leading)
            Slider(value: $current, in: range) { e in
                editing = e
                if !e { onCommit(current) }
            }
            .tint(DS.Palette.accent)
            .accessibilityLabel(title)
            Text(format(current)).font(DS.Text.metadata.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary).frame(minWidth: 64, alignment: .trailing)
        }
        .onAppear { current = value }
        .onChange(of: value) { _, v in if !editing { current = v } }
    }
}
