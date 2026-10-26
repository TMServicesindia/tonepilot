import XCTest
@testable import TonePilotCore

/// Writes a minimal valid SF2: one looped sine sample (441 Hz, period exactly 100 frames),
/// one instrument covering `keyRange`, one preset (bank 0, program 0).
enum TestSoundFont {
    static func make(rootKey: UInt8 = 69, keyRange: (UInt8, UInt8) = (0, 127), attenuationCB: Int16 = 0) -> Data {
        let rate = 44_100, frames = 44_100
        var smpl = Data()
        for i in 0..<frames {
            let v = Int16(sin(2 * Double.pi * Double(i) / 100) * 20_000)
            withUnsafeBytes(of: v.littleEndian) { smpl.append(contentsOf: $0) }
        }
        smpl.append(Data(count: 46 * 2)) // SF2 requires 46 zero samples after each sample

        func chunk(_ id: String, _ body: Data) -> Data {
            var d = Data(id.utf8)
            withUnsafeBytes(of: UInt32(body.count).littleEndian) { d.append(contentsOf: $0) }
            d.append(body)
            if body.count & 1 == 1 { d.append(0) }
            return d
        }
        func list(_ type: String, _ chunks: [Data]) -> Data { chunk("LIST", Data(type.utf8) + chunks.reduce(Data(), +)) }
        func name(_ s: String) -> Data { var d = Data(s.utf8.prefix(20)); d.append(Data(count: 20 - d.count)); return d }
        func u16(_ v: UInt16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func i16(_ v: Int16) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func u32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func gen(_ op: UInt16, _ amount: Data) -> Data { u16(op) + amount }

        let phdr: Data = [name("Test Sine"), u16(0), u16(0), u16(0), u32(0), u32(0), u32(0),
                          name("EOP"), u16(0), u16(0), u16(1), u32(0), u32(0), u32(0)].reduce(Data(), +)
        let pbag = u16(0) + u16(0) + u16(1) + u16(0)
        let pmod = Data(count: 10)
        let pgen = gen(41, u16(0)) + gen(0, u16(0))
        let inst = name("Sine Inst") + u16(0) + name("EOI") + u16(1)
        let ibag = u16(0) + u16(0) + u16(4) + u16(0)
        let imod = Data(count: 10)
        let igen: Data = [gen(43, Data([keyRange.0, keyRange.1])), gen(48, i16(attenuationCB)), gen(54, u16(1)),
                          gen(53, u16(0)), gen(0, u16(0))].reduce(Data(), +)
        let shdr: Data = [name("sine"), u32(0), u32(UInt32(frames)), u32(1000), u32(1000 + 400 * 100),
                          u32(UInt32(rate)), Data([rootKey, 0]), u16(0), u16(1),
                          name("EOS"), u32(0), u32(0), u32(0), u32(0), u32(0), Data([0, 0]), u16(0), u16(0)].reduce(Data(), +)

        let info = list("INFO", [chunk("ifil", u16(2) + u16(1))])
        let sdta = list("sdta", [chunk("smpl", smpl)])
        let pdta: Data = list("pdta", [chunk("phdr", phdr), chunk("pbag", pbag), chunk("pmod", pmod), chunk("pgen", pgen),
                                 chunk("inst", inst), chunk("ibag", ibag), chunk("imod", imod), chunk("igen", igen),
                                 chunk("shdr", shdr)])
        let body = Data("sfbk".utf8) + info + sdta + pdta
        return chunk("RIFF", body)
    }
}

enum Measure {
    /// Frequency by interpolated positive zero crossings over `range`.
    static func frequency(_ x: [Float], sampleRate: Double, range: Range<Int>) -> Double {
        var crossings: [Double] = []
        for i in max(1, range.lowerBound)..<min(x.count, range.upperBound) where x[i - 1] < 0 && x[i] >= 0 {
            let frac = Double(-x[i - 1] / (x[i] - x[i - 1]))
            crossings.append(Double(i - 1) + frac)
        }
        guard crossings.count > 2 else { return 0 }
        return Double(crossings.count - 1) / ((crossings.last! - crossings.first!) / sampleRate)
    }

