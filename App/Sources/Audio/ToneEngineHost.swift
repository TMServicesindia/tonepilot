import AVFoundation
import TonePilotCore

/// What AppModel needs from a sound backend. Two implementations:
/// - `ToneEngineHost` (default): TonePilot's own engine (full layer controls, accompaniment, melody guide).
/// - `SoundEngine` (legacy): Apple's AVAudioUnitSampler — fewer controls, kept as a fallback.
protocol ToneOutput: AnyObject {
    var avEngine: AVAudioEngine { get }
    var songPlayerNode: AVAudioPlayerNode { get }
    var onMeter: ((Float, Bool) -> Void)? { get set }
    var routeDescription: String { get }
    var supportsAccompaniment: Bool { get }
    /// Your instruments only (no song audio), for recording just your playing.
    var instrumentNode: AVAudioNode? { get }
    func start() throws
    func stop()
    /// Called on the CoreMIDI thread.
    func perform(_ commands: [SoundCommand])
    func allNotesOff()
}

enum AudioSessionSetup {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        // .playback: sound continues with the silent switch on and goes to the wired/USB output
        // that feeds the Casio's AUDIO IN.
        try session.setCategory(.playback, mode: .default, options: [])
        // ~5 ms buffers for live playing; iOS may grant a larger value (shown in Diagnostics).
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }

    static var routeDescription: String {
        let s = AVAudioSession.sharedInstance()
        let outputs = s.currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        let ms = (s.outputLatency + s.ioBufferDuration) * 1000
        return "\(outputs.isEmpty ? "No output" : outputs) · ≈\(Int(ms.rounded())) ms output latency · \(Int(s.sampleRate)) Hz"
    }

    /// True when the sound would come out of the iPhone's own speaker (not the Casio).
    static var isBuiltInSpeaker: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
    }
}

/// Hosts `ToneEngine` in AVAudioEngine through an AVAudioSourceNode. The render block only calls
/// `ToneEngine.render` (allocation- and lock-free). Commands arrive through the engine's queue.
final class ToneEngineHost: ToneOutput, @unchecked Sendable {
    let avEngine = AVAudioEngine()
    let songPlayer = AVAudioPlayerNode()
    let core: ToneEngine
    let controller: ToneEngineController
    var onMeter: ((Float, Bool) -> Void)?
    private var sourceNode: AVAudioSourceNode?
    private var meterTimer: Timer?

    var songPlayerNode: AVAudioPlayerNode { songPlayer }
    var supportsAccompaniment: Bool { true }
    var instrumentNode: AVAudioNode? { sourceNode }
    var routeDescription: String { AudioSessionSetup.routeDescription + " · \(core.activeVoiceCount) voices" }

    init() {
        // Render at the hardware rate when known so no resampling is needed.
        let rate = AVAudioSession.sharedInstance().sampleRate
        core = ToneEngine(sampleRate: rate >= 22_050 ? rate : 48_000, maxFrames: 4096)
        controller = ToneEngineController(engine: core)
        buildGraph()
    }

    private func buildGraph() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: core.sampleRate, channels: 2) else { return }
        let engine = core
        let node = AVAudioSourceNode(format: format) { _, _, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let total = Int(frameCount)
            var done = 0
            while done < total {
                let n = min(total - done, engine.maxFrames)
                engine.render(frames: n, left: l + done, right: r + done)
                done += n
            }
            return noErr
        }
        sourceNode = node
        avEngine.attach(node)
        avEngine.attach(songPlayer)
        avEngine.connect(node, to: avEngine.mainMixerNode, format: format)
        avEngine.connect(songPlayer, to: avEngine.mainMixerNode, format: nil)
    }

    func start() throws {
        try AudioSessionSetup.activate()
        avEngine.prepare()
        try avEngine.start()
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onMeter?(min(1, self.core.meterPeak), self.core.limiterEngaged)
        }
    }

    func stop() {
        allNotesOff()
        meterTimer?.invalidate()
        avEngine.stop()
    }

    func perform(_ commands: [SoundCommand]) { controller.perform(commands) }

    func allNotesOff() { core.send(.allNotesOff) }
}

extension SoundEngine: ToneOutput {
    var avEngine: AVAudioEngine { engine }
    var songPlayerNode: AVAudioPlayerNode { songPlayer }
    var supportsAccompaniment: Bool { false }
    var instrumentNode: AVAudioNode? { nil }
}
