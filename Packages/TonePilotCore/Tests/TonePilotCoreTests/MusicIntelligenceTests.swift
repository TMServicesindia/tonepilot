import XCTest
@testable import TonePilotCore

/// Synthetic "sung" melodies with known notes, slides and vibrato over an accompaniment.
enum SyntheticMelody {
    static let sr = 22_050.0

    /// `pitch(t)` returns a MIDI pitch (fractional allowed) or nil for silence.
    static func render(seconds: Double, vibratoCents: Double = 0, accompaniment: Bool = true,
                       pitch: (Double) -> Double?) -> AudioBuffer {
        let n = Int(seconds * sr)
        var x = [Float](repeating: 0, count: n)
        var phase = 0.0
        var env = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            if let p = pitch(t) {
                env = min(1, env + 1 / (0.02 * sr))
                let cents = p * 100 + vibratoCents * sin(2 * .pi * 5.5 * t)
                phase += 440 * pow(2, (cents - 6900) / 1200) / sr
            } else {
                env = max(0, env - 1 / (0.03 * sr))
            }
            var v = 0.0
            for h in 1...6 { v += sin(2 * .pi * phase * Double(h)) / Double(h) }
            var s = 0.25 * env * v
            if accompaniment {
                // Steady low C-major triad (C3 E3 G3) with harmonics, quieter than the lead.
                for m in [48.0, 52.0, 55.0] {
                    let f = 440 * pow(2, (m - 69) / 12)
                    s += 0.05 * (sin(2 * .pi * f * t) + 0.4 * sin(4 * .pi * f * t))
                }
            }
            x[i] = Float(s)
        }
        return AudioBuffer(samples: x, sampleRate: sr)
    }

    static let tune: [(midi: Int, start: Double, dur: Double)] = [
        (64, 0.3, 0.45), (67, 0.8, 0.45), (69, 1.3, 0.45), (67, 1.8, 0.45),
        (64, 2.3, 0.45), (62, 2.8, 0.45), (60, 3.3, 0.7), (72, 4.2, 0.6),
    ]

    static func tunePitch(_ t: Double) -> Double? {
        tune.first { t >= $0.start && t < $0.start + $0.dur }.map { Double($0.midi) }
    }
}

final class MelodyTests: XCTestCase {
    func testExtractsNotesOverAccompaniment() throws {
        let audio = SyntheticMelody.render(seconds: 5.2, pitch: SyntheticMelody.tunePitch)
        let track = try XCTUnwrap(MelodyExtractor.extract(audio))
        let found = track.notes.filter { $0.duration > 0.15 }
        XCTAssertEqual(found.map(\.midi), SyntheticMelody.tune.map(\.midi), "got \(found.map { ($0.midi, $0.start) })")
        for (n, truth) in zip(found, SyntheticMelody.tune) {
            XCTAssertEqual(n.start, truth.start, accuracy: 0.08)
            XCTAssertEqual(n.duration, truth.dur, accuracy: 0.12)
        }
        XCTAssertGreaterThan(track.voicedRatio, 0.5)
        XCTAssertEqual(track.source, .fullMix)
    }

    func testVibratoAndSlideStayInsideOneOrnamentedNote() throws {
        // 0.5 s on E4 with ±35 cent vibrato, then a 250 ms slide (meend-like) up to G4 held 0.6 s.
        let audio = SyntheticMelody.render(seconds: 2.0, vibratoCents: 35, accompaniment: false) { t in
            if t < 0.2 || t > 1.6 { return nil }
            if t < 0.7 { return 64 }
            if t < 0.95 { return 64 + 3 * (t - 0.7) / 0.25 }
            return 67
        }
        let track = try XCTUnwrap(MelodyExtractor.extract(audio))
        let main = track.notes.filter { $0.duration > 0.2 }
        XCTAssertEqual(main.map(\.midi), [64, 67], "got \(track.notes.map { ($0.midi, $0.start, $0.duration) })")
        XCTAssertTrue(main.allSatisfy(\.isOrnamented), "vibrato is kept as pitch movement")
        XCTAssertFalse(main[0].bendCents.isEmpty)
        let maxBend = main[0].bendCents.map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(maxBend, 20); XCTAssertLessThan(maxBend, 90)
    }