    static func rms(_ x: [Float], _ range: Range<Int>) -> Float {
        let r = max(0, range.lowerBound)..<min(x.count, range.upperBound)
        guard !r.isEmpty else { return 0 }
        return (r.reduce(0) { $0 + x[$1] * x[$1] } / Float(r.count)).squareRoot()
    }
}

final class EngineTests: XCTestCase {
    let sr = 48_000.0

    /// Renders `seconds`, running `events` (frame -> action) at buffer boundaries of 256 frames.
    func render(_ engine: ToneEngine, seconds: Double, at events: [Int: () -> Void] = [:]) -> (l: [Float], r: [Float]) {
        let total = Int(seconds * sr), block = 256
        var l = [Float](repeating: 0, count: total), r = [Float](repeating: 0, count: total)
        var bl = [Float](repeating: 0, count: block), br = [Float](repeating: 0, count: block)
        var f = 0
        while f < total {
            for (frame, action) in events where frame >= f && frame < f + block { action() }
            let n = min(block, total - f)
            bl.withUnsafeMutableBufferPointer { lp in
                br.withUnsafeMutableBufferPointer { rp in engine.render(frames: n, left: lp.baseAddress!, right: rp.baseAddress!) }
            }
            for i in 0..<n { l[f + i] = bl[i]; r[f + i] = br[i] }
            f += n
        }
        return (l, r)
    }

    func dryMaster() -> EngineMasterConfig {
        var m = EngineMasterConfig()
        m.gain = 1; m.reverbLevel = 0; m.chorusLevel = 0; m.delayLevel = 0
        return m
    }

    func sineBank() throws -> SoundFontBank { try SoundFontBank(data: TestSoundFont.make(), name: "test") }

    func slot(_ inst: LoadedInstrument, handle: UInt32 = 1, configure: (inout EngineLayerConfig) -> Void = { _ in }) -> EngineCommand {
        var c = EngineLayerConfig()
        c.handle = handle
        if let s = inst.synth {
            c.isSynth = true
            c.synthWave = UInt8(SynthSettings.Waveform.allCases.firstIndex(of: s.waveform)!)
            c.synthDetune = Float(s.detuneCents)
        } else {
            c.regions = UnsafePointer(inst.regions.baseAddress); c.regionCount = inst.regionCount
            c.samples = inst.samples.baseAddress; c.sampleCount = inst.samples.count
        }
        c.sendReverb = 0
        c.gain = 0.5
        configure(&c)
        return .setSlot(index: 0, config: c)
    }

    // MARK: SoundFont parsing & pitch

