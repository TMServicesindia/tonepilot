import SwiftUI
import TonePilotCore

/// Pick a tone and play it on the Casio — like the keyboard's own TONE button, but with
/// TonePilot's tones: AI-built song tones, your saved tones, and every instrument sound.
/// The selected tone plays for any music you play; it isn't tied to a song.
struct ToneSelectorView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var savedMessage: String?
    /// Shown in a sheet (with Done) or inline in the Play tab.
    var inSheet = false

    var body: some View {
        let list = model.library.toneList(search: search)
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        ConnectionStatus(midi: model.midi)
                        Spacer()
                        if AudioSessionSetup.isBuiltInSpeaker {
                            Label("iPhone speaker", systemImage: "speaker.wave.2").font(.caption).foregroundStyle(Theme.warn)
                        }
                    }
                    Text("NOW PLAYING ON YOUR KEYBOARD").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(model.activeArrangement?.name ?? "No tone selected").font(.title2.weight(.bold))
                    if let a = model.activeArrangement {
                        Text(a.layers.compactMap { model.library.patch(id: $0.patchId)?.name }.joined(separator: " + "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let savedMessage { Text(savedMessage).font(.caption).foregroundStyle(Theme.good) }
                }
                .padding(.vertical, 4)
            }

            if !list.songTones.isEmpty {
                Section("Song tones (made by TonePilot)") {
                    ForEach(list.songTones) { entry in row(entry, canSave: true) }
                }
            }
            Section {
                if list.myTones.isEmpty { Text("Save any tone here with ⋯ › Save to My Tones.").font(.caption).foregroundStyle(.secondary) }
                ForEach(list.myTones) { entry in row(entry, canSave: false) }
            } header: { Text("My tones") }
            ForEach(list.instruments) { group in
                Section(group.family.displayName) {
                    ForEach(group.entries) { entry in row(entry, canSave: true) }
                }
            }
            Section { AuditionStrip() } footer: {
                Text("Press keys on your Casio (or here) to hear the selected tone. Tones play through the app into the keyboard's AUDIO IN.")
            }
        }
        .searchable(text: $search, prompt: "Search tones")
        .navigationTitle("Tones")
        .toolbar {
            if inSheet { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { model.panic() } label: { Image(systemName: "stop.circle") }.accessibilityLabel("All notes off")
            }
        }
    }

    private func isActive(_ tone: Arrangement) -> Bool {
        guard let active = model.activeArrangement else { return false }
        return active.id == tone.id
    }

    private func row(_ entry: Library.ToneList.Entry, canSave: Bool) -> some View {
        HStack {
            Button { select(entry) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.tone.name).font(.body.weight(isActive(entry.tone) ? .bold : .regular))
                        Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if isActive(entry.tone) { Image(systemName: "pianokeys.inverse").foregroundStyle(Theme.accent) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if canSave {
                Menu {
                    Button { save(entry) } label: { Label("Save to My Tones", systemImage: "star") }
                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
            }
        }
    }

    private func select(_ entry: Library.ToneList.Entry) {
        // Song tones keep their real identity so edits made elsewhere stay in sync.
        if let songId = entry.songId, let song = model.song(songId), let real = song.arrangements.first(where: { $0.id == entry.tone.id }) {
            model.activate(real, songId: songId)
        } else {
            model.activate(entry.tone)
        }
    }

    private func save(_ entry: Library.ToneList.Entry) {
        let copy = entry.tone.savedAsMyTone(name: entry.tone.name)
        model.updateArrangement(copy, inSong: nil)
        savedMessage = "Saved “\(copy.name)” to My Tones — edit it in Tone Studio."
    }
}
