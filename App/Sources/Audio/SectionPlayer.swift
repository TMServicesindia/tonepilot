import AVFoundation
import TonePilotCore

/// Plays (and optionally loops) one section of the imported song through the same
/// engine as the tones, so the user can practise along through the Casio speakers.
final class SectionPlayer {
    private let player: AVAudioPlayerNode
    private let engine: AVAudioEngine
    private var file: AVAudioFile?
    private var loopRange: (start: AVAudioFramePosition, count: AVAudioFrameCount)?
    private var generation = 0
    private(set) var isPlaying = false

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    init(player: AVAudioPlayerNode, engine: AVAudioEngine) {
        self.player = player
        self.engine = engine
    }

    func load(url: URL) throws {
        stop()
        let f = try AVAudioFile(forReading: url)
        // Match the player's connection to the file so no implicit conversion is needed.
        engine.connect(player, to: engine.mainMixerNode, format: f.processingFormat)
        file = f
    }

    /// Starts playback at `start` seconds; loops between start and end when `loop` is true.
    func play(from start: Double, to end: Double?, loop: Bool) {
        // play() on a stopped engine raises an Objective-C exception.
        guard let file, engine.isRunning else { return }
        stop()
        let sr = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(max(0, start) * sr)
        let endFrame = min(file.length, end.map { AVAudioFramePosition($0 * sr) } ?? file.length)
        guard endFrame > startFrame else { return }
        loopRange = (startFrame, AVAudioFrameCount(endFrame - startFrame))
        generation += 1
        schedule(loop: loop, generation: generation)
        player.play()
        isPlaying = true
    }

    private func schedule(loop: Bool, generation: Int) {
        guard let file, let range = loopRange else { return }
        player.scheduleSegment(file, startingFrame: range.start, frameCount: range.count, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.generation == generation, self.isPlaying else { return }
                if loop { self.schedule(loop: true, generation: generation) } else { self.isPlaying = false }
            }
        }
    }

    func stop() {
        generation += 1
        player.stop()
        isPlaying = false
    }
}
