import SwiftUI
import TonePilotCore

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
