import AVFoundation
import AudioToolbox
import TonePilotCore

/// Real-time sound generation: a fixed pool of sampler voices (one per layer),
/// each with filter -> delay -> reverb -> pan/volume, summed into a peak limiter.
///
/// Threading:
/// - `perform(_:)` is called on the CoreMIDI receive thread. It only reads an
///   immutable routing snapshot (swapped under a lock) and sends MIDI to samplers.
/// - Loading SoundFont presets does disk I/O and happens on `loadQueue`, never on
///   the MIDI or render thread.
/// - No analysis, networking or allocation-heavy work ever runs here.
final class SoundEngine: @unchecked Sendable {
    /// Layer count is capped by what an iPhone renders reliably; raise after profiling (Milestone 7).
    static let maxLayers = 6

    final class Slot {
        let sampler = AVAudioUnitSampler()
        let filter = AVAudioUnitEQ(numberOfBands: 1)
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()
        let mixer = AVAudioMixerNode()
        var loadedPreset: SoundFontReference?
    }

    let engine = AVAudioEngine()
    let slots: [Slot] = (0..<SoundEngine.maxLayers).map { _ in Slot() }
    /// Bus for song playback (practice along with a section) so it can be balanced against the tones.
    let songPlayer = AVAudioPlayerNode()
    private let toneBus = AVAudioMixerNode()
    private let limiter: AVAudioUnitEffect = {
        let desc = AudioComponentDescription(componentType: kAudioUnitType_Effect,
                                             componentSubType: kAudioUnitSubType_PeakLimiter,
                                             componentManufacturer: kAudioUnitManufacturer_Apple,
                                             componentFlags: 0, componentFlagsMask: 0)
        return AVAudioUnitEffect(audioComponentDescription: desc)
    }()

    private let routingLock = NSLock()
    private var routing: [UUID: AVAudioUnitSampler] = [:]
    private let loadQueue = DispatchQueue(label: "TonePilot.SoundFontLoad", qos: .userInitiated)

    /// Peak output level 0...1 (+ clip flag), delivered on the main thread ~20x/s.
    var onMeter: ((Float, Bool) -> Void)?

    private(set) var isRunning = false
    var soundFontDirectory: URL

    init(soundFontDirectory: URL) {
        self.soundFontDirectory = soundFontDirectory
        buildGraph()
    }

