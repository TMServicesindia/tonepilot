import SwiftUI
import TonePilotCore

/// Live guidance at the current song position: left-hand Root → Fifth → Root for the current chord,
/// and the next right-hand melody notes (shifted to the keys the lead layer expects).
struct LiveGuideStrip: View {
    let song: Song
    let time: Double?
    /// Semitones the guide shifts melody notes so they land on the right-hand keys.
    let melodyOffset: Int

    private var transpose: Int { song.performanceTranspose ?? 0 }

    var body: some View {
        let steps = song.chordGuide ?? []
        let t = time ?? 0
        let current = ChordGuide.step(at: t, in: steps)
        let next = steps.first { $0.time > t }
        let melody = (song.melody?.notes ?? []).filter { $0.end > t }.prefix(6)
        let difficult = song.melody?.difficultPhrases.contains { $0.contains(t) } ?? false

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LEFT HAND").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    if let current {
                        Text(transposed(current).patternText).font(.system(size: 30, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text("\(transposed(current).chord) · \(transposed(current).patternNoteNames)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        Text(time == nil ? "Press play to follow" : "—").font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.6)
                        Text(" ").font(.caption.monospaced())
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("NEXT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(next.map { transposed($0).chord } ?? "—").font(.title3.weight(.semibold)).lineLimit(1)
                    Text(next.map { String(format: "in %.1f s", max(0, $0.time - t)) } ?? " ")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(width: 86, alignment: .trailing)
                .opacity(next == nil ? 0.4 : 1)
            }
            // Always takes its line, so the strip doesn't jump when a drone section starts or ends.
            Text("No clear chord here — play the Sa–Pa drone or follow the melody.").font(.caption2).foregroundStyle(Theme.warn)
                .lineLimit(1).minimumScaleFactor(0.7)
                .opacity(current?.isDrone == true ? 1 : 0)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("RIGHT HAND").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Label("Tricky phrase", systemImage: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Theme.warn)
                        .opacity(difficult ? 1 : 0)
                }
                if melody.isEmpty {
                    Text(song.melody == nil ? "No melody estimate for this song" : "—").font(.caption).foregroundStyle(.secondary)
                        .frame(height: 44, alignment: .leading)
                } else {
                    HStack(spacing: 6) {
                        ForEach(Array(melody.enumerated()), id: \.element.id) { i, n in
                            let key = n.midi + melodyOffset + transpose
                            VStack(spacing: 1) {
                                Text(NoteName.name(for: key)).font(i == 0 ? .headline.monospaced() : .caption.monospaced())
                                Text("〰︎").font(.caption2).foregroundStyle(Theme.accent).opacity(n.isOrnamented ? 1 : 0)
                            }
                            .frame(minWidth: 34, minHeight: 36)
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .background(i == 0 && n.start <= t ? Theme.accent.opacity(0.35) : Theme.panelRaised, in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
    }

    private func transposed(_ step: ChordGuideStep) -> ChordGuideStep {
        guard transpose != 0, let chord = ChordSymbol(step.chord) else {
            var s = step
            s.pattern = step.pattern.map { $0 + transpose }
            return s
        }
        var s = step
        s.chord = chord.transposed(transpose).name
        s.pattern = ChordGuide.pattern(root: chord.transposed(transpose).root)
        return s
    }
}

/// Full guide: correct chords and melody notes, choose Live Play vs Reference Learning.
struct MelodyChordGuideView: View {
    @EnvironmentObject var model: AppModel
    let songId: UUID

    private var song: Song? { model.song(songId) }

    var body: some View {
        if let song {
            List {
                modeSection(song)
                Section {
                    Stepper("Performance key: \(transposeLabel(song.performanceTranspose ?? 0))",
                            value: Binding(get: { song.performanceTranspose ?? 0 }, set: { model.setPerformanceTranspose(songId: songId, $0) }),
                            in: -12...12)
                    HStack {
                        Text("Melody octave")
                        Spacer()
                        Button("−12") { model.shiftMelody(songId: songId, by: -12) }.buttonStyle(.bordered)
                        Button("+12") { model.shiftMelody(songId: songId, by: 12) }.buttonStyle(.bordered)
                    }
                } footer: {
                    Text("Transposing changes the guides and generated accompaniment, not the original recording.")
                }
                chordSection(song)
                melodySection(song)
            }
            .navigationTitle("Melody & chords")
        } else {
            ContentUnavailableView("Song not found", systemImage: "questionmark")
        }
    }

    private func transposeLabel(_ t: Int) -> String {
        guard let key = song?.key?.value else { return t == 0 ? "original" : "\(t > 0 ? "+" : "")\(t)" }
        return "\(MusicalKey(tonic: key.tonic + t, mode: key.mode).displayName)\(t == 0 ? " (original)" : " (\(t > 0 ? "+" : "")\(t))")"
    }

    private func modeSection(_ song: Song) -> some View {
        let acc = song.accompaniment ?? AccompanimentSettings()
        return Section {
            Picker("Mode", selection: Binding(get: { acc.melodyGuide }, set: { on in
                var a = acc; a.melodyGuide = on
                model.ensurePerformance(songId: songId)
                model.updateAccompaniment(a)
            })) {
                Text("Live Play").tag(false)
                Text("Reference Learning").tag(true)
            }
            .pickerStyle(.segmented)
            if acc.melodyGuide {
                Picker("Guide sound", selection: Binding(get: { acc.guidePatchId }, set: { id in
                    var a = acc; a.guidePatchId = id; model.updateAccompaniment(a)
                })) {
                    Text("Same as the lead tone").tag(UUID?.none)
                    ForEach(model.library.patches.filter { [.flute, .strings, .synthLead, .piano, .bell, .ethnic].contains($0.family) }) { p in
                        Text(p.name).tag(UUID?.some(p.id))
                    }
                }
                HStack { Text("Guide volume"); Slider(value: Binding(get: { acc.guideLevel }, set: { var a = acc; a.guideLevel = $0; model.updateAccompaniment(a) }), in: 0...1) }
                if model.audioURL(for: song) != nil {
                    Button { model.openStudio(songId); model.cursor = 0; if !model.isStudioPlaying { model.studioTogglePlay() } } label: { Label("Play with guide from the start", systemImage: "play.fill") }
                }
            }
        } header: { Text("Melody") } footer: {
            Text(acc.melodyGuide
                 ? "Reference Learning: TonePilot plays the estimated melody so you can learn it, then play along on your Casio."
                 : "Live Play: you play the melody on the Casio's right-hand keys with the section's lead tone. The guide shows which keys to press.")
        }
    }

    private func chordSection(_ song: Song) -> some View {
        Section {
            if (song.chordGuide ?? []).isEmpty { Text("No chords yet — analyse the song first.").foregroundStyle(.secondary) }
            ForEach(song.chordGuide ?? []) { step in
                HStack {
                    Text(step.time.mmss).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                    Menu {
                        if !step.alternatives.isEmpty {
                            Section("Likely alternatives") { ForEach(step.alternatives, id: \.self) { alt in Button(alt) { model.correctChord(songId: songId, stepId: step.id, to: alt) } } }
                        }
                        Section("All chords") {
                            ForEach(NoteName.sharpNames, id: \.self) { root in
                                Menu(root) {
                                    Button(root) { model.correctChord(songId: songId, stepId: step.id, to: root) }
                                    Button(root + "m") { model.correctChord(songId: songId, stepId: step.id, to: root + "m") }
                                }
                            }
                        }
                    } label: {
                        Text(step.chord).font(.headline).frame(minWidth: 60, alignment: .leading)
                    }
                    Text(step.patternText).font(.subheadline.monospaced())
                    Spacer()
                    if step.userEdited { Image(systemName: "checkmark.seal").foregroundStyle(Theme.good) }
                    else { ConfidenceBadge(confidence: step.confidence, provenance: .algorithm) }
                }
            }
        } header: { Text("Left hand · Root → Fifth → Root") } footer: {
            Text("Tap a chord to correct it. Where no clear chord was found, the guide suggests a tonic drone (Sa–Pa) instead of forcing one.")
        }
    }

    private func melodySection(_ song: Song) -> some View {
        let offset = AutoArranger.guideOffset(for: model.activeSongId == songId ? model.activeArrangement : song.arrangements.first { $0.origin == .myVersion })
        return Section {
            if let melody = song.melody {
                Text(melody.source == .vocalStem ? "Transcribed from the separated vocals." : "Predominant line of the full mix — may follow an instrument where nobody sings.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(song.orderedSections) { section in
                    let notes = melody.notes(in: section.startTime, section.endTime).filter { $0.start >= section.startTime }
                    if !notes.isEmpty {
                        DisclosureGroup("\(section.label) · \(notes.count) notes") {
                            ForEach(notes) { n in noteRow(n, offset: offset, difficult: melody.difficultPhrases.contains { $0.contains(n.start) }) }
                        }
                    }
                }
            } else {
                Text("No melody estimate yet.").foregroundStyle(.secondary)
            }
        } header: { Text("Right hand · melody") } footer: {
            Text("〰︎ marks slides, vibrato or gamaka-like movement kept from the recording. Notes are shown on the keys to press\(offset != 0 ? " (shifted \(offset > 0 ? "up" : "down") an octave to match the lead tone)" : "").")
        }
    }

    private func noteRow(_ n: MelodyNote, offset: Int, difficult: Bool) -> some View {
        HStack {
            Text(n.start.mmss).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            Text(NoteName.name(for: n.midi + offset + (song?.performanceTranspose ?? 0))).font(.body.monospaced().weight(.semibold)).frame(width: 48, alignment: .leading)
            Text("\(n.duration, specifier: "%.2f") s").font(.caption).foregroundStyle(.secondary)
            if n.isOrnamented { Text("〰︎").foregroundStyle(Theme.accent) }
            if difficult { Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.warn) }
            if n.confidence < 0.4 { Image(systemName: "questionmark.circle").font(.caption).foregroundStyle(Theme.warn) }
            Spacer()
            Button { model.editMelodyNote(songId: songId, noteId: n.id, semitones: -1) } label: { Image(systemName: "minus.circle") }
            Button { model.editMelodyNote(songId: songId, noteId: n.id, semitones: 1) } label: { Image(systemName: "plus.circle") }
            Button(role: .destructive) { model.editMelodyNote(songId: songId, noteId: n.id, delete: true) } label: { Image(systemName: "trash") }
        }
        .buttonStyle(.borderless)
    }
}
