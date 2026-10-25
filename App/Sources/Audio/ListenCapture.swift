import AVFoundation
import TonePilotCore

/// Listen Mode capture: records what the microphone hears while the user plays a song from a
/// streaming app they're licensed to use (on this iPhone's speaker or a nearby device).
/// Audio is kept in memory only, converted to the analysis rate, and released after analysis.
@MainActor
final class ListenCapture: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var tooQuiet = false
    @Published private(set) var songEnded = false
    @Published var error: String?
    /// Called once when the song seems to have ended. Fires even while TonePilot is in the
    /// background (the streaming app is in front), because it's driven by audio callbacks, not views.
    var onSongEnded: (() -> Void)?

    private let engine = AVAudioEngine()
    private var session = ListenSession()

    func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    func start() async {
        guard await requestPermission() else {
            error = "Microphone access is off. Enable it in Settings › Privacy › Microphone › TonePilot."
            return
        }
        do {
            let s = AVAudioSession.sharedInstance()
            // .measurement disables voice processing (AGC/echo cancellation) that would distort music.
            // .mixWithOthers lets Spotify/YouTube Music/Apple Music keep playing while we listen.
            try s.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
            try s.setActive(true)
            let input = engine.inputNode
            let inFormat = input.outputFormat(forBus: 0)
            session = ListenSession()
            guard let tapConverter = TapConverter(from: inFormat) else { throw NSError(domain: "TonePilot", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unsupported microphone format"]) }
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
                let chunk = tapConverter.convert(buffer)
                Task { @MainActor in self?.ingest(chunk) }
            }
            engine.prepare()
            try engine.start()
            isListening = true
            songEnded = false
            error = nil
        } catch {
            self.error = "Couldn't start listening: \(error.localizedDescription)"
        }
    }

    private func ingest(_ chunk: [Float]) {
        guard isListening, !chunk.isEmpty else { return }
        session.append(chunk)
        elapsed = session.elapsed
        level = session.currentLevel
        tooQuiet = session.isTooQuiet
        if session.shouldAutoStop, !songEnded {
            songEnded = true
            onSongEnded?()
        }
    }

    /// Stops listening and returns the captured song (memory is released from the session).
    func stop() -> TonePilotCore.AudioBuffer? {
        guard isListening else { return nil }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isListening = false
        // Hand the audio session back to playback for the tone engine.
        try? AudioSessionSetup.activate()
        let audio = session.finish()
        return audio.duration >= 8 ? audio : nil
    }

    func cancel() {
        _ = stop()
    }
}

/// Persistent mono resampler used only on the (serial) audio tap thread, so its filter state
/// carries across buffers without glitches.
final class TapConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let out: AVAudioFormat

    init?(from input: AVAudioFormat) {
        guard let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: AnalysisConfig().sampleRate, channels: 1, interleaved: false),
              let c = AVAudioConverter(from: input, to: out) else { return nil }
        c.downmix = true
        converter = c
        self.out = out
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * out.sampleRate / buffer.format.sampleRate) + 64
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: capacity) else { return [] }
        var fed = false
        var error: NSError?
        converter.convert(to: outBuf, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard let ch = outBuf.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: ch, count: Int(outBuf.frameLength)))
    }
}