    private func buildGraph() {
        engine.attach(toneBus)
        engine.attach(limiter)
        engine.attach(songPlayer)
        let format = engine.outputNode.inputFormat(forBus: 0)
        let stereo = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate > 0 ? format.sampleRate : 48_000, channels: 2)
        for slot in slots {
            [slot.sampler, slot.filter, slot.delay, slot.reverb, slot.mixer].forEach { engine.attach($0) }
            engine.connect(slot.sampler, to: slot.filter, format: stereo)
            engine.connect(slot.filter, to: slot.delay, format: stereo)
            engine.connect(slot.delay, to: slot.reverb, format: stereo)
            engine.connect(slot.reverb, to: slot.mixer, format: stereo)
            engine.connect(slot.mixer, to: toneBus, format: stereo)
            let band = slot.filter.bands[0]
            band.filterType = .resonantLowPass
            band.bypass = true
            slot.delay.wetDryMix = 0
            slot.reverb.loadFactoryPreset(.mediumHall)
            slot.reverb.wetDryMix = 0
            slot.mixer.outputVolume = 0
        }
        engine.connect(toneBus, to: limiter, format: stereo)
        engine.connect(songPlayer, to: engine.mainMixerNode, format: nil)
        engine.connect(limiter, to: engine.mainMixerNode, format: stereo)
        installMeter()
    }

    // MARK: Session & lifecycle

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // .playback keeps sound going with the silent switch on and routes to the
        // headphone/line output that feeds the Casio AUDIO IN.
        try session.setCategory(.playback, mode: .default, options: [])
        // ~5 ms buffers for low-latency live playing; iOS may grant a larger value.
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        allNotesOff()
        engine.stop()
        isRunning = false
    }

    /// Current output route + measured latency, for the diagnostics screen.
    var routeDescription: String {
        let s = AVAudioSession.sharedInstance()
        let outputs = s.currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        let ms = (s.outputLatency + s.ioBufferDuration) * 1000
        return "\(outputs.isEmpty ? "No output" : outputs) · ≈\(Int(ms.rounded())) ms output latency · \(Int(s.sampleRate)) Hz"
    }

    // MARK: Arrangement

    /// Configures slots for the arrangement's audible layers. Preset loading happens on a
    /// background queue; `completion` reports presets that failed to load (missing SoundFont etc.).
    func apply(_ arrangement: Arrangement?, patches: [UUID: InstrumentPatch], completion: @escaping ([String]) -> Void) {
        let layers = Array((arrangement?.audibleLayers ?? []).prefix(Self.maxLayers))
        var newRouting: [UUID: AVAudioUnitSampler] = [:]
        var loads: [(Slot, SoundFontReference, String)] = []

        for (i, slot) in slots.enumerated() {
            guard i < layers.count, let arrangement else {
                slot.mixer.outputVolume = 0
                continue
            }
            let layer = layers[i]
            let patch = patches[layer.patchId]
            newRouting[layer.id] = slot.sampler
            slot.mixer.outputVolume = Float(GainStaging.effectiveGain(layer: layer, in: arrangement))
            slot.mixer.pan = Float(layer.pan)
            slot.sampler.globalTuning = Float(layer.fineTuneCents)

            let effects = layer.effectsOverride ?? patch?.effects ?? EffectSettings()
            slot.reverb.wetDryMix = Float(effects.reverbMix)
            slot.delay.wetDryMix = Float(effects.delayMix)
            slot.delay.delayTime = effects.delayTime
            slot.delay.feedback = Float(effects.delayFeedback)
            let filter = patch?.filter ?? FilterSettings()
            let band = slot.filter.bands[0]
            band.bypass = !filter.enabled
            band.frequency = Float(filter.cutoff)
            band.bandwidth = Float(max(0.05, 2 - filter.resonance / 12)) // more resonance = narrower band

            if let ref = patch?.soundFont, ref != slot.loadedPreset {
                loads.append((slot, ref, patch?.name ?? "Unknown patch"))
            }
        }

        routingLock.lock()
        routing = newRouting
        routingLock.unlock()

        guard !loads.isEmpty else { completion([]); return }
        let dir = soundFontDirectory
        loadQueue.async {
            var failures: [String] = []
            var loaded: [(Slot, SoundFontReference?)] = []
            for (slot, ref, name) in loads {
                let url = dir.appendingPathComponent(ref.fileName)
                do {
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        throw NSError(domain: "TonePilot", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "\(ref.fileName) is not installed"])
                    }
                    try slot.sampler.loadSoundBankInstrument(at: url, program: ref.program,
                                                             bankMSB: ref.bankMSB, bankLSB: ref.bankLSB)
                    loaded.append((slot, ref))
                } catch {
                    loaded.append((slot, nil))
                    failures.append("\(name): \(error.localizedDescription)")
                }
            }
            // Slot bookkeeping is main-thread state.
            DispatchQueue.main.async {
                for (slot, ref) in loaded { slot.loadedPreset = ref }
                completion(failures)
            }
        }
    }

    // MARK: Real-time commands (MIDI thread)

    func perform(_ commands: [SoundCommand]) {
        guard !commands.isEmpty else { return }
        routingLock.lock()
        let map = routing
        routingLock.unlock()
        for command in commands {
            switch command {
            case let .start(layerId, note, velocity):
                map[layerId]?.startNote(note, withVelocity: velocity, onChannel: 0)
            case let .stop(layerId, note):
                map[layerId]?.stopNote(note, onChannel: 0)
            case let .sustain(layerId, on):
                map[layerId]?.sendController(MIDIController.sustain, withValue: on ? 127 : 0, onChannel: 0)
            case let .controller(layerId, cc, value):
                map[layerId]?.sendController(cc, withValue: value, onChannel: 0)
            case let .pitchBend(layerId, value):
                map[layerId]?.sendPitchBend(value, onChannel: 0)
            case .allNotesOff:
                allNotesOff()
            }
        }
    }

    /// Silences every slot, including notes started under a previous arrangement.
    func allNotesOff() {
        for slot in slots {
            slot.sampler.sendController(MIDIController.sustain, withValue: 0, onChannel: 0)
            slot.sampler.sendController(MIDIController.allNotesOff, withValue: 0, onChannel: 0)
            slot.sampler.sendController(MIDIController.allSoundOff, withValue: 0, onChannel: 0)
            for note in UInt8(0)...UInt8(127) { slot.sampler.stopNote(note, onChannel: 0) }
        }
    }

    // MARK: Metering

    private func installMeter() {
        var lastPublish = Date.distantPast
        limiter.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            guard let data = buffer.floatChannelData else { return }
            var peak: Float = 0
            for ch in 0..<Int(buffer.format.channelCount) {
                let p = data[ch]
                for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(p[i])) }
            }
            let now = Date()
            guard now.timeIntervalSince(lastPublish) > 0.05 else { return }
            lastPublish = now
            DispatchQueue.main.async { self?.onMeter?(min(peak, 1), peak >= 0.99) }
        }
    }
}
