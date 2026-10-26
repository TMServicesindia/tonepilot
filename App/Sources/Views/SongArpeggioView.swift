import SwiftUI
import TonePilotCore

/// Song Arpeggio, step 1: the broken-chord pattern TonePilot learned for each section, a preview
/// on the song's own chords (its own clock — works with the song paused), and tap-to-correct.
struct SongArpeggioCard: View {
    @EnvironmentObject var model: AppModel
    let song: Song
    @State private var sectionId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Song Arpeggio", systemImage: "pianokeys.inverse").font(.headline)
                Spacer()
                Text("Step 1 · Preview").font(.caption2.weight(.semibold))
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
        let current = sections.first { $0.id == (sectionId ?? defaultSection(sections)?.id) } ?? sections[0]
        let pattern = arp.pattern(for: current.id)!
        let previewing = model.arpeggioPreview == ArpeggioPreview(songId: song.id, sectionId: current.id)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(sections) { s in
                    let on = s.id == current.id
                    Button {
                        sectionId = s.id
                        if model.arpeggioPreview?.songId == song.id { model.startArpeggioPreview(songId: song.id, sectionId: s.id) }
                    } label: {
                        Text(s.label).font(.subheadline.weight(.semibold)).lineLimit(1)
                            .padding(.horizontal, 12).frame(minHeight: 40)
                            .background(on ? Theme.accent : Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(on ? .black : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        HStack(spacing: 8) {
            StatusPill(text: "\(Int(arp.effectiveBPM.rounded())) BPM", color: .secondary)
            StatusPill(text: pattern.meterName, color: .secondary)
            StatusPill(text: pattern.sustained ? "Held chords" : "\(pattern.hits.count) notes per bar", color: .secondary)
            Spacer(minLength: 0)
            confidence(pattern)
        }

        PatternGrid(pattern: pattern) { model.cycleArpeggioStep($0, songId: song.id, sectionId: current.id) }
        Text(pattern.sustained ? "This section holds long chords rather than broken chords." : pattern.summary)
            .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
        Text("Tap a step to change its chord position (Root → 3rd → 5th → Octave → higher…), or to add or remove a note.\(pattern.userEdited ? " Edited by you." : "")")
            .font(.caption2).foregroundStyle(.secondary)

        HStack(spacing: 12) {
            Button {
                if previewing { model.stopArpeggioPreview() } else { model.startArpeggioPreview(songId: song.id, sectionId: current.id) }
            } label: {
                Label(previewing ? "Stop preview" : "Preview", systemImage: previewing ? "stop.fill" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            Menu {
                ForEach(SongArpeggio.suggestedSounds, id: \.self) { id in
                    if let p = model.library.patch(id: id) {
                        Button { model.setArpeggioSound(id, songId: song.id) } label: {
                            if arp.effectiveSoundId == id { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                        }
                    }
                }
            } label: {
                Label(model.library.patch(id: arp.effectiveSoundId)?.name ?? "Sound", systemImage: "music.note")
                    .font(.subheadline).lineLimit(1).frame(minHeight: 48).padding(.horizontal, 10)
                    .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        Text("Plays the pattern on the song's own chords for this section, on its own clock — the song can stay paused.")
            .font(.caption2).foregroundStyle(.secondary)

        LabeledSlider(title: "Fill volume", value: arp.effectiveVolume, range: 0...1, format: { "\(Int(($0 * 100).rounded()))" }) {
            model.setArpeggioVolume($0, songId: song.id)
        }
        LabeledSlider(title: "Tempo", value: arp.tempoScale ?? 1, range: 0.5...1.25, format: { "\(Int((arp.bpm * $0).rounded())) BPM" }) {
            model.setArpeggioTempo($0, songId: song.id)
        }
    }

    private func defaultSection(_ sections: [SongSection]) -> SongSection? {
        sections.first { $0.type == .verse } ?? sections.first
    }

    @ViewBuilder private func confidence(_ p: ArpeggioPattern) -> some View {
        let c = p.confidence
        if p.userEdited {
            StatusPill(text: "Your version", color: Theme.good, symbol: "person.fill")
        } else if c >= 0.75 {
            StatusPill(text: "Matches the song \(Int(c * 100))%", color: Theme.good, symbol: "checkmark")
        } else if c >= 0.5 {
            StatusPill(text: "Likely \(Int(c * 100))%", color: Theme.warn, symbol: "questionmark")
        } else {
            StatusPill(text: "Unsure \(Int(c * 100))%", color: Theme.bad, symbol: "exclamationmark.triangle")
        }
    }
}

/// One bar of the pattern: a cell per step, grouped by beat, labelled with its chord position.
struct PatternGrid: View {
    let pattern: ArpeggioPattern
    let onTap: (Int) -> Void

    var body: some View {
        let hits = Dictionary(pattern.hits.map { ($0.step, $0) }, uniquingKeysWith: { a, _ in a })
        HStack(spacing: 6) {
            ForEach(0..<pattern.beatsPerBar, id: \.self) { beat in
                HStack(spacing: 2) {
                    ForEach(0..<pattern.stepsPerBeat, id: \.self) { sub in
                        let step = beat * pattern.stepsPerBeat + sub
                        let hit = hits[step]
                        Button { onTap(step) } label: {
                            Text(hit?.degree.short ?? "·")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(hit == nil ? Theme.panelRaised : Theme.accent.opacity(0.35 + 0.6 * (hit?.velocity ?? 0)),
                                            in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(hit == nil ? Color.secondary : .black)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Step \(step + 1): \(hit?.degree.label ?? "empty")")
                    }
                }
            }
        }
        .animation(nil, value: pattern)
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
