import XCTest
@testable import TonePilotCore

/// Supersaw unison, filter envelope, velocity brightness and the Film Tone Library.
final class SynthUpgradeTests: XCTestCase {
    let sr = 48_000.0

    func render(_ patch: InstrumentPatch, note: UInt8 = 60, velocity: UInt8 = 110, seconds: Double = 0.8) -> [Float] {
        let e = ToneEngine(sampleRate: sr)
        var m = EngineMasterConfig()
        m.gain = 1; m.reverbLevel = 0; m.chorusLevel = 0; m.delayLevel = 0
        e.send(.setMaster(m))
        let inst = LoadedInstrument(name: patch.name, synth: patch.synth!)
        var c = EngineLayerConfig.make(layer: Layer(patchId: patch.id, volume: 1), patch: patch, instrument: inst, handle: 1, headroomGain: 0.5)
        c.sendReverb = 0; c.sendChorus = 0; c.sendDelay = 0
        e.send(.setSlot(index: 0, config: c))
        e.send(.noteOn(handle: 1, note: note, velocity: velocity))
        let total = Int(seconds * sr), block = 256
        var out = [Float](repeating: 0, count: total)
        var bl = [Float](repeating: 0, count: block), br = [Float](repeating: 0, count: block)
        var f = 0
        while f < total {
            let n = min(block, total - f)
            bl.withUnsafeMutableBufferPointer { lp in br.withUnsafeMutableBufferPointer { rp in e.render(frames: n, left: lp.baseAddress!, right: rp.baseAddress!) } }
            for i in 0..<n { out[f + i] = bl[i] }
            f += n
        }
        return out
    }

    /// High-frequency share: RMS of the first difference over RMS of the signal (brighter = higher).
    func brightness(_ x: [Float], _ r: Range<Int>) -> Float {
        var d: [Float] = []
        for i in r.dropFirst() { d.append(x[i] - x[i - 1]) }
        return Measure.rms(d, 0..<d.count) / max(1e-9, Measure.rms(x, r))
    }

    func synthPatch(_ s: SynthSettings, filter: FilterSettings = FilterSettings()) -> InstrumentPatch {
        FactoryPatches.synth(UUID(), "test", .synthLead, s, envelope: Envelope(attack: 0.002, decay: 0.3, sustain: 1, release: 0.2),
                             filter: filter, effects: EffectSettings(reverbMix: 0), tags: [])
    }

    func testSupersawIsWideButNotLouder() {
        let pair = render(synthPatch(SynthSettings(waveform: .saw, detuneCents: 20, unison: 2)))
        let saw7 = render(synthPatch(SynthSettings(waveform: .saw, detuneCents: 20, unison: 7)))
        XCTAssertTrue(saw7.allSatisfy(\.isFinite))
        let a = Measure.rms(pair, 4800..<38_400), b = Measure.rms(saw7, 4800..<38_400)
        XCTAssertGreaterThan(b, 0.01)
        XCTAssertLessThan(b, a * 1.6, "seven oscillators are level-matched, not 3× louder")
        XCTAssertGreaterThan(b, a * 0.5)
        XCTAssertNotEqual(pair[10_000], saw7[10_000])
        XCTAssertLessThan(saw7.map(abs).max()!, 1.0)
    }

    func testFilterEnvelopeOpensOnTheAttack() {
        let p = synthPatch(SynthSettings(waveform: .saw, detuneCents: 0, unison: 1),
                           filter: FilterSettings(enabled: true, cutoff: 600, resonance: 0, envAmount: 3, envDecay: 0.15))
        let x = render(p)
        XCTAssertGreaterThan(brightness(x, 480..<4800), brightness(x, 28_800..<38_400) * 1.3, "bright attack, darker sustain")
    }

    func testHardHitsAreBrighter() {
        let p = synthPatch(SynthSettings(waveform: .saw, detuneCents: 0, unison: 1),
                           filter: FilterSettings(enabled: true, cutoff: 1500, resonance: 0, velocityBrightness: 1.5))
        let hard = render(p, velocity: 127), soft = render(p, velocity: 40)
        XCTAssertGreaterThan(brightness(hard, 4800..<38_400), brightness(soft, 4800..<38_400) * 1.2)
    }