    func testSilenceGivesNoNotesAndTranspose() throws {
        let audio = AudioBuffer(samples: [Float](repeating: 0, count: 22_050 * 2), sampleRate: 22_050)
        XCTAssertEqual(MelodyExtractor.extract(audio)?.notes.count ?? 0, 0)
        let t = MelodyTrack(notes: [MelodyNote(start: 0, duration: 1, midi: 60, confidence: 1)], source: .user, voicedRatio: 1)
        XCTAssertEqual(t.transposed(by: 12).notes[0].midi, 72)
        XCTAssertEqual(t.range, 60...60)
    }

    func testDifficultPhrasesFlagFastOrnamentedPassages() {
        let fast: [MelodyNote] = (0..<30).map { (i: Int) -> MelodyNote in
            MelodyNote(start: Double(i) * 0.12, duration: 0.1, midi: 60 + (i % 2) * 7, confidence: 0.8, isOrnamented: i % 3 == 0)
        }
        XCTAssertFalse(MelodyExtractor.difficultPhrases(fast).isEmpty)
        let slow: [MelodyNote] = (0..<6).map { (i: Int) -> MelodyNote in MelodyNote(start: Double(i), duration: 0.9, midi: 60, confidence: 0.8) }
        XCTAssertTrue(MelodyExtractor.difficultPhrases(slow).isEmpty)
    }
}

final class ChordGuideTests: XCTestCase {
    func testChordSymbolParsing() {
        XCTAssertEqual(ChordSymbol("C")?.name, "C")
        XCTAssertEqual(ChordSymbol("Am")?.quality, .minor)
        XCTAssertEqual(ChordSymbol("F#m")?.root, 6)
        XCTAssertEqual(ChordSymbol("Bb")?.root, 10)
        XCTAssertEqual(ChordSymbol("Cmaj7")?.quality, .major)
        XCTAssertNil(ChordSymbol("N"))
        XCTAssertNil(ChordSymbol("H"))
        XCTAssertEqual(ChordSymbol("G")?.transposed(7).name, "D")
    }

    func testRootFifthRootPatternsFromTheExamples() {
        let events = [("C", 0.0), ("G", 2.0), ("Am", 4.0), ("F", 6.0)].map { ChordEvent(time: $0.1, duration: 2, symbol: $0.0, confidence: 0.9) }
        let guide = ChordGuide.build(chords: events, key: MusicalKey(tonic: 0, mode: .major))
        XCTAssertEqual(guide.map(\.patternText), ["C → G → C", "G → D → G", "A → E → A", "F → C → F"])
        for step in guide {
            XCTAssertEqual(step.pattern[1] - step.pattern[0], 7)
            XCTAssertEqual(step.pattern[2] - step.pattern[0], 12)
            XCTAssertLessThanOrEqual(step.pattern.max()!, 59, "stays under the right-hand split")
            XCTAssertGreaterThanOrEqual(step.pattern.min()!, 36, "on the Casio's 61 keys")
        }
    }

    func testUncertainPassageBecomesTonicDroneAndCorrectionWorks() {
        let events = [ChordEvent(time: 0, duration: 4, symbol: "Em", confidence: 0.3, alternatives: ["G"]),
                      ChordEvent(time: 4, duration: 2, symbol: "N", confidence: 0.1)]
        let guide = ChordGuide.build(chords: events, key: MusicalKey(tonic: 2, mode: .minor))
        XCTAssertTrue(guide.allSatisfy(\.isDrone))
        XCTAssertEqual(guide[0].patternText, "D → A → D")
        XCTAssertEqual(guide[0].alternatives, ["Em", "G"])
        let fixed = ChordGuide.correct(guide[0], to: "Bm")!
        XCTAssertEqual(fixed.patternText, "B → F# → B")
        XCTAssertTrue(fixed.userEdited)
        XCTAssertFalse(fixed.isDrone)
    }

