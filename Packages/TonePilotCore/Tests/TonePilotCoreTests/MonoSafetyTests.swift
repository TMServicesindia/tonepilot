import XCTest
@testable import TonePilotCore

/// Mono (legato) tones never leave a note stuck: chords play as chords, every voice of a key
/// glides together, and a tone change or a lost release can't make a key "come back".
final class MonoSafetyTests: XCTestCase {
    let sr = 48_000.0

    func engine() -> ToneEngine {
        let e = ToneEngine(sampleRate: sr)
        var m = EngineMasterConfig()
        m.gain = 1; m.reverbLevel = 0; m.chorusLevel = 0; m.delayLevel = 0
        e.send(.setMaster(m))
        return e
    }

    func render(_ e: ToneEngine, seconds: Double) -> [Float] {
        let total = Int(seconds * sr), block = 256
        var out = [Float](repeating: 0, count: total)
        var l = [Float](repeating: 0, count: block), r = l
        var f = 0
        while f < total {
            let n = min(block, total - f)
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in e.render(frames: n, left: lp.baseAddress!, right: rp.baseAddress!) } }
            for i in 0..<n { out[f + i] = l[i] }
            f += n
        }
        return out
    }

    func monoSynth(handle: UInt32 = 1, glide: Float = 0.05) -> EngineCommand {
        var c = EngineLayerConfig()
        c.handle = handle; c.isSynth = true; c.synthWave = 0; c.synthDetune = 0; c.gain = 0.5; c.sendReverb = 0
        c.envOverride = true; c.attack = 0.005; c.decay = 0.1; c.sustain = 1; c.release = 0.05
        c.mono = true; c.glideTime = glide
        return .setSlot(index: 0, config: c)
    }

    /// Two regions per key, like GeneralUser's stereo/layered presets.
    func monoTwoVoicesPerKey() throws -> (EngineCommand, LoadedInstrument, UnsafeMutableBufferPointer<Region>) {
        let inst = try LoadedInstrument(bank: SoundFontBank(data: TestSoundFont.make(), name: "t"), bankNumber: 0, program: 0)
        let doubled = UnsafeMutableBufferPointer<Region>.allocate(capacity: 2)
        doubled[0] = inst.regions[0]; doubled[1] = inst.regions[0]
        var c = EngineLayerConfig()
        c.handle = 1; c.regions = UnsafePointer(doubled.baseAddress); c.regionCount = 2
        c.samples = inst.samples.baseAddress; c.sampleCount = inst.samples.count
        c.gain = 0.4; c.sendReverb = 0; c.mono = true; c.glideTime = 0.05
        c.envOverride = true; c.attack = 0.005; c.decay = 0.1; c.sustain = 1; c.release = 0.05
        return (.setSlot(index: 0, config: c), inst, doubled)
    }

    func testEveryVoiceOfAKeyGlidesTogetherAndNothingSticks() throws {
        let (cmd, inst, doubled) = try monoTwoVoicesPerKey()
        defer { doubled.deallocate(); _ = inst }
        let e = engine()
        e.send(cmd)
        e.send(.noteOn(handle: 1, note: 69, velocity: 110))
        _ = render(e, seconds: 0.2)
        XCTAssertEqual(e.activeVoiceCount, 2, "two voices for the key")
        e.send(.noteOn(handle: 1, note: 71, velocity: 110))   // legato
        let mid = render(e, seconds: 0.4)
        XCTAssertEqual(e.activeVoiceCount, 2, "both voices moved, no third one")
        XCTAssertEqual(Measure.frequency(mid, sampleRate: sr, range: 9600..<19_200), 441 * pow(2, 2.0 / 12), accuracy: 6, "both on the new key, not one left behind")
        e.send(.noteOff(handle: 1, note: 69))
        e.send(.noteOff(handle: 1, note: 71))
        _ = render(e, seconds: 0.5)
        XCTAssertEqual(e.activeVoiceCount, 0, "nothing keeps sounding after both keys are up")
    }

    func testChordOnAMonoToneSoundsAsAChordAndReleasesCleanly() {
        let e = engine()
        e.send(monoSynth())
        for n: UInt8 in [60, 64, 67] { e.send(.noteOn(handle: 1, note: n, velocity: 100)) }
        _ = render(e, seconds: 0.3)
        XCTAssertGreaterThanOrEqual(e.activeVoiceCount, 2, "a chord isn't squeezed into one gliding voice")
        // Released in any order: nothing glides back to a key that's up.
        for n: UInt8 in [64, 60, 67] { e.send(.noteOff(handle: 1, note: n)) }
        _ = render(e, seconds: 0.5)
        XCTAssertEqual(e.activeVoiceCount, 0)
    }

    func testToneChangeWhileHoldingDoesNotBringAKeyBack() {
        let e = engine()
        e.send(monoSynth())
        e.send(.noteOn(handle: 1, note: 60, velocity: 100))
        _ = render(e, seconds: 0.1)
        e.send(monoSynth())                                   // tone/section switch while held
        e.send(.noteOn(handle: 1, note: 62, velocity: 100))
        _ = render(e, seconds: 0.1)
        e.send(.noteOff(handle: 1, note: 62))
        e.send(.noteOff(handle: 1, note: 60))
        _ = render(e, seconds: 0.5)
        XCTAssertEqual(e.activeVoiceCount, 0, "no key comes back after a tone change")
    }

    func testLostReleaseCannotStickTheNextNote() {
        let e = engine()
        e.send(monoSynth())
        e.send(.noteOn(handle: 1, note: 60, velocity: 100))
        _ = render(e, seconds: 0.1)
        e.send(.releaseHandle(1))                             // e.g. tone switched, key's release went elsewhere
        _ = render(e, seconds: 0.3)
        e.send(.noteOn(handle: 1, note: 65, velocity: 100))
        _ = render(e, seconds: 0.1)
        e.send(.noteOff(handle: 1, note: 65))
        _ = render(e, seconds: 0.5)
        XCTAssertEqual(e.activeVoiceCount, 0, "releasing the new key stops it (it doesn't glide back to 60)")
    }

    func testSingleLineLegatoStillGlidesAndReturns() {
        let e = engine()
        e.send(monoSynth(glide: 0.02))
        e.send(.noteOn(handle: 1, note: 57, velocity: 120))
        _ = render(e, seconds: 0.3)
        e.send(.noteOn(handle: 1, note: 69, velocity: 120))
        let up = render(e, seconds: 0.4)
        XCTAssertEqual(Measure.frequency(up, sampleRate: sr, range: 9600..<19_200), 440, accuracy: 4)
        XCTAssertEqual(e.activeVoiceCount, 1)
        e.send(.noteOff(handle: 1, note: 69))
        let back = render(e, seconds: 0.4)
        XCTAssertEqual(Measure.frequency(back, sampleRate: sr, range: 9600..<19_200), 220, accuracy: 3, "returns to the held key")
        e.send(.noteOff(handle: 1, note: 57))
        _ = render(e, seconds: 0.4)
        XCTAssertEqual(e.activeVoiceCount, 0)
    }
}
