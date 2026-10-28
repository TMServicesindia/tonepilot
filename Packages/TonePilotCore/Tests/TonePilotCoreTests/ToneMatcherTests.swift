import XCTest
@testable import TonePilotCore

/// The tone matcher finds the instrument a part was played on, its EQ, and says how close it is.
final class ToneMatcherTests: XCTestCase {
    let sr = 44_100.0

    /// A phrase: 12 notes, mixed lengths, around A4.
    let phrase: [MelodyNote] = (0..<12).map { i in
        MelodyNote(start: 0.2 + Double(i) * 0.45, duration: i % 3 == 0 ? 0.4 : 0.3, midi: [69, 71, 72, 74, 76, 74, 72, 71][i % 8], confidence: 0.9)
    }

    func synthPatches() -> [InstrumentPatch] {
        let ids: [UUID] = [FactoryPatches.supersawLeadId, FactoryPatches.warmSynthLeadId, FactoryPatches.softSynthLeadId,
                           FactoryPatches.trancePluckId, FactoryPatches.heroWhistleLeadId, FactoryPatches.retroLeadId, FactoryPatches.singingSynthLeadId]
        return ids.compactMap { id in FactoryPatches.all.first { $0.id == id } }
    }

    func instrument(_ p: InstrumentPatch) -> LoadedInstrument? { p.synth.map { LoadedInstrument(name: p.name, synth: $0) } }

    func testFindsTheInstrumentAPartWasPlayedOn() throws {
        for patch in synthPatches() {
            let target = ToneMatcher.render(patch, instrument: instrument(patch)!, notes: phrase, seconds: 6, sampleRate: sr)
            let best = try XCTUnwrap(ToneMatcher.bestMatches(target: target, notes: phrase, candidates: synthPatches(), instrument: instrument).first)
            XCTAssertEqual(best.name, patch.name, "\(patch.name) recognised")
            XCTAssertGreaterThanOrEqual(best.similarity, 0.95, "\(patch.name): \(best.similarity)")
        }
    }

    func testFitsTheEQOfABrighterOrDarkerMix() throws {
        let patch = try XCTUnwrap(synthPatches().first { $0.id == FactoryPatches.warmSynthLeadId })
        let bright = ToneMatcher.render(patch, instrument: instrument(patch)!, notes: phrase, seconds: 6, sampleRate: sr,
                                        eq: EQSettings(lowDB: -4, midDB: 0, midFrequency: 1000, highDB: 6))
        let best = try XCTUnwrap(ToneMatcher.bestMatches(target: bright, notes: phrase, candidates: [patch], instrument: instrument).first)
        XCTAssertGreaterThan(best.eq.highDB, 2, "adds treble: \(best.eq)")
        XCTAssertLessThan(best.eq.lowDB, -1, "cuts bass: \(best.eq)")
        XCTAssertGreaterThanOrEqual(best.similarity, 0.9)
    }

    /// Separated parts aren't clean: other instruments bleed in, plus noise.
    func testStillFindsTheInstrumentWithBleedAndNoise() throws {
        let saw = try XCTUnwrap(synthPatches().first { $0.id == FactoryPatches.supersawLeadId })
        let pad = try XCTUnwrap(FactoryPatches.all.first { $0.id == FactoryPatches.wideSynthPadId })
        var target = ToneMatcher.render(saw, instrument: instrument(saw)!, notes: phrase, seconds: 6, sampleRate: sr)
        let chords = [MelodyNote(start: 0, duration: 5.8, midi: 48, confidence: 1), MelodyNote(start: 0, duration: 5.8, midi: 55, confidence: 1)]
        let bed = ToneMatcher.render(pad, instrument: instrument(pad)!, notes: chords, seconds: 6, sampleRate: sr)
        var seed: UInt32 = 7
        for i in target.samples.indices {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            target.samples[i] += 0.25 * bed.samples[i] + 0.004 * (Float(seed >> 8) / 8_388_608 - 1)
        }
        let best = try XCTUnwrap(ToneMatcher.bestMatches(target: target, notes: phrase, candidates: synthPatches(), instrument: instrument).first)
        XCTAssertEqual(best.name, saw.name)
        XCTAssertGreaterThanOrEqual(best.similarity, 0.8, "\(best.similarity)")
    }

