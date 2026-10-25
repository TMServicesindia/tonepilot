import SwiftUI
import TonePilotCore

/// Listen Mode: play the song in Spotify, YouTube Music, Apple Music, JioSaavn… and TonePilot
/// listens through the microphone, then builds the full arrangement. Nothing is recorded to disk.
struct ListenModeView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var capture = ListenCapture()
    /// Existing song to re-analyse, or nil to create a new one.
    var songId: UUID?
    @State private var title = ""
    @State private var film = ""
    @State private var service = "Spotify"
    @State private var licensed = false
    @State private var message: String?

    private let services = ["Spotify", "YouTube Music", "Apple Music", "JioSaavn", "Amazon Music", "Other"]

    var body: some View {
        NavigationStack {
            Form {
                if songId == nil {
                    Section("Song") {
                        TextField("Title (e.g. Hukum – Thalaivar Alappara)", text: $title)
                        TextField("Film / album", text: $film)
                        Picker("Playing from", selection: $service) { ForEach(services, id: \.self) { Text($0) } }
                    }
                }
                Section {
                    Toggle("I'm playing this from a service I'm licensed to listen to", isOn: $licensed)
                } footer: {
                    Text("TonePilot only analyses what the microphone hears and keeps the results (tempo, chords, melody, sections, tones). The audio stays in memory and is discarded — it's never saved, uploaded or played back.")
                }
                Section("How to") {
                    Label("Turn the music volume up (70–90%) in a quiet room.", systemImage: "speaker.wave.3")
                    Label("Tap Start listening, then play the song from the beginning in \(service).", systemImage: "play.circle")
                    Label("Playing from this iPhone works; a nearby speaker or second device is cleaner.", systemImage: "iphone.radiowaves.left.and.right")
                    Label("TonePilot stops by itself when the song ends, or tap Stop & build.", systemImage: "stop.circle")
                }
                Section {
                    if capture.isListening {
                        HStack {
                            Image(systemName: "waveform").foregroundStyle(Theme.accent)
                            Text("Listening · \(capture.elapsed.mmss)").font(.headline.monospacedDigit())
                            Spacer()
                        }
                        ProgressView(value: Double(min(1, capture.level * 8)))
                        if capture.tooQuiet { Text("I can barely hear anything — turn the music up or move the phone closer.").font(.caption).foregroundStyle(Theme.warn) }
                        if capture.songEnded { Text("Sounds like the song ended.").font(.caption).foregroundStyle(Theme.good) }
                        Button("Stop & build arrangement") { finish() }.buttonStyle(.borderedProminent)
                        Button("Cancel", role: .destructive) { capture.cancel() }
                    } else {
                        Button { Task { await capture.start() } } label: { Label("Start listening", systemImage: "mic.fill") }
                            .buttonStyle(.borderedProminent)
                            .disabled(!licensed || (songId == nil && title.trimmingCharacters(in: .whitespaces).isEmpty))
                    }
                    if let e = capture.error { Text(e).font(.footnote).foregroundStyle(Theme.bad) }
                    if let message { Text(message).font(.footnote) }
                }
            }
            .navigationTitle("Listen Mode")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { capture.cancel(); dismiss() } } }
            .onChange(of: capture.songEnded) { _, ended in if ended { finish() } }
        }
    }

    private func finish() {
        guard let audio = capture.stop() else {
            message = "That was too short to analyse — play at least 30 seconds."
            return
        }
        let id: UUID
        if let songId {
            id = songId
        } else {
            var song = Song(title: title.trimmingCharacters(in: .whitespaces), film: film.isEmpty ? nil : film,
                            sourceType: .listened, sourceReference: service, userConfirmedRights: true)
            song.arrangements = [.starterFilmStack(name: "Main tone")]
            model.update(song)
            id = song.id
        }
        model.analyzeListened(songId: id, audio: audio)
        dismiss()
    }
}
