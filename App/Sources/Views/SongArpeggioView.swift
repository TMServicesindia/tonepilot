import SwiftUI
import TonePilotCore

/// Song Arpeggio, step 1: the broken-chord pattern TonePilot learned for each section, a preview
/// on the song's own chords (its own clock — works with the song paused), and tap-to-correct.
struct SongArpeggioCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Song Arpeggio", systemImage: "pianokeys.inverse").font(.headline)
                Spacer()
                Text("Live").font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.18), in: Capsule()).foregroundStyle(Theme.accent)
            }
            if let arp = song.arpeggio, !model.arpeggioSections(song).isEmpty {
                learned(arp)
            } else {
                notLearned
            }
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .onDisappear { if model.arpeggioPreview?.songId == song.id { model.stopArpeggioPreview() } }
    }

    // MARK: Not learned yet

    @ViewBuilder private var notLearned: some View {
        let separated = !model.stemKinds(for: song).isEmpty
        Text("TonePilot learns each section's broken-chord pattern — its rhythm, accents and chord positions — from the song's separated **Music** part. Then you can preview it on the song's own chords.")
            .font(.footnote).foregroundStyle(.secondary)
        if model.separationProgress[song.id] != nil || song.analysisStatus == .running {
            Label("Learning starts when the separation and analysis finish.", systemImage: "hourglass").font(.caption)
        } else if !separated {
            Button { model.separateStems(song.id) } label: { Label("Separate the parts first", systemImage: "scissors") }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSeparate || model.audioURL(for: song) == nil)
        } else {
            Button { model.analyze(songId: song.id, useServer: model.serverSettings.enabled) } label: {
                Label("Learn the patterns", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            Text("Re-analyses the song from its separated parts (your tones and corrections are kept).")
                .font(.caption2).foregroundStyle(.secondary)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live fill-in").font(.headline)
                    Text("Start each bar with your broken chord — TonePilot plays the rest, in your tone.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .tint(Theme.accent)
            .accessibilityIdentifier("arpeggio.live")
            if live {
                HStack(spacing: 8) {
                    yourPart(pattern)
                    Spacer(minLength: 0)
                    Text(model.arpeggioLiveChord.map { "Heard: \($0)" } ?? "Play your root…")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent).lineLimit(1)
                }
                Stepper(value: Binding(get: { arp.effectiveSplit }, set: { model.setArpeggioSplit($0, songId: song.id) }), in: 40...84) {
                    Text("Chord hand: below \(NoteName.name(for: arp.effectiveSplit))").font(.subheadline)
                }
                Text("Works with the song paused (it uses the song's tempo) or playing. Your octave note counts as chord hand too.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 12))

        // 2. Section
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sections) { s in
                    let on = s.id == current.id
                    Button { model.selectArpeggioSection(s.id, songId: song.id) } label: {
                        Text(s.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                            .padding(.horizontal, 12).frame(minHeight: 40)
                            .background(on ? Theme.accent : Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(on ? .black : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        // 3. Pattern (a basic style, adjusted to the song)
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(style.name).font(.title3.weight(.bold))
                Text(style.shape).font(.subheadline.monospaced()).foregroundStyle(Theme.accent)
                Text(style.id == suggested?.id ? "Suggested from the song · \(style.meterName) · \(Int(arp.effectiveBPM.rounded())) BPM"
                                               : "Your choice · \(style.meterName) · \(Int(arp.effectiveBPM.rounded())) BPM")
                    .font(.caption).foregroundStyle(.secondary)
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
                Label("Change", systemImage: "slider.horizontal.3").font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12).frame(minHeight: 40)
                    .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityIdentifier("arpeggio.style")
        }
        PatternGrid(pattern: pattern, yours: live ? model.arpeggioFollower?.yourNotes ?? 3 : 0)

        // 4. Preview and sound
        HStack(spacing: 12) {
            Button {
                if previewing { model.stopArpeggioPreview() } else { model.startArpeggioPreview(songId: song.id, sectionId: current.id) }
            } label: {
                Label(previewing ? "Stop preview" : "Preview", systemImage: previewing ? "stop.fill" : "play.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("arpeggio.preview")
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
                    .font(.subheadline).lineLimit(1).frame(minHeight: 48).padding(.horizontal, 10)
                    .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        Text("Preview plays this pattern on the song's own chords, on its own clock — the song can stay paused.")
            .font(.caption2).foregroundStyle(.secondary)
        LabeledSlider(title: "Fill volume", value: arp.effectiveVolume, range: 0...1, format: { "\(Int(($0 * 100).rounded()))" }) {
            model.setArpeggioVolume($0, songId: song.id)
        }
        LabeledSlider(title: "Tempo", value: arp.tempoScale ?? 1, range: 0.5...1.25, format: { "\(Int((arp.bpm * $0).rounded())) BPM" }) {
            model.setArpeggioTempo($0, songId: song.id)
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
        let k = min(hits.count, model.arpeggioFollower?.yourNotes ?? 3)
        let you = hits.prefix(k).map { ArpeggioStyle.number($0.degree) }.joined(separator: "·")
        let ai = hits.dropFirst(k).map { ArpeggioStyle.number($0.degree) }.joined(separator: "·")
        return Text("You **\(you)** → TonePilot **\(ai.isEmpty ? "—" : ai)**").font(.caption.monospaced())
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
        HStack(spacing: 6) {
            ForEach(0..<pattern.beatsPerBar, id: \.self) { beat in
                HStack(spacing: 2) {
                    ForEach(0..<pattern.stepsPerBeat, id: \.self) { sub in
                        let step = beat * pattern.stepsPerBeat + sub
                        let hit = hits[step]
                        Text(hit.map { ArpeggioStyle.number($0.degree) } ?? "·")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(hit == nil ? Theme.panelRaised : Theme.accent.opacity(0.35 + 0.6 * (hit?.velocity ?? 0)),
                                        in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(yourSteps.contains(step) ? Color.white : .clear, lineWidth: 2))
                            .foregroundStyle(hit == nil ? Color.secondary : .black)
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
        HStack(spacing: 10) {
            Text(title).font(.subheadline).frame(width: 92, alignment: .leading)
            Slider(value: $current, in: range) { e in
                editing = e
                if !e { onCommit(current) }
            }
            .tint(Theme.accent)
            Text(format(current)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
        }
        .onAppear { current = value }
        .onChange(of: value) { _, v in if !editing { current = v } }
    }
}