    func testTransposeAndLookup() {
        var o = ChordGuide.Options(); o.transpose = 2
        let guide = ChordGuide.build(chords: [ChordEvent(time: 1, duration: 2, symbol: "C", confidence: 0.9)], key: nil, options: o)
        XCTAssertEqual(guide[0].chord, "D")
        XCTAssertEqual(ChordGuide.step(at: 2, in: guide)?.chord, "D")
        XCTAssertNil(ChordGuide.step(at: 3.5, in: guide))
    }

    func testChordAlternativesFromAnalysis() throws {
        let audio = SyntheticSong.render(pattern: ["A"], beatsPerSection: 32)
        let result = try SongAnalyzer.analyze(audio)
        XCTAssertFalse(result.chordGuide.isEmpty)
        XCTAssertEqual(result.chordGuide.filter { $0.duration >= 1 }.map(\.chord), ["C", "F", "G", "C"])
    }

    func testTimeSignatureFromAccentPattern() {
        let four = (0..<48).map { Float($0 % 4 == 0 ? 3 : 1) }
        let three = (0..<48).map { Float($0 % 3 == 0 ? 3 : 1) }
        XCTAssertEqual(SectionInsights.timeSignature(beatStrength: four)?.value, 4)
        XCTAssertEqual(SectionInsights.timeSignature(beatStrength: three)?.value, 3)
    }
}

final class ArrangementIntelligenceTests: XCTestCase {
    func a0HasLead(_ activity: [SectionActivity]?) -> Bool { (activity ?? []).contains { $0.role == .lead && $0.level > 0.3 } }

    func analysedSong() throws -> (Song, SongAnalysisResult) {
        // A-B-A-B: A = plucked chords (piano-like), B = sustained pad. No lead line.
        let audio = SyntheticSong.render(pattern: ["A", "B", "A", "B"], beatsPerSection: 32)
        let result = try SongAnalyzer.analyze(audio)
        var song = Song(title: "Test", sourceType: .importedFile, userConfirmedRights: true)
        song.apply(result)
        return (song, result)
    }

    func testSectionActivityDescribesWhatPlays() throws {
        let (song, _) = try analysedSong()
        let a = song.orderedSections[0].activity ?? [], b = song.orderedSections[1].activity ?? []
        XCTAssertTrue(b.contains { $0.role == .pad && $0.level > 0.6 }, "\(b)")
        XCTAssertTrue(a.contains { $0.role == .keys }, "\(a)")
        XCTAssertTrue((a + b).allSatisfy { $0.source == .mixFeatures && !$0.evidence.isEmpty })
    }

    func testAutoArrangeBuildsPlayableSectionsWithAIOriginalAndMyVersion() throws {
        let (song, result) = try analysedSong()
        let out = AutoArranger.arrange(song, timbres: result.timbres, patches: FactoryPatches.all)
        let arranged = out.song
        XCTAssertEqual(out.arranged.count, arranged.sections.count)
        for s in arranged.sections {
            let mine = try XCTUnwrap(arranged.arrangement(for: s))
            XCTAssertEqual(mine.origin, .myVersion)
            let ai = try XCTUnwrap(arranged.aiOriginal(for: s))
            XCTAssertEqual(ai.origin, .aiOriginal)
            XCTAssertEqual(ai.layers, mine.layers)
            XCTAssertFalse(ai.rationale?.isEmpty ?? true)
            // Split keyboard: something on each hand.
            XCTAssertTrue(mine.layers.contains { $0.keyRange.high < 60 }, "left-hand layer")
            XCTAssertTrue(mine.layers.contains { $0.keyRange.low >= 55 }, "right-hand layer")
            XCTAssertLessThanOrEqual(mine.layers.count, ToneEngine.liveSlotCount)
            XCTAssertTrue(mine.layers.allSatisfy { FactoryPatches.all.map(\.id).contains($0.patchId) })
        }
        // Repeated sections of the same type share one arrangement; different material differs.
        let ordered = arranged.orderedSections
        for a in ordered { for b in ordered where a.repetitionGroup == b.repetitionGroup && a.type == b.type {
            XCTAssertEqual(a.arrangementId, b.arrangementId)
        } }
        XCTAssertEqual(ordered[0].arrangementId, ordered[2].arrangementId)
        XCTAssertNotEqual(ordered[0].arrangementId, ordered[1].arrangementId)
        XCTAssertFalse(a0HasLead(ordered[0].activity), "chord roots are not mistaken for a melody")
        let padSection = arranged.arrangement(for: arranged.orderedSections[1])!
        XCTAssertTrue(padSection.layers.contains { $0.role == .pad }, "sustained section gets strings/pad")
    }

