import SwiftUI
import TonePilotCore

/// Correct a chord in two taps (screen spec §2.10, Yamaha Chord Tracker pattern): the heard chord and its
/// likeliest alternative as big buttons, then any root + major / minor (the chord types TonePilot uses),
/// "Hear it", and "Also fix the repeats".
struct ChordCorrectionSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let songId: UUID
    let stepId: UUID
    @State private var chosen = ""
    @State private var fixRepeats = true

    var body: some View {
        NavigationStack {
            if let song = model.song(songId), let step = song.chordGuide?.first(where: { $0.id == stepId }) {
                let options = [step.chord] + step.alternatives.filter { $0 != step.chord }.prefix(1)
                let parsed = ChordSymbol(chosen)
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.l) {
                        (Text("TonePilot heard ") + Text(step.chord).bold() + Text(". Pick the right chord:"))
                            .font(DS.Text.bodySecondary).foregroundStyle(DS.Palette.textSecondary)
                        HStack(spacing: DS.Space.s) {
                            ForEach(Array(options.enumerated()), id: \.element) { i, c in
                                Button { chosen = c } label: {
                                    VStack(spacing: DS.Space.xxs) {
                                        Text(c).font(DS.Text.display).foregroundStyle(DS.Palette.textPrimary)
                                        Text(i == 0 ? "Most likely" : "Also possible").font(DS.Text.metadata).foregroundStyle(DS.Palette.textSecondary)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 88)
                                    .background(DS.Palette.surface, in: RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.l, style: .continuous)
                                        .strokeBorder(chosen == c ? DS.Palette.accent : .clear, lineWidth: 2))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(chosen == c ? .isSelected : [])
                                .accessibilityIdentifier("chord.option.\(i)")
                            }
                        }
                        DSSectionHeader(title: "Something else")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DS.Space.xs), count: 6), spacing: DS.Space.xs) {
                            ForEach(Array(NoteName.sharpNames.enumerated()), id: \.offset) { pc, n in
                                let on = parsed?.root == pc
                                Button { chosen = n + (parsed?.quality.rawValue ?? "") } label: {
                                    Text(n).font(DS.Text.label)
                                        .frame(maxWidth: .infinity, minHeight: DS.Size.touchTarget)
                                        .foregroundStyle(on ? DS.Palette.accent : DS.Palette.textPrimary)
                                        .background(on ? DS.Palette.accentMuted : DS.Palette.elevated, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Root \(n)")
                                .accessibilityIdentifier("chord.root.\(pc)")
                            }
                        }
                        Picker("Type", selection: Binding(get: { parsed?.quality ?? .major },
                                                          set: { q in if let p = parsed { chosen = NoteName.sharpNames[p.root] + q.rawValue } })) {
                            Text("Major").tag(ChordSymbol.Quality.major)
                            Text("Minor").tag(ChordSymbol.Quality.minor)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("chord.type")
                        Toggle("Also fix the repeats", isOn: $fixRepeats).tint(DS.Palette.accent)
                            .font(DS.Text.body)
                            .accessibilityIdentifier("chord.repeats")
                        HStack(spacing: DS.Space.s) {
                            Button {
                                if let c = ChordSymbol(chosen) {
                                    let root = 48 + c.root
                                    model.auditionChord([root, root + 7, root + 12] + (c.quality == .minor ? [root + 15] : [root + 16]))
                                }
                            } label: { Label("Hear it", systemImage: "play.fill") }
                                .buttonStyle(.dsSecondary)
                                .accessibilityIdentifier("chord.hear")
                            Button("Save") { save(step) }
                                .buttonStyle(.dsPrimary)
                                .disabled(chosen.isEmpty || chosen == step.chord)
                                .accessibilityIdentifier("chord.save")
                        }
                    }
                    .padding(DS.Space.screenMargin)
                }
                .dsCanvas()
                .navigationTitle("Chord at \(step.time.mmss)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.accessibilityIdentifier("chord.cancel") } }
                .onAppear { if chosen.isEmpty { chosen = step.chord } }
            } else {
                ContentUnavailableView("Chord not found", systemImage: "music.note")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save(_ step: ChordGuideStep) {
        if fixRepeats { model.correctChordInRepeats(songId: songId, stepId: step.id, to: chosen) }
        else { model.correctChord(songId: songId, stepId: step.id, to: chosen) }
        dismiss()
    }
}
