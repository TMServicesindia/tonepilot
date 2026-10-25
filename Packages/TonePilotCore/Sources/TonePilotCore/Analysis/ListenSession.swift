import Foundation

/// Listen Mode: the song plays from a streaming service the user is licensed to listen to
/// (on this phone's speaker or a nearby device) and TonePilot analyses what the microphone hears.
///
/// Privacy/licensing design: the captured audio exists only in memory for the duration of the
/// analysis and is never written to disk, uploaded, or played back. Only derived musical data
/// (tempo, chords, melody notes, sections, tones) is kept.
public struct ListenSession: Sendable {
    public struct Config: Sendable {
        public var sampleRate: Double = AnalysisConfig().sampleRate
        /// Hard cap so a forgotten session can't grow without bound (≈ 50 MB at 22 kHz).
        public var maxSeconds: Double = 10 * 60
        /// Auto-stop needs at least this much music first.
        public var minSecondsBeforeAutoStop: Double = 30
        /// Seconds of near-silence at the end that mean "the song finished".
        public var trailingSilenceSeconds: Double = 6
        /// Silence = below this fraction of the session's typical loudness.
        public var silenceRatio: Float = 0.08
        public init() {}
    }

    public let config: Config
    public private(set) var samples: [Float] = []
    private var blockRMS: [Float] = []
    private var pending: [Float] = []
    /// RMS block length for level tracking (0.1 s).
    private var blockSize: Int { Int(config.sampleRate / 10) }

    public init(config: Config = Config()) {
        self.config = config
        samples.reserveCapacity(Int(config.sampleRate * 300))
    }

    public var elapsed: Double { Double(samples.count) / config.sampleRate }
    public var isFull: Bool { elapsed >= config.maxSeconds }

    /// Most recent 0.1 s level (0...1-ish), for the input meter.
    public var currentLevel: Float { blockRMS.last ?? 0 }

    /// Appends mono samples already at `config.sampleRate`.
    public mutating func append(_ chunk: [Float]) {
        guard !isFull else { return }
        let room = Int(config.maxSeconds * config.sampleRate) - samples.count
        let take = chunk.count <= room ? chunk : Array(chunk.prefix(room))
        samples.append(contentsOf: take)
        pending.append(contentsOf: take)
        while pending.count >= blockSize {
            let block = pending.prefix(blockSize)
            blockRMS.append((block.reduce(0) { $0 + $1 * $1 } / Float(blockSize)).squareRoot())
            pending.removeFirst(blockSize)
        }
    }

    /// Typical loudness while music plays (median of non-silent blocks).
    var musicLevel: Float {
        let loud = blockRMS.filter { $0 > 1e-4 }.sorted()
        return loud.isEmpty ? 0 : loud[loud.count / 2]
    }

    /// True when the song seems to have ended (long enough, then sustained quiet).
    public var shouldAutoStop: Bool {
        if isFull { return true }
        guard elapsed >= config.minSecondsBeforeAutoStop + config.trailingSilenceSeconds else { return false }
        let n = Int(config.trailingSilenceSeconds * 10)
        guard blockRMS.count > n else { return false }
        let threshold = musicLevel * config.silenceRatio
        return blockRMS.suffix(n).allSatisfy { $0 < threshold }
    }

    /// True if the microphone is hearing almost nothing (volume too low / wrong device).
    public var isTooQuiet: Bool {
        guard blockRMS.count >= 30 else { return false }
        return blockRMS.suffix(30).max() ?? 0 < 0.003
    }

    /// The captured song with leading/trailing silence trimmed, ready for `SongPipeline`.
    /// Consumes the session's memory.
    public mutating func finish() -> AudioBuffer {
        let threshold = musicLevel * config.silenceRatio
        let first = blockRMS.firstIndex { $0 >= threshold } ?? 0
        let last = blockRMS.lastIndex { $0 >= threshold } ?? max(0, blockRMS.count - 1)
        let start = max(0, (first - 2) * blockSize)
        let end = min(samples.count, (last + 3) * blockSize)
        let trimmed = end > start ? Array(samples[start..<end]) : samples
        samples = []
        blockRMS = []
        pending = []
        return AudioBuffer(samples: trimmed, sampleRate: config.sampleRate)
    }
}