    func testMelodyDrivesLeadChoiceAndOctaveCompensation() {
        // A low, ornamented sung melody (male range) in a sustained section.
        var section = SongSection(type: .verse, startTime: 0, endTime: 10, provenance: .algorithm)
        section.activity = [SectionActivity(role: .vocalMelody, level: 0.9, evidence: "test", source: .stems),
                            SectionActivity(role: .pad, level: 0.5, evidence: "test", source: .mixFeatures)]
        section.timbre = SectionTimbre(centroid: 1400, onsetRate: 1.2, lowEnergyShare: 0.2, highEnergyShare: 0.03, sustain: 0.7, loudness: 0.2)
        var song = Song(title: "Low melody", sections: [section])
        let low: [MelodyNote] = (0..<12).map { (i: Int) -> MelodyNote in
            MelodyNote(start: Double(i) * 0.8, duration: 0.7, midi: 50 + (i % 5), confidence: 0.8, isOrnamented: i % 2 == 0)
        }
        song.melody = MelodyTrack(notes: low, source: .vocalStem, voicedRatio: 0.8)
        let out = AutoArranger.arrange(song, patches: FactoryPatches.all).song
        let a = out.arrangement(for: out.sections[0])!
        let lead = a.layers.first { $0.role == .vocalMelody }!
        XCTAssertEqual(lead.octave, -1, "played an octave up, sounds at the sung pitch")
        XCTAssertEqual(AutoArranger.guideOffset(for: a), 12)
        XCTAssertTrue([FactoryPatches.vocalLeadId, FactoryPatches.bansuriId, FactoryPatches.expressiveViolinId, FactoryPatches.expressiveShehnaiId].contains(lead.patchId),
                      "ornamented vocal line gets an expressive lead")
        XCTAssertGreaterThanOrEqual(Int(lead.keyRange.low), 55)
        XCTAssertTrue(out.toneSuggestions.contains { $0.sectionId == section.id }, "alternatives offered for preview")
    }

    func testRegenerateOneSectionLeavesOthersAndUserEditsSurviveFullRerun() throws {
        let (song, result) = try analysedSong()
        var arranged = AutoArranger.arrange(song, timbres: result.timbres, patches: FactoryPatches.all).song
        let s0 = arranged.orderedSections[0], s1 = arranged.orderedSections[1]
        // User edits section 2's My Version.
        var mine = arranged.arrangement(for: s1)!
        mine.layers[0].volume = 0.33
        mine.updatedAt = mine.createdAt.addingTimeInterval(60)
        arranged.arrangements[arranged.arrangements.firstIndex { $0.id == mine.id }!] = mine

        let rerun = AutoArranger.arrange(arranged, patches: FactoryPatches.all).song
        XCTAssertEqual(rerun.arrangement(for: rerun.sections.first { $0.id == s1.id }!)?.layers[0].volume, 0.33, "user edit kept")

        let regen = AutoArranger.arrange(rerun, patches: FactoryPatches.all, onlySection: s0.id)
        XCTAssertEqual(regen.arranged, [s0.id])
        let after = regen.song
        XCTAssertNotEqual(after.sections.first { $0.id == s0.id }!.arrangementId, s0.arrangementId, "section 1 regenerated")
        XCTAssertEqual(after.arrangement(for: after.sections.first { $0.id == s1.id }!)?.layers[0].volume, 0.33)
    }