    func testParsesSyntheticSoundFont() throws {
        let bank = try sineBank()
        XCTAssertEqual(bank.presets, [SoundFontPresetInfo(name: "Test Sine", bank: 0, program: 0)])
        let regions = try bank.regions(bank: 0, program: 0)
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].rootKey, 69)
        XCTAssertEqual(regions[0].loopMode, 1)
        XCTAssertEqual(regions[0].loopEnd - regions[0].loopStart, 40_000)
        XCTAssertThrowsError(try bank.regions(bank: 0, program: 5))
        XCTAssertThrowsError(try SoundFontBank(data: Data("RIFF....WAVE".utf8)))
    }

    func testRootAndTransposedPitch() throws {
        let inst = try LoadedInstrument(bank: sineBank(), bankNumber: 0, program: 0)
        for (note, expected) in [(69, 441.0), (81, 882.0), (57, 220.5)] {
            let e = ToneEngine(sampleRate: sr)
            e.send(.setMaster(dryMaster()))
            e.send(slot(inst))
            e.send(.noteOn(handle: 1, note: UInt8(note), velocity: 127))
            let out = render(e, seconds: 0.6)
            XCTAssertEqual(Measure.frequency(out.l, sampleRate: sr, range: 4800..<28_000), expected, accuracy: expected * 0.003, "note \(note)")
        }
    }

    func testLoopSustainsBeyondSampleLengthAndReleaseSilences() throws {
        let inst = try LoadedInstrument(bank: sineBank(), bankNumber: 0, program: 0)
        let e = ToneEngine(sampleRate: sr)
        e.send(.setMaster(dryMaster()))
        e.send(slot(inst))
        e.send(.noteOn(handle: 1, note: 69, velocity: 127))
        let out = render(e, seconds: 3, at: [Int(2.0 * sr): { e.send(.noteOff(handle: 1, note: 69)) }])
        XCTAssertGreaterThan(Measure.rms(out.l, Int(1.5 * sr)..<Int(1.9 * sr)), 0.05, "loop keeps the 1 s sample sounding")
        XCTAssertLessThan(Measure.rms(out.l, Int(2.6 * sr)..<Int(3 * sr)), 0.001, "released")
        XCTAssertEqual(e.activeVoiceCount, 0)
    }

    func testSustainPedalHoldsThenReleases() throws {
        let inst = try LoadedInstrument(bank: sineBank(), bankNumber: 0, program: 0)
        let e = ToneEngine(sampleRate: sr)
        e.send(.setMaster(dryMaster()))
        e.send(slot(inst))
        e.send(.sustain(handle: 1, on: true))
        e.send(.noteOn(handle: 1, note: 69, velocity: 100))
        let out = render(e, seconds: 2.5, at: [
            Int(0.3 * sr): { e.send(.noteOff(handle: 1, note: 69)) },
            Int(1.5 * sr): { e.send(.sustain(handle: 1, on: false)) },
        ])
        XCTAssertGreaterThan(Measure.rms(out.l, Int(1.0 * sr)..<Int(1.4 * sr)), 0.05, "pedal holds the note")
        XCTAssertLessThan(Measure.rms(out.l, Int(2.1 * sr)..<Int(2.5 * sr)), 0.001, "pedal up releases")
    }

    func testEnvelopeOverrideAttack() throws {
        let inst = try LoadedInstrument(bank: sineBank(), bankNumber: 0, program: 0)
        let e = ToneEngine(sampleRate: sr)
        e.send(.setMaster(dryMaster()))
        e.send(slot(inst) { $0.envOverride = true; $0.attack = 0.5; $0.decay = 0.1; $0.sustain = 1; $0.release = 0.1 })
        e.send(.noteOn(handle: 1, note: 69, velocity: 127))
        let out = render(e, seconds: 0.8)
        let early = Measure.rms(out.l, 0..<Int(0.05 * sr)), late = Measure.rms(out.l, Int(0.6 * sr)..<Int(0.7 * sr))
        XCTAssertLessThan(early, late * 0.15, "slow attack fades in")
    }

    // MARK: Synth, filter, glide, limiter

    func testSynthSinePitchAndFilter() throws {
        let sine = LoadedInstrument(name: "sine", synth: SynthSettings(waveform: .sine, detuneCents: 0))
        let e = ToneEngine(sampleRate: sr)
        e.send(.setMaster(dryMaster()))
        e.send(slot(sine))
        e.send(.noteOn(handle: 1, note: 69, velocity: 127))
        let out = render(e, seconds: 0.5)
        XCTAssertEqual(Measure.frequency(out.l, sampleRate: sr, range: 4800..<24_000), 440, accuracy: 1.5)

        func highFrequencyEnergy(cutoff: Float?) -> Float {
            let saw = LoadedInstrument(name: "saw", synth: SynthSettings(waveform: .saw, detuneCents: 0))
            let e = ToneEngine(sampleRate: sr)
            e.send(.setMaster(dryMaster()))
            e.send(slot(saw) { c in if let cutoff { c.filterOverride = true; c.cutoff = cutoff } })
            e.send(.noteOn(handle: 1, note: 57, velocity: 127))
            let x = render(e, seconds: 0.4).l
            // First difference emphasises high frequencies.
            return Measure.rms((1..<x.count).map { x[$0] - x[$0 - 1] }, 4800..<19_000)
        }
        XCTAssertLessThan(highFrequencyEnergy(cutoff: 600), highFrequencyEnergy(cutoff: nil) * 0.3)
    }

    func testMonoLegatoGlidesAndReturnsToHeldNote() throws {
        let sine = LoadedInstrument(name: "sine", synth: SynthSettings(waveform: .sine, detuneCents: 0))
        let e = ToneEngine(sampleRate: sr)
        e.send(.setMaster(dryMaster()))
        e.send(slot(sine) { $0.mono = true; $0.glideTime = 0.3 })
        e.send(.noteOn(handle: 1, note: 57, velocity: 127)) // 220 Hz
        let out = render(e, seconds: 2.0, at: [
            Int(0.5 * sr): { e.send(.noteOn(handle: 1, note: 69, velocity: 127)) }, // legato to 440 Hz
            Int(1.2 * sr): { e.send(.noteOff(handle: 1, note: 69)) },              // back to held 57
        ])
        let mid = Measure.frequency(out.l, sampleRate: sr, range: Int(0.53 * sr)..<Int(0.58 * sr))
        XCTAssertGreaterThan(mid, 230); XCTAssertLessThan(mid, 430)
        XCTAssertEqual(Measure.frequency(out.l, sampleRate: sr, range: Int(0.95 * sr)..<Int(1.15 * sr)), 440, accuracy: 4)
        XCTAssertEqual(Measure.frequency(out.l, sampleRate: sr, range: Int(1.75 * sr)..<Int(1.95 * sr)), 220, accuracy: 3)
        XCTAssertLessThanOrEqual(e.activeVoiceCount, 1, "mono layer never stacks voices")
    }

    func testPitchBend() throws {
        let sine = LoadedInstrument(name: "sine", synth: SynthSettings(waveform: .sine, detuneCents: 0))
        let e = ToneEngine(sampleRate: sr)
        e.send(.setMaster(dryMaster()))
        e.send(slot(sine) { $0.bendRange = 2 })
        e.send(.noteOn(handle: 1, note: 69, velocity: 127))
        e.send(.pitchBend(handle: 1, value: 16_383))
        let out = render(e, seconds: 0.5)
        XCTAssertEqual(Measure.frequency(out.l, sampleRate: sr, range: 4800..<24_000), 440 * pow(2, 2.0 / 12 * 8191 / 8192), accuracy: 2)
    }

    func testLimiterPreventsClipping() {
        let e = ToneEngine(sampleRate: sr)
        var m = EngineMasterConfig(); m.gain = 1
        e.send(.setMaster(m))
        for s in 0..<8 {
            let saw = LoadedInstrument(name: "saw\(s)", synth: SynthSettings(waveform: .square, detuneCents: 5))
            var c = EngineLayerConfig()
            c.handle = UInt32(s + 1); c.isSynth = true; c.synthWave = 3; c.gain = 1; c.sendReverb = 0.5
            _ = saw
            e.send(.setSlot(index: s, config: c))
            for n in stride(from: 48, to: 84, by: 4) { e.send(.noteOn(handle: UInt32(s + 1), note: UInt8(n), velocity: 127)) }
        }
        let out = render(e, seconds: 0.5)
        let peak = (out.l + out.r).map(abs).max()!
        XCTAssertLessThanOrEqual(peak, 0.951)
        XCTAssertTrue(e.limiterEngaged)
    }

    // MARK: Sequencer & controller

    func testSequencerIsSampleAccurate() throws {
        let sine = LoadedInstrument(name: "sine", synth: SynthSettings(waveform: .sine, detuneCents: 0))
        let e = ToneEngine(sampleRate: sr)
        let controller = ToneEngineController(engine: e)
        e.send(.setMaster(dryMaster()))
        let h = controller.accompanimentHandle(.bass)
        var c = EngineLayerConfig(); c.handle = h; c.isSynth = true; c.synthWave = 0; c.sendReverb = 0
        c.envOverride = true; c.attack = 0.001; c.decay = 0.1; c.sustain = 1; c.release = 0.01
        c.isAccompaniment = true
        _ = sine
        e.send(.setSlot(index: ToneEngine.AccompanimentSlot.bass.rawValue, config: c))
        controller.setSequence([SequencerEvent(frame: 10_000, handle: h, note: 45, velocity: 100),
                                SequencerEvent(frame: 20_000, handle: h, note: 45, velocity: 0)])
        controller.setTransport(playing: true, seconds: 0)
        let out = render(e, seconds: 1)
        let first = out.l.firstIndex { abs($0) > 1e-6 }!
        XCTAssertEqual(first, 10_000, accuracy: 1)
        XCTAssertLessThan(Measure.rms(out.l, 22_000..<48_000), 1e-4)
        XCTAssertEqual(e.transportSeconds, 1, accuracy: 0.01)
    }

    func testTransportStopReleasesAccompanimentOnly() throws {
        let e = ToneEngine(sampleRate: sr)
        let controller = ToneEngineController(engine: e)
        e.send(.setMaster(dryMaster()))
        let bassH = controller.accompanimentHandle(.bass)
        var bass = EngineLayerConfig(); bass.handle = bassH; bass.isSynth = true; bass.isAccompaniment = true; bass.sendReverb = 0
        bass.envOverride = true; bass.attack = 0.001; bass.decay = 0.1; bass.sustain = 1; bass.release = 0.02
        var live = EngineLayerConfig(); live.handle = 999; live.isSynth = true; live.sendReverb = 0
        e.send(.setSlot(index: 9 - 1, config: bass))
        e.send(.setSlot(index: 0, config: live))
        controller.setSequence([SequencerEvent(frame: 0, handle: bassH, note: 40, velocity: 100)])
        controller.setTransport(playing: true, seconds: 0)
        e.send(.noteOn(handle: 999, note: 64, velocity: 100))
        _ = render(e, seconds: 0.2)
        XCTAssertEqual(e.activeVoiceCount, 2)
        controller.setTransport(playing: false, seconds: 0.2)
        _ = render(e, seconds: 0.3)
        XCTAssertEqual(e.activeVoiceCount, 1, "live note keeps sounding when backing stops")
    }

    func testControllerKeepsHeldNotesAcrossArrangementSwitch() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try TestSoundFont.make().write(to: dir.appendingPathComponent("test.sf2"))
        let cache = InstrumentCache(soundFontDirectory: dir, sampleDirectory: dir)
        let patchA = InstrumentPatch(name: "Sine", family: .other, sourceType: .soundFont,
                                     soundFont: SoundFontReference(fileName: "test.sf2", program: 0))
        let patchB = InstrumentPatch(name: "Synth", family: .synthLead, sourceType: .synthesized, synth: SynthSettings(waveform: .sine))
        let patches = [patchA.id: patchA, patchB.id: patchB]
        let layerA = Layer(patchId: patchA.id), layerB = Layer(patchId: patchB.id)
        let e = ToneEngine(sampleRate: sr)
        let controller = ToneEngineController(engine: e)
        let router = NoteRouter()

        let arr1 = Arrangement(name: "1", layers: [layerA])
        XCTAssertEqual(controller.apply(arr1, patches: patches, cache: cache), [])
        controller.perform(router.setArrangement(arr1))
        controller.perform(router.handle(.noteOn(channel: 1, note: 69, velocity: 100)))
        _ = render(e, seconds: 0.2)

        let arr2 = Arrangement(name: "2", layers: [layerA, layerB])
        controller.apply(arr2, patches: patches, cache: cache)
        controller.perform(router.setArrangement(arr2))
        let out = render(e, seconds: 0.3)
        XCTAssertGreaterThan(Measure.rms(out.l, 0..<out.l.count), 0.01, "held note survives switch")
        XCTAssertEqual(e.activeVoiceCount, 1, "new layer doesn't start until a new key press")

        let arr3 = Arrangement(name: "3", layers: [layerB])
        controller.apply(arr3, patches: patches, cache: cache)
        controller.perform(router.setArrangement(arr3))
        _ = render(e, seconds: 1.5)
        XCTAssertEqual(e.activeVoiceCount, 0, "removed layer's note released, nothing stuck")
        controller.perform(router.handle(.noteOff(channel: 1, note: 69, velocity: 0)))
        _ = render(e, seconds: 0.1)
        XCTAssertEqual(e.activeVoiceCount, 0)

        let missing = InstrumentPatch(name: "Ghost", family: .piano, sourceType: .soundFont, soundFont: SoundFontReference(fileName: "nope.sf2", program: 0))
        let failures = controller.apply(Arrangement(name: "x", layers: [Layer(patchId: missing.id)]), patches: [missing.id: missing], cache: cache)
        XCTAssertEqual(failures.count, 1)
        XCTAssertTrue(failures[0].contains("not installed"))
    }

    func testCacheRetiresUnusedInstrumentsSafely() throws {
        let cache = InstrumentCache(soundFontDirectory: FileManager.default.temporaryDirectory, sampleDirectory: FileManager.default.temporaryDirectory)
        cache.gracePeriod = 0
        let p = InstrumentPatch(name: "Synth", family: .synthLead, sourceType: .synthesized, synth: SynthSettings())
        let inst = try cache.instrument(for: p)
        XCTAssertTrue(try cache.instrument(for: p) === inst, "cached")
        XCTAssertEqual(cache.maintenance(inUse: [ObjectIdentifier(inst)], now: Date().addingTimeInterval(5)).count, 0)
        let cmds = cache.maintenance(inUse: [], now: Date().addingTimeInterval(5))
        XCTAssertEqual(cmds.count, 1, "kill command sent before release")
        XCTAssertEqual(cache.loadedCount, 0)
    }

    // MARK: User samples

    func testWAVRoundTripAndUserSampleInstrument() throws {
        let rate = 44_100
        let frames = (0..<rate).map { Float(sin(2 * Double.pi * 261.6256 * Double($0) / Double(rate)) * 0.8) }
        let decoded = try WAVDecoder.decodeMono(data: WAVDecoder.encode16(frames, sampleRate: rate))
        XCTAssertEqual(decoded.sampleRate, 44_100)
        XCTAssertEqual(decoded.frames.count, frames.count)
        XCTAssertEqual(decoded.frames[1000], frames[1000], accuracy: 1e-4)

        let zone = SampleZone(fileName: "c4.wav", rootNote: 60, keyRange: KeyRange(low: 48, high: 72), loopStart: 1000, loopEnd: 40_000)
        let inst = LoadedInstrument(name: "user", userSamples: [.init(frames: decoded.frames, sampleRate: 44_100, zone: zone)], envelope: Envelope())
        XCTAssertEqual(inst.coveredKeys, 48...72)
        XCTAssertEqual(inst.maxStretchSemitones, 12)
        let e = ToneEngine(sampleRate: sr)
        e.send(.setMaster(dryMaster()))
        e.send(slot(inst))
        e.send(.noteOn(handle: 1, note: 67, velocity: 127))
        e.send(.noteOn(handle: 1, note: 80, velocity: 127)) // outside the mapped range: silent
        let out = render(e, seconds: 0.5)
        XCTAssertEqual(Measure.frequency(out.l, sampleRate: sr, range: 4800..<20_000), 391.995, accuracy: 1.5)
        XCTAssertEqual(e.activeVoiceCount, 1)
    }

    // MARK: Real SoundFont (runs when TONEPILOT_SF2 points at GeneralUser GS)

    func testGeneralUserGSIfAvailable() throws {
        guard let path = ProcessInfo.processInfo.environment["TONEPILOT_SF2"], FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Set TONEPILOT_SF2 to a General MIDI .sf2 to run")
        }
        let bank = try SoundFontBank(url: URL(fileURLWithPath: path))
        XCTAssertGreaterThan(bank.presets.count, 100)
        // Every factory patch must resolve in the default bank.
        for patch in FactoryPatches.generalMIDI {
            let ref = patch.soundFont!
            XCTAssertFalse(try bank.regions(bank: 0, program: Int(ref.program)).isEmpty, patch.name)
        }
        // Extended patches (incl. the GM drum kit on bank 128) load through the cache.
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        let cache = InstrumentCache(soundFontDirectory: dir, sampleDirectory: dir)
        cache.register(bank: bank, as: FactoryPatches.defaultSoundFontFile)
        for patch in FactoryPatches.extended {
            XCTAssertNoThrow(try cache.instrument(for: patch), patch.name)
        }
        XCTAssertTrue(bank.hasPreset(bank: 128, program: 0), "GM drum kit")
        let piano = try LoadedInstrument(bank: bank, bankNumber: 0, program: 0)
        let e = ToneEngine(sampleRate: sr)
        e.send(.setMaster(dryMaster()))
        e.send(slot(piano))
        e.send(.noteOn(handle: 1, note: 69, velocity: 100))
        let out = render(e, seconds: 0.6)
        XCTAssertGreaterThan(Measure.rms(out.l, 0..<out.l.count), 0.01)
        // Piano partials make zero-crossing pitch noisy; FFT peak near 440 Hz.
        let n = 16_384
        var mag: [Float] = []
        MagnitudeFFT(size: n).magnitudes(out.l, offset: 4000, into: &mag)
        let lo = Int(300.0 * Double(n) / sr), hi = Int(600.0 * Double(n) / sr)
        let peak = (lo...hi).max { mag[$0] < mag[$1] }!
        XCTAssertEqual(Double(peak) * sr / Double(n), 440, accuracy: 6)
        print("GeneralUser GS: \(bank.presets.count) presets, piano regions \(piano.regionCount)")
    }

    func testRealtimePerformanceBudget() throws {
        // 6 synth layers x 10-note chords with effects on: must render well faster than real time.
        let e = ToneEngine(sampleRate: sr, maxFrames: 512)
        e.send(.setMaster(EngineMasterConfig()))
        for s in 0..<6 {
            var c = EngineLayerConfig(); c.handle = UInt32(s + 1); c.isSynth = true; c.synthWave = 2; c.synthDetune = 7
            c.filterOverride = true; c.cutoff = 4000; c.sendReverb = 0.3; c.sendChorus = 0.2; c.sendDelay = 0.1
            c.eq = EQSettings(lowDB: 2, midDB: -2, highDB: 3)
            e.send(.setSlot(index: s, config: c))
            for n in 0..<10 { e.send(.noteOn(handle: UInt32(s + 1), note: UInt8(48 + n * 3), velocity: 100)) }
        }
        var l = [Float](repeating: 0, count: 512), r = [Float](repeating: 0, count: 512)
        let seconds = 5.0
        let start = Date()
        for _ in 0..<Int(seconds * sr / 512) {
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in e.render(frames: 512, left: lp.baseAddress!, right: rp.baseAddress!) } }
        }
        let elapsed = Date().timeIntervalSince(start)
        let factor = seconds / elapsed
        print("Realtime factor (60 voices + FX, this machine): \(String(format: "%.1f", factor))x")
        XCTAssertEqual(e.activeVoiceCount, 60)
        XCTAssertGreaterThan(factor, 1.5)
    }
}

