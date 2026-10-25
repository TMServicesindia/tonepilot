import XCTest
@testable import TonePilotCore

/// Renders an audible demo through the real engine + GeneralUser GS when TONEPILOT_SF2 and
/// TONEPILOT_DEMO_OUT are set: left-hand Root→Fifth→Root on piano, right-hand melody on the
/// Bansuri-like Flute (glide + vibrato) layered with strings and a subtle celesta.
final class DemoRenderTests: XCTestCase {
    func testRenderDemo() throws {
        let env = ProcessInfo.processInfo.environment
        guard let sf2 = env["TONEPILOT_SF2"], let out = env["TONEPILOT_DEMO_OUT"] else { throw XCTSkip("demo not requested") }
        let sr = 48_000.0
        let dir = URL(fileURLWithPath: sf2).deletingLastPathComponent()
        let cache = InstrumentCache(soundFontDirectory: dir, sampleDirectory: dir)
        cache.register(bank: try SoundFontBank(url: URL(fileURLWithPath: sf2)), as: FactoryPatches.defaultSoundFontFile)
        let patches = Dictionary(uniqueKeysWithValues: FactoryPatches.all.map { ($0.id, $0) })

        let flute = Layer(patchId: FactoryPatches.bansuriId, volume: 0.85, keyRange: KeyRange(low: 60, high: 127), role: .lead)
        let strings = Layer(patchId: FactoryPatches.id(forProgram: 49), volume: 0.35, pan: 0.15, keyRange: KeyRange(low: 60, high: 127), role: .pad)
        let bell = Layer(patchId: FactoryPatches.id(forProgram: 8), volume: 0.22, pan: 0.25, octave: 1, keyRange: KeyRange(low: 64, high: 127), role: .accent)
        let piano = Layer(patchId: FactoryPatches.softPianoId, volume: 0.7, pan: -0.1, keyRange: KeyRange(low: 24, high: 59), role: .harmony)
        var master = MasterEffects(); master.reverbLevel = 1.0
        let tone = Arrangement(name: "Demo", layers: [flute, strings, bell, piano], master: master)

        let engine = ToneEngine(sampleRate: sr)
        let controller = ToneEngineController(engine: engine)
        XCTAssertEqual(controller.apply(tone, patches: patches, cache: cache), [])

        // Events: what the player's two hands would send (routed per layer like NoteRouter does).
        var events: [SequencerEvent] = []
        func play(_ layers: [Layer], _ note: Int, _ start: Double, _ dur: Double, _ vel: UInt8 = 96) {
            for l in layers where l.keyRange.contains(UInt8(note)) {
                let h = controller.handle(for: l.id)
                let n = UInt8(note + l.semitoneOffset)
                events.append(SequencerEvent(frame: Int64(start * sr), handle: h, note: n, velocity: vel))
                events.append(SequencerEvent(frame: Int64((start + dur) * sr), handle: h, note: n, velocity: 0))
            }
        }
        let beat = 0.5
        let chords = [ChordSymbol("C")!, ChordSymbol("Am")!, ChordSymbol("F")!, ChordSymbol("G")!]
        for (bar, chord) in chords.enumerated() {
            let p = ChordGuide.pattern(root: chord.root)
            let t = Double(bar) * 4 * beat
            play([piano], p[0], t, beat * 1.9, 90); play([piano], p[1], t + beat, beat * 0.95, 70); play([piano], p[2], t + 2 * beat, beat * 1.9, 80)
            play([piano], p[1], t + 3 * beat, beat * 0.95, 65)
        }
        let melody: [(Int, Double, Double)] = [(76, 0, 1), (79, 1, 0.5), (81, 1.5, 0.5), (79, 2, 1.5), (76, 3.5, 0.5),
                                                (72, 4, 1), (74, 5, 0.5), (76, 5.5, 0.5), (77, 6, 1.5), (79, 7.5, 0.6)]
        for (n, s, d) in melody {
            // Legato: overlap slightly so the mono flute glides between notes.
            play([flute, strings, bell], n, s, d + 0.04, 100)
        }
        controller.setSequence(events)
        controller.setTransport(playing: true, seconds: 0)

        let total = Int(9.5 * sr), block = 256
        var l = [Float](repeating: 0, count: total), r = l
        l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
            var f = 0
            while f < total { let n = min(block, total - f); engine.render(frames: n, left: lp.baseAddress! + f, right: rp.baseAddress! + f); f += n }
        } }
        let peak = (l + r).map(abs).max() ?? 0
        XCTAssertGreaterThan(peak, 0.05)
        XCTAssertLessThanOrEqual(peak, 0.951)
        // Interleave to a 16-bit stereo WAV.
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + total * 4)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(2); u32(UInt32(sr)); u32(UInt32(sr) * 4); u16(4); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(total * 4))
        for i in 0..<total {
            u16(UInt16(bitPattern: Int16(max(-1, min(1, l[i])) * 32_767)))
            u16(UInt16(bitPattern: Int16(max(-1, min(1, r[i])) * 32_767)))
        }
        try d.write(to: URL(fileURLWithPath: out))
        print("Demo written: \(out), peak \(peak)")
    }
}