    func testRestoreAIOriginalAndDetach() throws {
        let (song, result) = try analysedSong()
        var s = AutoArranger.arrange(song, timbres: result.timbres, patches: FactoryPatches.all).song
        let sec = s.orderedSections[0]
        let detached = try XCTUnwrap(s.detachArrangement(for: sec.id))
        XCTAssertNotEqual(detached.id, sec.arrangementId, "shared with the repeat, so copied")
        s.restoreAIOriginal(for: sec.id)
        let restored = s.arrangement(for: s.sections.first { $0.id == sec.id }!)!
        XCTAssertEqual(restored.origin, .myVersion)
        XCTAssertEqual(restored.layers, s.aiOriginal(for: s.sections.first { $0.id == sec.id }!)?.layers)
    }
}

final class PerformanceLogicTests: XCTestCase {
    let sections = [SongSection(type: .intro, startTime: 0, endTime: 10), SongSection(type: .verse, startTime: 10, endTime: 30),
                    SongSection(type: .chorus, startTime: 30, endTime: 50)]

    func testAutomaticSwitchesSlightlyBeforeBoundary() {
        var s = SectionScheduler(sections: sections, settings: SwitchingSettings(mode: .automatic, reference: .backingTrack, leadTime: 0.25))
        XCTAssertEqual(s.update(time: 0), .switchTo(sections[0].id))
        XCTAssertNil(s.update(time: 5))
        XCTAssertNil(s.update(time: 9.7))
        XCTAssertEqual(s.update(time: 9.8), .switchTo(sections[1].id))
        XCTAssertEqual(s.upcoming(after: 12)?.id, sections[2].id)
        XCTAssertEqual(s.update(time: 2), .switchTo(sections[0].id), "seeking back")
    }

    func testAssistedSuggestsAndWaitsManualDoesNothing() {
        var a = SectionScheduler(sections: sections, settings: SwitchingSettings(mode: .assisted))
        _ = a.update(time: 0)
        _ = a.confirmSuggestion()
        XCTAssertEqual(a.update(time: 12), .suggest(sections[1].id))
        XCTAssertEqual(a.confirmSuggestion(), sections[1].id)
        XCTAssertNil(a.confirmSuggestion())
        var m = SectionScheduler(sections: sections, settings: SwitchingSettings(mode: .manual))
        XCTAssertNil(m.update(time: 35))
        let noClock = SwitchingSettings(mode: .automatic, reference: .none)
        XCTAssertEqual(noClock.effectiveMode, .manual, "no song position, no automatic switching")
    }

    func testAccompanimentEvents() {
        let beats = (0..<8).map { Double($0) * 0.5 }
        let guide = [ChordGuideStep(time: 0, duration: 2, chord: "C", pattern: [48, 55, 60], confidence: 0.9),
                     ChordGuideStep(time: 2, duration: 2, chord: "G", pattern: [43, 50, 55], confidence: 0.9)]
        let melody = [MelodyNote(start: 0.1, duration: 0.4, midi: 64, confidence: 0.9)]
        let h = AccompanimentGenerator.Handles(bass: 1, drums: 2, guide: 3, metronome: 4)
        let none = AccompanimentGenerator.events(beats: beats, beatsPerBar: 4, chordGuide: guide, melody: melody,
                                                 settings: AccompanimentSettings(), handles: h, sampleRate: 48_000)
        XCTAssertTrue(none.isEmpty, "everything off by default")

        let all = AccompanimentGenerator.events(beats: beats, beatsPerBar: 4, chordGuide: guide, melody: melody,
                                                settings: AccompanimentSettings(bass: true, drums: true, metronome: true, melodyGuide: true),
                                                handles: h, sampleRate: 48_000)
        let bassOn = all.filter { $0.handle == 1 && $0.velocity > 0 }
        XCTAssertEqual(bassOn.map(\.note), [36, 43, 31, 38], "root then fifth per bar, an octave below the guide")
        XCTAssertEqual(bassOn.first?.frame, 0)
        XCTAssertEqual(all.filter { $0.handle == 4 && $0.velocity > 0 }.count, 8)
        XCTAssertEqual(all.filter { $0.handle == 3 && $0.velocity > 0 }.map(\.note), [64])
        XCTAssertTrue(all.contains { $0.handle == 2 && $0.note == 36 })
        // Time-ordered; at equal frames note-offs precede note-ons (no cut-off of a re-struck note).
        for (a, b) in zip(all, all.dropFirst()) {
            XCTAssertLessThanOrEqual(a.frame, b.frame)
            if a.frame == b.frame { XCTAssertFalse(a.velocity > 0 && b.velocity == 0 && a.bend == nil && b.bend == nil) }
        }
        XCTAssertEqual(all.filter { $0.velocity > 0 }.count, all.filter { $0.velocity == 0 }.count, "every note has a note-off")
    }

