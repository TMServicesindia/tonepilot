import Foundation
import TonePilotCore

/// Record tab: records TonePilot's own output (your playing, optionally with the song parts that
/// are playing), starting on your first key press, and saves it as MP3.
extension AppModel {
    func refreshRecordings() {
        Task.detached(priority: .utility) { [weak self] in
            let list = RecordingsFolder.list()
            await MainActor.run { self?.recordings = list }
        }
    }

    func startRecording() {
        guard recordState == .idle else { return }
        recordError = nil
        let engine = output.avEngine
        let node = recordIncludeSong ? engine.mainMixerNode : (output.instrumentNode ?? engine.mainMixerNode)
        do {
            try recorder.start(node: node, waitForKey: recordWaitForKey)
        } catch {
            recordError = "Recording couldn't start: \(error.localizedDescription)"
            return
        }
        recordWaiting.withLock { $0 = recordWaitForKey }
        recordState = recordWaitForKey ? .waitingForKey : .recording
        live.recordSeconds = 0
        recordTimer?.invalidate()
        recordTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let s = self.recorder.status()
                self.live.recordSeconds = s.seconds
                self.live.recordLevel = min(1, s.peak)
            }
        }
    }

    func stopRecording() {
        guard recordState == .recording || recordState == .waitingForKey else { return }
        recordTimer?.invalidate()
        recordTimer = nil
        recordWaiting.withLock { $0 = false }
        live.recordLevel = 0
        guard let raw = recorder.stop() else { recordState = .idle; return }
        let title = song(activeSongId)?.title ?? "My playing"
        let stamp = Date().formatted(.dateTime.day().month(.abbreviated).hour().minute())
        let dest = RecordingsFolder.freshURL(base: "\(title) – \(stamp)".replacingOccurrences(of: ":", with: "."))
        recordState = .saving(0)
        let throttle = ProgressThrottle()
        let thread = Thread { [weak self] in
            var failure: String?
            do {
                try Mp3Encoder.encode(raw, to: dest) { p in
                    if throttle.shouldSend(p) { Task { @MainActor in if case .saving = self?.recordState { self?.recordState = .saving(p) } } }
                }
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                try? FileManager.default.removeItem(at: dest)
            }
            try? FileManager.default.removeItem(at: raw)
            let failureText = failure
            Task { @MainActor in
                guard let self else { return }
                self.recordState = .idle
                self.recordError = failureText
                self.refreshRecordings()
            }
        }
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func deleteRecording(_ r: Recording) {
        try? FileManager.default.removeItem(at: r.url)
        recordings.removeAll { $0.url == r.url }
    }

    func renameRecording(_ r: Recording, to name: String) {
        if !RecordingsFolder.rename(r, to: name) { recordError = "A recording with that name already exists." }
        refreshRecordings()
    }
}