/// Song Arpeggio's pattern player: its own looping clock, independent of the song transport.
final class PatternPlayerTests: XCTestCase {
    let sr = 48_000.0

    func render(_ e: ToneEngine, seconds: Double) -> [Float] {
        let total = Int(seconds * sr), block = 256
        var l = [Float](repeating: 0, count: total), bl = [Float](repeating: 0, count: block), br = bl
        var f = 0
        while f < total {
            let n = min(block, total - f)
            bl.withUnsafeMutableBufferPointer { lp in br.withUnsafeMutableBufferPointer { rp in e.render(frames: n, left: lp.baseAddress!, right: rp.baseAddress!) } }
            for i in 0..<n { l[f + i] = bl[i] }
            f += n
        }
        return l
    }

    func engine() -> (ToneEngine, ToneEngineController, UInt32) {
        let e = ToneEngine(sampleRate: sr)
        let c = ToneEngineController(engine: e)
        var m = EngineMasterConfig(); m.gain = 1; m.reverbLevel = 0; m.chorusLevel = 0; m.delayLevel = 0
        e.send(.setMaster(m))
        let h = c.accompanimentHandle(.arpeggio)
        var cfg = EngineLayerConfig(); cfg.handle = h; cfg.isSynth = true; cfg.synthWave = 0; cfg.sendReverb = 0
        cfg.envOverride = true; cfg.attack = 0.001; cfg.decay = 0.1; cfg.sustain = 1; cfg.release = 0.005
        e.send(.setSlot(index: ToneEngine.AccompanimentSlot.arpeggio.rawValue, config: cfg))
        return (e, c, h)
    }

