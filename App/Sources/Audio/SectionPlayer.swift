import AVFoundation
import TonePilotCore

/// Plays (and optionally loops) the imported song — a section or from any point — through the
/// same output as the tones, so you can play along through the Casio speakers. Its position is
/// the timing reference for automatic tone switching and accompaniment sync.
final class SectionPlayer {
    private let player: AVAudioPlayerNode
    private let engine: AVAudioEngine
    private var file: AVAudioFile?
    private(set) var loadedURL: URL?
    private var range: (start: AVAudioFramePosition, count: AVAudioFrameCount)?
    private var loop = false
    private var generation = 0
    private(set) var isPlaying = false

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    /// Changes playback speed without changing pitch (practice at 50–100%).
    private let timePitch = AVAudioUnitTimePitch()

    /// 0.5...1.0 (1 = normal speed). Pitch stays the same.
    var rate: Float {
        get { timePitch.rate }
        set { timePitch.rate = max(0.25, min(2, newValue)) }
    }

    init(player: AVAudioPlayerNode, engine: AVAudioEngine) {
        self.player = player
        self.engine = engine
        engine.attach(timePitch)
    }

    func load(url: URL) throws {
        if loadedURL == url, file != nil { return }
        stop()
        let f = try AVAudioFile(forReading: url)
        // player -> time/pitch (slow practice) -> mixer, matching the file's format.
        engine.connect(player, to: timePitch, format: f.processingFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: f.processingFormat)
        file = f
        loadedURL = url
    }

    var duration: Double {
        guard let file else { return 0 }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Starts playback at `start` seconds until `end` (or the end of the song); loops when asked.
    func play(from start: Double, to end: Double? = nil, loop: Bool = false) {
        // play() on a stopped engine raises an Objective-C exception.
        guard let file, engine.isRunning else { return }
        stop()
        let sr = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, start) * sr)
        let endFrame = min(file.length, end.map { AVAudioFramePosition($0 * sr) } ?? file.length)
        guard endFrame > startFrame else { return }
        range = (startFrame, AVAudioFrameCount(endFrame - startFrame))
        self.loop = loop
        generation += 1
        schedule(generation: generation)
        player.play()
        isPlaying = true
    }

    private func schedule(generation: Int) {
        guard let file, let range else { return }
        player.scheduleSegment(file, startingFrame: range.start, frameCount: range.count, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == generation, self.isPlaying else { return }
                if self.loop { self.schedule(generation: generation) } else { self.isPlaying = false }
            }
        }
    }

    /// Song position in seconds (accounts for loops), or nil when stopped.
    var currentTime: Double? {
        guard isPlaying, let file, let range, let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return nil }
        let sr = file.processingFormat.sampleRate
        var played = AVAudioFramePosition(Double(playerTime.sampleTime) * sr / playerTime.sampleRate)
        if loop, range.count > 0 { played %= AVAudioFramePosition(range.count) }
        return Double(range.start + max(0, played)) / sr
    }

    func stop() {
        generation += 1
        player.stop()
        isPlaying = false
    }
}
