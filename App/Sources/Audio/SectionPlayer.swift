import AVFoundation
import TonePilotCore

/// Plays the song's audio — the original recording, or its separated stems in sync — from any
/// point, optionally looping a section, through the same output as the tones. Each track has
/// its own level (Song Studio mixer). Its position is the timing reference for automatic tone
/// switching and the generated parts.
///
/// Graph: track players → submix → time/pitch (slow practice keeps the pitch) → main mixer.
final class SectionPlayer {
    private struct Track {
        let id: String
        let node: AVAudioPlayerNode
        let file: AVAudioFile
    }

    private let engine: AVAudioEngine
    /// The node supplied by the output (used for the first track).
    private let primary: AVAudioPlayerNode
    private let submix = AVAudioMixerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var tracks: [Track] = []
    private var loadedKey: String?
    private var levels: [String: Float] = [:]
    private var range: (start: Double, end: Double)?
    private var loop = false
    private var generation = 0
    private(set) var isPlaying = false

    /// 0.25...2 (1 = normal speed). Pitch stays the same.
    var rate: Float {
        get { timePitch.rate }
        set { timePitch.rate = max(0.25, min(2, newValue)) }
    }

    init(player: AVAudioPlayerNode, engine: AVAudioEngine) {
        primary = player
        self.engine = engine
        engine.attach(submix)
        engine.attach(timePitch)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
        engine.connect(submix, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    }

    /// Track ids currently loaded (e.g. `audio.original` or the stems).
    var trackIds: [String] { tracks.map(\.id) }

    /// Loads one or more files that start together (the recording, or its stems).
    func load(_ files: [(id: String, url: URL)]) throws {
        let key = files.map { "\($0.id)=\($0.url.path)" }.joined(separator: "|")
        if key == loadedKey, !tracks.isEmpty { return }
        stop()
        for t in tracks where t.node !== primary { engine.detach(t.node) }
        tracks = []
        loadedKey = nil
        for (i, f) in files.enumerated() {
            let file = try AVAudioFile(forReading: f.url)
            let node: AVAudioPlayerNode
            if i == 0 { node = primary } else { node = AVAudioPlayerNode(); engine.attach(node) }
            engine.connect(node, to: submix, format: file.processingFormat)
            node.volume = levels[f.id] ?? 1
            tracks.append(Track(id: f.id, node: node, file: file))
        }
        loadedKey = key
    }

    func load(url: URL) throws { try load([(SongStudio.original, url)]) }

    var duration: Double {
        guard let f = tracks.first?.file else { return 0 }
        return Double(f.length) / f.processingFormat.sampleRate
    }

    /// Sets a track's level (0 = silent; the track keeps playing in sync).
    func setLevel(_ level: Float, for id: String) {
        levels[id] = level
        tracks.first { $0.id == id }?.node.volume = level
    }

    /// Starts playback at `start` seconds until `end` (or the end of the song); loops when asked.
    func play(from start: Double, to end: Double? = nil, loop: Bool = false) {
        // play() on a stopped engine raises an Objective-C exception.
        guard !tracks.isEmpty, engine.isRunning else { return }
        stop()
        let stopAt = min(duration, end ?? duration)
        guard stopAt > start else { return }
        range = (max(0, start), stopAt)
        self.loop = loop
        generation += 1
        let g = generation
        // Start every track on the same future host time so stems stay sample-aligned.
        let when = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.05))
        for (i, t) in tracks.enumerated() {
            let sr = t.file.processingFormat.sampleRate
            let first = AVAudioFramePosition(max(0, start) * sr)
            let last = min(t.file.length, AVAudioFramePosition(stopAt * sr))
            guard last > first else { continue }
            t.node.scheduleSegment(t.file, startingFrame: first, frameCount: AVAudioFrameCount(last - first), at: nil,
                                   completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard i == 0 else { return }
                DispatchQueue.main.async { self?.finished(generation: g) }
            }
        }
        for t in tracks { t.node.play(at: when) }
        isPlaying = true
    }

    private func finished(generation g: Int) {
        guard g == generation, isPlaying else { return }
        if loop, let range { play(from: range.start, to: range.end, loop: true) } else { isPlaying = false }
    }

    /// Song position in seconds, or nil when stopped.
    var currentTime: Double? {
        guard isPlaying, let range, let clock = tracks.first, let nodeTime = clock.node.lastRenderTime,
              let playerTime = clock.node.playerTime(forNodeTime: nodeTime) else { return nil }
        let played = max(0, Double(playerTime.sampleTime) / playerTime.sampleRate)
        return min(range.end, range.start + played)
    }

    func stop() {
        generation += 1
        for t in tracks { t.node.stop() }
        isPlaying = false
    }
}