    func testPlaysAndLoopsWithTheSongStopped() {
        let (e, c, h) = engine()
        // One note at 0.1–0.2 s in a 0.5 s loop; the song transport never starts.
        c.setPattern([SequencerEvent(frame: 4_800, handle: h, note: 57, velocity: 100),
                      SequencerEvent(frame: 9_600, handle: h, note: 57, velocity: 0)], loopSeconds: 0.5)
        c.setPatternPlaying(true)
        let out = render(e, seconds: 1.2)
        XCTAssertFalse(e.isTransportPlaying)
        XCTAssertEqual(out.firstIndex { abs($0) > 1e-6 }!, 4_800, accuracy: 1, "sample-accurate start")
        XCTAssertLessThan(Measure.rms(out, 12_000..<28_000), 1e-4, "silent between loop repeats")
        XCTAssertGreaterThan(Measure.rms(out, 29_000..<33_000), 0.01, "second loop plays at 0.6 s")
        XCTAssertGreaterThan(Measure.rms(out, 53_000..<57_000), 0.01, "third loop at 1.1 s")
    }

    func testSongTransportDoesNotStopIt() {
        let (e, c, h) = engine()
        c.setPattern([SequencerEvent(frame: 0, handle: h, note: 57, velocity: 100),
                      SequencerEvent(frame: 23_999, handle: h, note: 57, velocity: 0)], loopSeconds: 0.5)
        c.setPatternPlaying(true)
        _ = render(e, seconds: 0.1)
        c.setTransport(playing: true, seconds: 10)
        c.setTransport(playing: false, seconds: 10)
        let out = render(e, seconds: 0.2)
        XCTAssertGreaterThan(Measure.rms(out, 2_000..<8_000), 0.01, "playing/pausing the song leaves the arpeggio alone")
        c.setPatternPlaying(false)
        let after = render(e, seconds: 0.2)
        XCTAssertLessThan(Measure.rms(after, 4_000..<9_000), 1e-4, "stopping it releases its notes")
    }