    func testAccompanimentPlaysThroughEngine() throws {
        let e = ToneEngine(sampleRate: 48_000)
        let c = ToneEngineController(engine: e)
        let cache = InstrumentCache(soundFontDirectory: FileManager.default.temporaryDirectory, sampleDirectory: FileManager.default.temporaryDirectory)
        let click = FactoryPatches.all.first { $0.id == FactoryPatches.clickId }!
        XCTAssertNil(c.setAccompaniment(.metronome, patch: click, volume: 0.8, cache: cache))
        let h = AccompanimentGenerator.Handles(bass: c.accompanimentHandle(.bass), drums: c.accompanimentHandle(.drums),
                                               guide: c.accompanimentHandle(.melodyGuide), metronome: c.accompanimentHandle(.metronome))
        c.setSequence(AccompanimentGenerator.events(beats: [0, 0.5, 1.0, 1.5], beatsPerBar: 4, chordGuide: [], melody: [],
                                                    settings: AccompanimentSettings(metronome: true), handles: h, sampleRate: 48_000))
        c.setTransport(playing: true, seconds: 0)
        var l = [Float](repeating: 0, count: 48_000), r = l
        l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
            for b in 0..<(48_000 / 500) { e.render(frames: 500, left: lp.baseAddress! + b * 500, right: rp.baseAddress! + b * 500) }
        } }
        let clicks = [0, 24_000].map { Measure.rms(l, $0..<($0 + 1200)) }
        XCTAssertTrue(clicks.allSatisfy { $0 > 0.01 }, "\(clicks)")
        XCTAssertLessThan(Measure.rms(l, 8_000..<20_000), 0.002, "silent between clicks")
    }
}

final class PresetAndSchemaTests: XCTestCase {
    func testPresetExportImport() throws {
        var lib = Library()
        lib.mergeFactoryPatches(FactoryPatches.all)
        let custom = InstrumentPatch(name: "My Veena", family: .ethnic, sourceType: .userSample,
                                     sampleZones: [SampleZone(fileName: "veena_c4.wav", rootNote: 60, keyRange: KeyRange(low: 48, high: 72))])
        lib.upsert(custom)
        let tone = Arrangement(name: "Interlude", layers: [Layer(patchId: custom.id), Layer(patchId: FactoryPatches.bansuriId)])
        let data = try PresetExchange.export([tone], from: lib)
        var other = Library()
        other.mergeFactoryPatches(FactoryPatches.all)
        let (imported, missing) = try PresetExchange.importPresets(data, into: &other)
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(missing, ["veena_c4.wav"])
        XCTAssertNotNil(other.patch(id: custom.id))
        XCTAssertEqual(other.globalArrangements.first?.layers.map(\.patchId), [custom.id, FactoryPatches.bansuriId])
        XCTAssertThrowsError(try PresetExchange.importPresets(Data("{}".utf8), into: &other))
    }