    func testDifferentInstrumentsScoreLower() throws {
        let pluck = try XCTUnwrap(synthPatches().first { $0.id == FactoryPatches.trancePluckId })
        let whistle = try XCTUnwrap(synthPatches().first { $0.id == FactoryPatches.heroWhistleLeadId })
        let target = ToneMatcher.render(pluck, instrument: instrument(pluck)!, notes: phrase, seconds: 6, sampleRate: sr)
        let m = ToneMatcher.bestMatches(target: target, notes: phrase, candidates: [whistle, pluck], instrument: instrument)
        XCTAssertEqual(m.first?.name, pluck.name)
        XCTAssertLessThan(m.last?.similarity ?? 1, 0.85, "a whistle isn't a pluck: \(m.map { ($0.name, $0.similarity) })")
    }
}

final class PartMatcherTests: XCTestCase {
    func testSongsLeadPartIsReverseEngineeredIntoTheRightHandTone() throws {
        let sr = 44_100.0
        let lead = try XCTUnwrap(FactoryPatches.all.first { $0.id == FactoryPatches.retroLeadId })
        func inst(_ p: InstrumentPatch) -> LoadedInstrument? { p.synth.map { LoadedInstrument(name: p.name, synth: $0) } }
        // 40 s song: verse 0–20, chorus 20–40. The lead part plays a hook in the chorus.
        let hook: [MelodyNote] = (0..<30).map { i in
            MelodyNote(start: 20.3 + Double(i) * 0.6, duration: i % 2 == 0 ? 0.45 : 0.3, midi: [67, 69, 71, 72, 74, 72, 71, 69][i % 8], confidence: 0.9)
        }
        let part = ToneMatcher.render(lead, instrument: inst(lead)!, notes: hook, seconds: 40, sampleRate: sr)
        var verse = SongSection(type: .verse, startTime: 0, endTime: 20, provenance: .algorithm)
        verse.timbre = SectionTimbre(centroid: 1500, onsetRate: 2, lowEnergyShare: 0.2, highEnergyShare: 0.05, sustain: 0.6, loudness: 0.05)
        var chorus = SongSection(type: .chorus, startTime: 20, endTime: 40, provenance: .algorithm)
        chorus.timbre = SectionTimbre(centroid: 2500, onsetRate: 4, lowEnergyShare: 0.3, highEnergyShare: 0.1, sustain: 0.5, loudness: 0.2)
        chorus.activity = [SectionActivity(role: .lead, level: 0.8, evidence: "t", source: .stems)]
        var song = Song(title: "Hook", sections: [verse, chorus])
        song.melody = MelodyTrack(notes: hook, source: .fullMix, voicedRatio: 0.8)

        let synths = FactoryPatches.all.filter { $0.synth != nil && $0.family == .synthLead }
        let matches = PartMatcher.match(song: song, parts: [.lead: part], patches: synths, instrument: inst)
        let m = try XCTUnwrap(matches["lead"])
        XCTAssertEqual(m.name, lead.name, "the hook's instrument is found from the audio alone")
        XCTAssertGreaterThanOrEqual(m.similarity, 0.9)
        XCTAssertEqual(m.section, chorus.label)

        song.partMatches = matches
        let out = AutoArranger.arrange(song, patches: FactoryPatches.all).song
        let a = try XCTUnwrap(out.arrangement(for: out.orderedSections[1]))
        let right = try XCTUnwrap(a.layers.first { [.lead, .motif, .vocalMelody].contains($0.role) })
        XCTAssertEqual(right.patchId, lead.id)
        XCTAssertNotNil(right.effectsOverride, "EQ and reverb fitted to the song")
        XCTAssertTrue(a.rationale?.contains("tone match") == true, a.rationale ?? "")
    }
}
