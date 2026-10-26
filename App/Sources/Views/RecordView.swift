import AVFoundation
import SwiftUI

/// Record tab: record your playing (in sync with the song parts that are playing, if chosen),
/// starting on your first key press, and keep it as MP3 to play, share or save to Files.
struct RecordView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var player = RecordingPlayer()
    @State private var renaming: Recording?
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                RecordPanel(live: model.live)
                Toggle(isOn: $model.recordIncludeSong) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include the song parts that are playing")
                        Text(model.recordIncludeSong ? "Your playing and the music, in sync." : "Only what you play on your keyboard.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.accent)
                .disabled(model.recordState != .idle)
                .accessibilityIdentifier("record.includeSong")
                Toggle(isOn: $model.recordWaitForKey) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start when I press the first key")
                        Text("No silence at the start — the moment just before your first note is kept.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.accent)
                .disabled(model.recordState != .idle)
                .accessibilityIdentifier("record.waitForKey")
                if let e = model.recordError { Text(e).font(.caption).foregroundStyle(Theme.bad) }
            } footer: {
                Text("Records TonePilot's own sound straight from the app (your tones, the arpeggio fill, and the song parts if included) — nothing from the room.")
            }

            Section("Recordings") {
                if model.recordings.isEmpty {
                    Text("Your recordings appear here as MP3 files. They're also in the Files app › On My iPhone › TonePilot › Recordings.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(model.recordings) { r in
                    RecordingRow(recording: r, player: player)
                        .swipeActions {
                            Button(role: .destructive) { player.stop(); model.deleteRecording(r) } label: { Label("Delete", systemImage: "trash") }
                            Button { newName = r.name; renaming = r } label: { Label("Rename", systemImage: "pencil") }.tint(.blue)
                        }
                }
            }
        }
        .navigationTitle("Record")
        .onAppear { model.refreshRecordings() }
        .onDisappear { player.stop() }
        .alert("Rename recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { if let r = renaming { player.stop(); model.renameRecording(r, to: newName) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }
}

/// The big record button, timer and level (redraws with LiveState only).
private struct RecordPanel: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var live: LiveState

    var body: some View {
        let state = model.recordState
        VStack(spacing: 14) {
            Button {
                switch state {
                case .idle: model.startRecording()
                case .recording, .waitingForKey: model.stopRecording()
                case .saving: break
                }
            } label: {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 4).frame(width: 96, height: 96)
                    if case .idle = state {
                        Circle().fill(Color.red).frame(width: 76, height: 76)
                    } else if case .saving = state {
                        ProgressView().controlSize(.large)
                    } else {
                        RoundedRectangle(cornerRadius: 8).fill(Color.red).frame(width: 40, height: 40)
                    }
                }
                .frame(width: 104, height: 104)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("record.button")
            .accessibilityLabel(state == .idle ? "Record" : "Stop")
            Text(Self.clock(live.recordSeconds)).font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                .opacity(state == .idle ? 0.4 : 1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(live.recordLevel))
                }
            }
            .frame(height: 6)
            Text(statusText(state)).font(.subheadline.weight(.semibold))
                .foregroundStyle(state == .idle ? Color.secondary : Theme.accent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("record.status")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func statusText(_ s: Recorder.State) -> String {
        switch s {
        case .idle: return "Tap to record"
        case .waitingForKey: return "Ready — recording starts with your first key"
        case .recording: return "Recording… tap to stop"
        case .saving(let p): return "Saving MP3… \(Int(p * 100))%"
        }
    }

    static func clock(_ t: Double) -> String {
        let s = Int(t)
        return String(format: "%d:%02d.%d", s / 60, s % 60, Int((t - Double(s)) * 10))
    }
}

private struct RecordingRow: View {
    let recording: Recording
    @ObservedObject var player: RecordingPlayer

    var body: some View {
        let playing = player.current == recording.url
        HStack(spacing: 12) {
            Button { playing ? player.stop() : player.play(recording.url) } label: {
                Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 34))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Stop \(recording.name)" : "Play \(recording.name)")
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(recording.duration.mmss) · \(ByteCountFormatter.string(fromByteCount: recording.bytes, countStyle: .file)) · MP3")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            ShareLink(item: recording.url) {
                Image(systemName: "square.and.arrow.up").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Share or save \(recording.name)")
        }
    }
}

/// Plays one recording at a time.
@MainActor
final class RecordingPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var current: URL?
    private var player: AVAudioPlayer?

    func play(_ url: URL) {
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        p.play()
        player = p
        current = url
    }

    func stop() {
        player?.stop()
        player = nil
        current = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}