    func testVersion2LayerAndEffectsDecodeWithDefaults() throws {
        // v2 EffectSettings JSON lacks chorusMix/eq; Layer lacks the new optional fields.
        let json = #"{"reverbMix":20,"delayMix":5,"delayTime":0.3,"delayFeedback":20}"#
        let fx = try JSONDecoder().decode(EffectSettings.self, from: Data(json.utf8))
        XCTAssertEqual(fx.chorusMix, 0)
        XCTAssertTrue(fx.eq.isFlat)
        var lib = Library(songs: [Song(title: "x", arrangements: [.starterFilmStack()])])
        lib.schemaVersion = 2
        var data = try LibraryCodec.encode(lib)
        data = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\" : 3", with: "\"schemaVersion\" : 2").utf8)
        let decoded = try LibraryCodec.decode(data)
        XCTAssertEqual(decoded.schemaVersion, 3)
        XCTAssertEqual(decoded.songs[0].arrangements[0].layers.count, 3)
    }

    func testFactoryCatalogueIncludesIndianAndSynthVocabulary() {
        let names = Set(FactoryPatches.all.map(\.name))
        for n in ["Bansuri-like Flute", "Santoor-like Dulcimer", "Veena-like Pluck", "Sitar", "Shehnai", "Vocal-like Lead", "Warm Analog Pad", "Standard Drum Kit"] {
            XCTAssertTrue(names.contains(n), n)
        }
        XCTAssertTrue(FactoryPatches.all.filter { $0.sourceType == .synthesized }.allSatisfy { $0.synth != nil && $0.notes?.contains("approximation") == true })
    }
}

final class PipelineTests: XCTestCase {
    /// Accompaniment A-B-A-B plus a sung-style melody only in the A sections.
    static func songWithMelody() -> AudioBuffer {
        var acc = SyntheticSong.render(pattern: ["A", "B", "A", "B"], beatsPerSection: 32)
        let phrase = SyntheticMelody.tune
        let mel = SyntheticMelody.render(seconds: 64, vibratoCents: 15, accompaniment: false) { t in
            let local = t.truncatingRemainder(dividingBy: 32)
            guard local < 16 else { return nil } // melody only in A (0-16 s, 32-48 s)
            let p = local.truncatingRemainder(dividingBy: 5.2)
            return phrase.first { p >= $0.start && p < $0.start + $0.dur }.map { Double($0.midi + 12) }
        }
        for i in acc.samples.indices where i < mel.samples.count { acc.samples[i] = acc.samples[i] * 0.7 + mel.samples[i] * 1.6 }
        return acc
    }

    func testOneClickPipelineProducesPlayableSongAwareArrangement() throws {
        let audio = Self.songWithMelody()
        let input = Song(title: "Pipeline", sourceType: .importedFile, userConfirmedRights: true)
        let out = try SongPipeline.run(song: input, audio: audio, patches: FactoryPatches.all)
        let song = out.song
        XCTAssertEqual(song.analysisStatus, .completed)
        XCTAssertEqual(out.arrangedSections.count, song.sections.count)
        XCTAssertNotNil(song.switching)
        XCTAssertFalse(song.accompaniment!.anyGenerated, "accompaniment off by default")
        XCTAssertFalse(song.chordGuide?.isEmpty ?? true)

        let melody = try XCTUnwrap(song.melody)
        let inA = melody.notes(in: 0, 16).filter { $0.duration > 0.2 }.map(\.midi)
        XCTAssertGreaterThan(Set(inA).intersection(Set(SyntheticMelody.tune.map { $0.midi + 12 })).count, 4, "melody recovered: \(inA)")

        let ordered = song.orderedSections
        XCTAssertGreaterThanOrEqual(ordered.count, 3)
        let first = ordered[0], second = ordered[1]
        XCTAssertTrue((first.activity ?? []).contains { $0.role == .lead && $0.level > 0.3 }, "\(first.activity ?? [])")
        XCTAssertFalse((second.activity ?? []).contains { $0.role == .lead && $0.level > 0.3 }, "\(second.activity ?? [])")
        XCTAssertTrue([.interlude, .verse, .outro, .instrumentalBreak].contains(second.type))
        let leadLayer = song.arrangement(for: first)?.layers.first { $0.role == .lead || $0.role == .vocalMelody }
        XCTAssertNotNil(leadLayer, "section with melody gets a right-hand lead")
        XCTAssertNotEqual(song.arrangement(for: first)?.id, song.arrangement(for: second)?.id, "tones change with the music")

        // Re-running keeps user corrections.
        var edited = song
        edited.bpm = .user(121)
        let again = try SongPipeline.run(song: edited, audio: audio, patches: FactoryPatches.all)
        XCTAssertEqual(again.song.bpm?.value, 121)
    }
}

