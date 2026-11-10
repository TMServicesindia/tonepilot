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
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("Include the song parts")
                        Text(model.recordIncludeSong ? "Your playing and the music, in sync." : "Only what you play.")
                            .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
                    }
                }
                .tint(DS.Palette.accent)
                .disabled(model.recordState != .idle)
                .accessibilityIdentifier("record.includeSong")
                Toggle(isOn: $model.recordWaitForKey) {
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text("Start on the first key")
                        Text("No silence at the start.")
                            .font(DS.Text.caption).foregroundStyle(DS.Palette.textSecondary)
                    }
                }
                .tint(DS.Palette.accent)
                .disabled(model.recordState != .idle)
                .accessibilityIdentifier("record.waitForKey")
                if let e = model.recordError {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(DS.Text.caption).foregroundStyle(DS.Palette.error)
                }
            } footer: {
                Text("Records TonePilot's own sound, not the room.")
            }

            Section("Recordings") {
                if model.recordings.isEmpty {
                    DSEmptyState(symbol: "waveform", title: "No recordings yet", message: "Saved as MP3 in Files › TonePilot › Recordings.")
                        .accessibilityIdentifier("record.empty")
                }
                ForEach(model.recordings) { r in
                    RecordingRow(recording: r, player: player,
                                 onRename: { newName = r.name; renaming = r },
                                 onDelete: { player.stop(); model.deleteRecording(r) })
                        .swipeActions {
                            Button(role: .destructive) { player.stop(); model.deleteRecording(r) } label: { Label("Delete", systemImage: "trash") }
                            Button { newName = r.name; renaming = r } label: { Label("Rename", systemImage: "pencil") }.tint(DS.Palette.info)
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .dsCanvas()
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
        VStack(spacing: DS.Space.l) {
            Button {
                switch state {
                case .idle: model.startRecording()
                case .recording, .waitingForKey: model.stopRecording()
                case .saving: break
                }
            } label: {
                ZStack {
                    // Red is the universal record mark (the one non-error use of the error colour).
                    Circle().stroke(DS.Palette.border, lineWidth: 4).frame(width: 96, height: 96)
                    if case .idle = state {
                        Circle().fill(DS.Palette.error).frame(width: 76, height: 76)
                    } else if case .saving = state {
                        ProgressView().controlSize(.large)
                    } else {
                        RoundedRectangle(cornerRadius: DS.Radius.s).fill(DS.Palette.error).frame(width: 40, height: 40)
                    }
                }
                .frame(width: 104, height: 104)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("record.button")
            .accessibilityLabel(state == .idle ? "Record" : "Stop")
            Text(Self.clock(live.recordSeconds)).font(DS.Text.display.monospacedDigit())
                .foregroundStyle(DS.Palette.textPrimary)
                .opacity(state == .idle ? 0.4 : 1)
                .accessibilityLabel("Recording time")
                .accessibilityValue("\(Int(live.recordSeconds) / 60) minutes \(Int(live.recordSeconds) % 60) seconds")
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Palette.elevated)
                    Capsule().fill(LinearGradient(colors: [DS.Palette.success, DS.Palette.warning, DS.Palette.error], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(live.recordLevel))
                }
            }
            .frame(height: 6)
            Text(statusText(state)).font(DS.Text.label)
                .foregroundStyle(state == .idle ? DS.Palette.textSecondary : DS.Palette.accent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("record.status")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Space.s)
    }

    private func statusText(_ s: Recorder.State) -> String {
        switch s {
        case .idle: return "Tap to record"
        case .waitingForKey: return "Ready. Recording starts with your first key"
        case .recording: return "Recording. Tap to stop"
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
    var onRename: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        let playing = player.current == recording.url
        HStack(spacing: DS.Space.m) {
            Button { playing ? player.stop() : player.play(recording.url) } label: {
                Image(systemName: playing ? "stop.circle.fill" : "play.circle.fill").font(DS.Text.largeTitle.weight(.regular))
                    .foregroundStyle(DS.Palette.accent)
                    .frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playing ? "Stop \(recording.name)" : "Play \(recording.name)")
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.name).font(DS.Text.body.weight(.semibold)).foregroundStyle(DS.Palette.textPrimary).lineLimit(1)
                Text("\(recording.duration.mmss) · \(ByteCountFormatter.string(fromByteCount: recording.bytes, countStyle: .file)) · MP3")
                    .font(DS.Text.metadata.monospacedDigit()).foregroundStyle(DS.Palette.textSecondary)
            }
            Spacer(minLength: DS.Space.xs)
            ShareLink(item: recording.url) {
                Image(systemName: "square.and.arrow.up").frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
            }
            .accessibilityLabel("Share or save \(recording.name)")
            // Visible ⋯ for what the swipe also offers (no hidden-only actions).
            Menu {
                Button(action: onRename) { Label("Rename", systemImage: "pencil") }
                Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: DS.Size.touchTarget, height: DS.Size.touchTarget)
            }
            .accessibilityLabel("\(recording.name) options")
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