    func testOldSavedTonesStillLoad() throws {
        let synth = try JSONDecoder().decode(SynthSettings.self, from: Data(#"{"waveform":"saw","detuneCents":7,"subLevel":0,"noise":0}"#.utf8))
        XCTAssertEqual(synth.unison, 2)
        let filter = try JSONDecoder().decode(FilterSettings.self, from: Data(#"{"enabled":true,"cutoff":2000,"resonance":3}"#.utf8))
        XCTAssertEqual(filter.envAmount, 0)
        XCTAssertEqual(filter.velocityBrightness, 0)
        let round = try JSONDecoder().decode(SynthSettings.self, from: JSONEncoder().encode(SynthSettings(unison: 7)))
        XCTAssertEqual(round.unison, 7)
    }

    func testFilmLibraryIsCompleteAndPlayable() {
        let ids = FactoryPatches.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "no duplicate ids")
        XCTAssertGreaterThanOrEqual(FactoryPatches.filmLibrary.count, 25)
        let eras = Set(FactoryPatches.libraryEras.map(\.tag))
        for p in FactoryPatches.filmLibrary {
            XCTAssertTrue((p.tags ?? []).contains { eras.contains($0) }, "\(p.name) has an era/style")
            if let program = p.soundFont?.program, p.soundFont?.bankMSB == SoundFontReference.melodicBankMSB {
                XCTAssertTrue(FactoryPatches.entries.contains { $0.0 == program } || [15, 111, 104].contains(program), "\(p.name) uses a catalogued GM program")
            }
            if p.synth != nil {
                let x = render(p, seconds: 0.4)
                XCTAssertTrue(x.allSatisfy(\.isFinite), p.name)
                XCTAssertGreaterThan(Measure.rms(x, 2400..<19_200), 0.002, "\(p.name) sounds")
                XCTAssertLessThan(x.map(abs).max()!, 1.0, "\(p.name) stays within headroom")
            }
        }
    }

    func testElectronicMassSectionUsesSupersawTones() throws {
        var section = SongSection(type: .chorus, startTime: 0, endTime: 20, provenance: .algorithm)
        section.timbre = SectionTimbre(centroid: 3200, onsetRate: 6.5, lowEnergyShare: 0.45, highEnergyShare: 0.22, sustain: 0.4, loudness: 0.3)
        section.activity = [SectionActivity(role: .vocalMelody, level: 0.8, evidence: "t", source: .stems),
                            SectionActivity(role: .percussion, level: 1, evidence: "t", source: .stems)]
        section.instruments = ["synth": 0.85, "voice": 0.7]
        var calm = SongSection(type: .verse, startTime: 20, endTime: 40, provenance: .algorithm)
        calm.timbre = SectionTimbre(centroid: 1200, onsetRate: 1, lowEnergyShare: 0.15, highEnergyShare: 0.02, sustain: 0.8, loudness: 0.04)
        var song = Song(title: "EDM mass", sections: [section, calm])
        song.melody = MelodyTrack(notes: (0..<40).map { MelodyNote(start: Double($0) * 0.9, duration: 0.6, midi: 64 + $0 % 5, confidence: 0.8) },
                                  source: .vocalStem, voicedRatio: 0.8)
        let out = AutoArranger.arrange(song, patches: FactoryPatches.all).song
        let a = try XCTUnwrap(out.arrangement(for: out.orderedSections[0]))
        let synthLeads: Set<UUID> = [FactoryPatches.anthemSupersawId, FactoryPatches.supersawLeadId, FactoryPatches.powerSawLeadId,
                                     FactoryPatches.drivenSynthBrassId, FactoryPatches.classicSynthBrassId]
        XCTAssertTrue(synthLeads.contains(try XCTUnwrap(a.layers.first { $0.role == .vocalMelody }).patchId))
        XCTAssertTrue(a.layers.contains { $0.patchId == FactoryPatches.supersawChordsId }, "left hand: supersaw chords")
    }
}
