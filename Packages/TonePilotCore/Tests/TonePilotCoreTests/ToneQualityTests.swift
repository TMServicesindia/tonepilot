import XCTest
@testable import TonePilotCore

/// AI tones for powerful (mass) songs vs calm ones, the song's own main tone, clean gain staging
/// and the drive stage.
final class ToneQualityTests: XCTestCase {
    static let calm = SectionTimbre(centroid: 1300, onsetRate: 1.0, lowEnergyShare: 0.18, highEnergyShare: 0.02, sustain: 0.75, loudness: 0.05)
    static let mass = SectionTimbre(centroid: 2600, onsetRate: 6.5, lowEnergyShare: 0.45, highEnergyShare: 0.2, sustain: 0.35, loudness: 0.3)

    /// A Hukum-like song: a calm verse and loud, percussive, brassy sections.
    func massSong(brass: Bool = true) -> Song {
        func section(_ type: SectionType, _ start: Double, _ t: SectionTimbre, powerful: Bool) -> SongSection {
            var s = SongSection(type: type, startTime: start, endTime: start + 20, provenance: .algorithm)
            s.timbre = t
            s.activity = [SectionActivity(role: .vocalMelody, level: 0.8, evidence: "test", source: .stems),
                          SectionActivity(role: .bass, level: powerful ? 0.7 : 0.3, evidence: "test", source: .stems),
                          SectionActivity(role: .percussion, level: powerful ? 0.95 : 0.2, evidence: "test", source: .stems)]
            if powerful, brass { s.instruments = ["brass": 0.8, "voice": 0.9, "synth": 0.3] }
            return s
        }
        let sections = [section(.verse, 0, Self.calm, powerful: false), section(.chorus, 20, Self.mass, powerful: true),
                        section(.verse, 40, Self.calm, powerful: false), section(.chorus, 60, Self.mass, powerful: true)]
        var song = Song(title: "Mass", sections: sections)
        let notes: [MelodyNote] = (0..<100).map { i in
            MelodyNote(start: Double(i) * 0.8, duration: 0.6, midi: 62 + (i % 7), confidence: 0.8, isOrnamented: i % 4 == 0)
        }
        song.melody = MelodyTrack(notes: notes, source: .vocalStem, voicedRatio: 0.8)
        song.arrangements = [.starterFilmStack(name: "Main tone")]
        return song
    }

    func testIntensityLevels() {
        let all = [Self.calm, Self.mass]
        XCTAssertEqual(ToneIntensity.level(ToneIntensity.value(Self.mass, song: all, percussion: 0.95)), .powerful)
        XCTAssertEqual(ToneIntensity.level(ToneIntensity.value(Self.calm, song: all, percussion: 0.2)), .soft)
    }

    func testPowerfulSectionsGetPowerfulTonesAndCalmOnesStaySoft() throws {
        let out = AutoArranger.arrange(massSong(), patches: FactoryPatches.all).song
        let chorus = try XCTUnwrap(out.arrangement(for: out.orderedSections[1]))
        let verse = try XCTUnwrap(out.arrangement(for: out.orderedSections[0]))
        let powerful: Set<UUID> = [FactoryPatches.powerBrassId, FactoryPatches.drivenSynthBrassId, FactoryPatches.powerSawLeadId,
                                   FactoryPatches.id(forProgram: 30), FactoryPatches.id(forProgram: 56)]
        let lead = try XCTUnwrap(chorus.layers.first { $0.role == .vocalMelody })
        XCTAssertTrue(powerful.contains(lead.patchId), "brass heard in a mass section → a powerful lead, not a voice imitation")
        XCTAssertTrue(chorus.layers.contains { $0.patchId == FactoryPatches.brassStabsId }, "left hand plays brass stabs")
        XCTAssertTrue(chorus.layers.contains { $0.patchId == FactoryPatches.subBassId }, "heavy low end → sub bass")
        let power: Set<UUID> = [FactoryPatches.brassStabsId, FactoryPatches.powerStringsId, FactoryPatches.subBassId]
        XCTAssertFalse(verse.layers.contains { power.contains($0.patchId) }, "calm verse keeps soft accompaniment")
    }

    func testNoVoiceImitationLeadWhenOnlyTheSingerIsHeard() throws {
        var song = massSong(brass: false)
        for i in song.sections.indices { song.sections[i].instruments = ["voice": 0.9] }
        let out = AutoArranger.arrange(song, patches: FactoryPatches.all).song
        for s in out.orderedSections {
            let lead = try XCTUnwrap(out.arrangement(for: s)?.layers.first { $0.role == .vocalMelody })
            XCTAssertNotEqual(lead.patchId, FactoryPatches.vocalLeadId)
        }
    }

    func testRepeatsKeepOneLead() {
        let out = AutoArranger.arrange(massSong(), patches: FactoryPatches.all).song
        let leads = out.orderedSections.map { s in out.arrangement(for: s)?.layers.first { $0.role == .vocalMelody }?.patchId }
        XCTAssertEqual(leads[0], leads[2], "verses share a lead")
        XCTAssertEqual(leads[1], leads[3], "choruses share a lead")
    }

    func testGainStagingKeepsHeadroom() {
        let out = AutoArranger.arrange(massSong(), patches: FactoryPatches.all).song
        for s in out.orderedSections {
            guard let a = out.arrangement(for: s) else { return XCTFail("no tone") }
            for probe: UInt8 in [48, 72] {
                let sum = a.layers.filter { $0.keyRange.contains(probe) }.reduce(0) { $0 + $1.volume }
                XCTAssertLessThanOrEqual(sum, 1.1 + 1e-9, "\(s.label) at \(probe)")
            }
        }
    }