extension PipelineTests {
    func testServerMelodyOverrideDrivesArrangement() throws {
        let audio = SyntheticSong.render(pattern: ["A", "B", "A", "B"], beatsPerSection: 32) // no melody in the mix
        let sung: [MelodyNote] = (0..<40).map { (i: Int) -> MelodyNote in
            MelodyNote(start: Double(i) * 0.4, duration: 0.35, midi: 67 + [0, 2, 4, 2, 0][i % 5], confidence: 0.9)
        }
        let override = MelodyTrack(notes: sung, source: .vocalStem, voicedRatio: 0.9)
        let out = try SongPipeline.run(song: Song(title: "s"), audio: audio, melodyOverride: override, patches: FactoryPatches.all)
        XCTAssertEqual(out.song.melody?.source, .vocalStem)
        let first = out.song.orderedSections[0]
        XCTAssertTrue((first.activity ?? []).contains { [.lead, .vocalMelody].contains($0.role) && $0.level > 0.5 }, "\(first.activity ?? [])")
        XCTAssertNotNil(out.song.arrangement(for: first)?.layers.first { [.lead, .vocalMelody].contains($0.role) })
    }
}

extension PerformanceLogicTests {
    func testMelodyGuideReplaysOrnamentBends() throws {
        // One note A4 held 1 s whose second half is bent up +300 cents (a meend-like slide to C5).
        let bends: [Int16] = (0..<50).map { $0 < 25 ? 0 : 300 }
        let note = MelodyNote(start: 0, duration: 1.0, midi: 69, bendCents: bends, confidence: 1, isOrnamented: true)
        let e = ToneEngine(sampleRate: 48_000)
        let c = ToneEngineController(engine: e)
        let cache = InstrumentCache(soundFontDirectory: FileManager.default.temporaryDirectory, sampleDirectory: FileManager.default.temporaryDirectory)
        let sine = InstrumentPatch(name: "Guide", family: .flute, sourceType: .synthesized, envelope: Envelope(attack: 0.005, decay: 0.1, sustain: 1, release: 0.05),
                                   effects: EffectSettings(reverbMix: 0), synth: SynthSettings(waveform: .sine, detuneCents: 0))
        XCTAssertNil(c.setAccompaniment(.melodyGuide, patch: sine, volume: 0.8, cache: cache))
        let h = AccompanimentGenerator.Handles(bass: 1, drums: 2, guide: c.accompanimentHandle(.melodyGuide), metronome: 4)
        let events = AccompanimentGenerator.events(beats: [], beatsPerBar: 4, chordGuide: [], melody: [note],
                                                   settings: AccompanimentSettings(melodyGuide: true), handles: h, sampleRate: 48_000)
        XCTAssertTrue(events.contains { $0.bend != nil })
        var m = EngineMasterConfig(); m.reverbLevel = 0; m.chorusLevel = 0; m.delayLevel = 0
        e.send(.setMaster(m))
        c.setSequence(events)
        c.setTransport(playing: true, seconds: 0)
        var l = [Float](repeating: 0, count: 48_000), r = l
        l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
            for b in 0..<(48_000 / 480) { e.render(frames: 480, left: lp.baseAddress! + b * 480, right: rp.baseAddress! + b * 480) }
        } }
        XCTAssertEqual(Measure.frequency(l, sampleRate: 48_000, range: 4_800..<20_000), 440, accuracy: 3)
        XCTAssertEqual(Measure.frequency(l, sampleRate: 48_000, range: 30_000..<45_000), 440 * pow(2, 3.0 / 12), accuracy: 4, "slide replayed")
    }
}