    func testRendererPlaysPatternOnEachChord() {
        let p = ArpeggioPattern(beatsPerBar: 4, stepsPerBeat: 4,
                                hits: [.init(step: 0, degree: .root, velocity: 1, length: 2), .init(step: 4, degree: .third, velocity: 0.6, length: 2),
                                       .init(step: 8, degree: .fifth, velocity: 0.8, length: 2), .init(step: 12, degree: .octave, velocity: 0.8, length: 8)],
                                centerNote: 55)
        let bars = [ArpeggioRenderer.Bar(chord: ChordSymbol("C")), .init(chord: ChordSymbol("Am")), .init(chord: nil), .init(chord: ChordSymbol("G"), uncertain: true)]
        let (events, seconds) = ArpeggioRenderer.loop(p, bars: bars, bpm: 120, handle: 7, sampleRate: sr)
        XCTAssertEqual(seconds, 8, accuracy: 1e-9)
        let ons = events.filter { $0.velocity > 0 }.map { Int($0.note) }
        XCTAssertEqual(ons.count, 16, "bar without a chord repeats the previous one")
        XCTAssertEqual(ons[1] - ons[0], 4, "C: major third")
        XCTAssertEqual(ons[5] - ons[4], 3, "Am: minor third")
        XCTAssertEqual(Array(ons[8..<12]), Array(ons[4..<8]), "no chord: keeps Am")
        XCTAssertEqual(ons[13] - ons[12], 7, "uncertain G: fifth instead of a third")
        XCTAssertTrue(events.allSatisfy { $0.frame < Int64(seconds * sr) }, "every note ends inside the loop")
        XCTAssertTrue(ons.allSatisfy { (40...72).contains($0) }, "stays near the learned register: \(ons)")
    }
}