    func testMainToneComesFromTheSongAndKeepsUserEdits() throws {
        let out = AutoArranger.arrange(massSong(), patches: FactoryPatches.all).song
        let mains = out.arrangements.filter { $0.name == "Main tone" && $0.origin != .aiOriginal }
        XCTAssertEqual(mains.count, 1, "the generic stack is replaced, not duplicated")
        let main = try XCTUnwrap(mains.first)
        XCTAssertTrue(main.rationale?.hasPrefix(AutoArranger.aiMainTonePrefix) == true)
        XCTAssertTrue(main.layers.contains { $0.patchId == FactoryPatches.brassStabsId }, "taken from the chorus (most intense)")
        XCTAssertNotEqual(Set(main.layers.map(\.patchId)), Set(Arrangement.starterFilmStack().layers.map(\.patchId)))

        // Your own main tone survives a re-run.
        var edited = out
        let i = try XCTUnwrap(edited.arrangements.firstIndex { $0.id == main.id })
        edited.arrangements[i].layers = [Layer(patchId: FactoryPatches.id(forProgram: 0), volume: 0.7)]
        edited.arrangements[i].rationale = nil
        let rerun = AutoArranger.arrange(edited, patches: FactoryPatches.all).song
        XCTAssertEqual(rerun.arrangements.first { $0.id == main.id }?.layers.map(\.patchId), [FactoryPatches.id(forProgram: 0)])

        // Edited in the editor (rationale kept, saved later) is also yours.
        var saved = out
        saved.arrangements[i].layers = [Layer(patchId: FactoryPatches.id(forProgram: 48), volume: 0.7)]
        saved.arrangements[i].updatedAt = saved.arrangements[i].createdAt.addingTimeInterval(30)
        let rerun2 = AutoArranger.arrange(saved, patches: FactoryPatches.all).song
        XCTAssertEqual(rerun2.arrangements.first { $0.id == main.id }?.layers.map(\.patchId), [FactoryPatches.id(forProgram: 48)])
        // An untouched AI main tone is refreshed in place (same id, no duplicates).
        let rerun3 = AutoArranger.arrange(out, patches: FactoryPatches.all).song
        XCTAssertEqual(rerun3.arrangements.filter { $0.name == "Main tone" && $0.origin != .aiOriginal }.map(\.id), [main.id])
    }

    func testDriveIsBoundedAndOffIsClean() {
        let n = 512
        var l = (0..<n).map { Float(sin(Double($0) * 0.05)) * 1.4 }, r = l
        let original = l
        l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
            ToneEngine.saturate(lp.baseAddress!, rp.baseAddress!, n, amount: 0.35)
        } }
        let peakIn = original.map(abs).max()!, peakOut = l.map(abs).max()!
        XCTAssertLessThan(peakOut, peakIn, "hot input is tamed, not clipped harder")
        XCTAssertLessThan(peakOut, 1.4)
        XCTAssertTrue(l.allSatisfy(\.isFinite))
        // Quiet signals pass at roughly their level (no big jumps when drive is used on soft playing).
        var ql = (0..<n).map { Float(sin(Double($0) * 0.05)) * 0.05 }, qr = ql
        ql.withUnsafeMutableBufferPointer { lp in qr.withUnsafeMutableBufferPointer { rp in
            ToneEngine.saturate(lp.baseAddress!, rp.baseAddress!, n, amount: 0.35)
        } }
        XCTAssertEqual(Double(ql.map(abs).max()!), 0.05, accuracy: 0.05)
    }

    func testLoudestSungPartsBecomeChorusWhenNothingRepeats() {
        func section(_ type: SectionType, _ start: Double, loud: Double) -> SongSection {
            var s = SongSection(type: type, startTime: start, endTime: start + 20, provenance: .algorithm)
            s.timbre = SectionTimbre(centroid: 2000, onsetRate: 3, lowEnergyShare: 0.3, highEnergyShare: 0.1, sustain: 0.5, loudness: loud)
            return s
        }
        var sections = [section(.intro, 0, loud: 0.05), section(.interlude, 20, loud: 0.1), section(.interlude, 40, loud: 0.3),
                        section(.interlude, 60, loud: 0.11), section(.interlude, 80, loud: 0.29), section(.outro, 100, loud: 0.05)]
        let lead = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, 0.8) })
        SongAnalyzer.relabelInstrumentalSections(&sections, lead: lead)
        XCTAssertEqual(sections.map(\.type), [.intro, .verse, .chorus, .verse, .chorus, .outro])
        XCTAssertEqual(sections[4].label, "\(SectionType.chorus.displayName) 2")
    }

    func testInstrumentLabelsMapToFamilies() {
        XCTAssertEqual(InstrumentEvidence.family(forLabel: "trumpet"), "brass")
        XCTAssertEqual(InstrumentEvidence.family(forLabel: "violin_fiddle"), "strings")
        XCTAssertEqual(InstrumentEvidence.family(forLabel: "synthesizer"), "synth")
        XCTAssertEqual(InstrumentEvidence.family(forLabel: "electric_guitar"), "electricGuitar")
        XCTAssertEqual(InstrumentEvidence.family(forLabel: "flute"), "flute")
        XCTAssertEqual(InstrumentEvidence.family(forLabel: "singing"), "voice")
        XCTAssertNil(InstrumentEvidence.family(forLabel: "dog_bark"))
        XCTAssertNil(InstrumentEvidence.family(forLabel: "bass_guitar"))
        XCTAssertEqual(InstrumentEvidence.family(forLabel: "electric_piano"), "piano")
    }
}
