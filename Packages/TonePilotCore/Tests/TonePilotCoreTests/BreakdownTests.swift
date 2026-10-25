import XCTest
@testable import TonePilotCore

final class AudioFileTagsTests: XCTestCase {
    func id3v23(_ frames: [(String, String)]) -> Data {
        var body = Data()
        for (id, text) in frames {
            var payload = Data([1]) // UTF-16 with BOM
            payload.append(text.data(using: .utf16)!)
            body.append(Data(id.utf8))
            withUnsafeBytes(of: UInt32(payload.count).bigEndian) { body.append(contentsOf: $0) }
            body.append(Data([0, 0]))
            body.append(payload)
        }
        let size = body.count
        var d = Data("ID3".utf8) + Data([3, 0, 0])
        d.append(contentsOf: [UInt8((size >> 21) & 0x7F), UInt8((size >> 14) & 0x7F), UInt8((size >> 7) & 0x7F), UInt8(size & 0x7F)])
        return d + body + Data(repeating: 0xFF, count: 64) // fake audio frames
    }

    func testReadsUTF16TitleAndArtist() {
        let tags = AudioFileTags.read(id3v23([("TIT2", "Hukum - Thalaivar Alappara"), ("TPE1", "Anirudh Ravichander"), ("TALB", "Jailer")]))
        XCTAssertEqual(tags, AudioFileTags(title: "Hukum - Thalaivar Alappara", artist: "Anirudh Ravichander", album: "Jailer"))
    }

    func testMissingTagsFallBackToFilename() {
        let tags = AudioFileTags.read(Data(repeating: 0xFF, count: 500))
        XCTAssertNil(tags.title)
        XCTAssertEqual(tags.displayTitle(filename: "Hukum___Thalaivar_Alappara (320 kbps).mp3"), "Hukum Thalaivar Alappara")
        XCTAssertEqual(AudioFileTags.titleFromFilename("my-song.mp3"), "my-song")
    }

    func testID3v1Trailer() {
        var d = Data(repeating: 0xFF, count: 300)
        var tag = Data("TAG".utf8)
        func field(_ s: String, _ n: Int) -> Data { var f = Data(s.utf8.prefix(n)); f.append(Data(count: n - f.count)); return f }
        tag += field("Old Song", 30) + field("Old Artist", 30) + field("Album", 30) + Data(count: 35)
        d += tag
        let tags = AudioFileTags.read(d)
        XCTAssertEqual(tags.title, "Old Song")
        XCTAssertEqual(tags.artist, "Old Artist")
    }

    func testMalformedTagDoesNotCrash() {
        var d = Data("ID3".utf8) + Data([3, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F]) // claims a huge tag
        d += Data("TIT2".utf8) + Data([0xFF, 0xFF, 0xFF, 0xFF, 0, 0])
        XCTAssertNil(AudioFileTags.read(d).title)
    }
}

final class BreakdownTests: XCTestCase {
    func testBassLineFollowsRoots() {
        // 4 bars at 120 BPM: bass C2, G2, A2, F2 (one bar each) with harmonics.
        let sr = 22_050.0
        let roots = [36, 43, 45, 41]
        var x = [Float](repeating: 0, count: Int(sr * 8))
        for i in x.indices {
            let t = Double(i) / sr
            let m = roots[min(3, Int(t / 2))]
            let f = 440 * pow(2, Double(m - 69) / 12)
            x[i] = Float(0.3 * sin(2 * .pi * f * t) + 0.15 * sin(4 * .pi * f * t) + 0.08 * sin(6 * .pi * f * t))
        }
        let beats = stride(from: 0.0, through: 8.0, by: 0.5).map { $0 }
        let bass = BassAnalyzer.bassLine(AudioBuffer(samples: x, sampleRate: sr), beats: beats)
        XCTAssertEqual(bass.map(\.midi), roots, "got \(bass.map { ($0.midi, $0.time) })")
        XCTAssertEqual(bass.map(\.time), [0, 2, 4, 6])
        let insights = SongInsights(bassLine: bass)
        XCTAssertEqual(insights.rootMovement(from: 0, to: 8), "C → G → A → F")
    }

    func testRhythmFeelStraightVsShuffle() {
        let fr = 100.0
        let beats = stride(from: 0.0, to: 20, by: 0.5).map { $0 }
        func env(_ offbeat: Double) -> [Float] {
            var e = [Float](repeating: 0, count: 2000)
            for b in beats { e[Int(b * fr)] = 1; e[Int((b + 0.5 * offbeat) * fr)] = 0.8 }
            return e
        }
        XCTAssertTrue(RhythmAnalyzer.feel(onsetEnvelope: env(0.5), frameRate: fr, beats: beats).hasPrefix("Straight"))
        XCTAssertTrue(RhythmAnalyzer.feel(onsetEnvelope: env(2.0 / 3), frameRate: fr, beats: beats).hasPrefix("Shuffle"))
    }

    func testVoicingsUseSmoothInversions() {
        let steps = ["C", "F", "G", "Am"].enumerated().map { ChordGuideStep(time: Double($0.offset) * 2, duration: 2, chord: $0.element, pattern: [], confidence: 0.9) }
        let v = KeyboardGuide.voicings(steps)
        XCTAssertEqual(v.map(\.chord), ["C", "F", "G", "Am"])
        XCTAssertEqual(v[0].notes, ["C4", "E4", "G4"])
        XCTAssertEqual(v[1].notes, ["C4", "F4", "A4"], "F as 2nd inversion keeps the hand still")
        XCTAssertEqual(v[1].inversion, "2nd inversion")
        XCTAssertEqual(v[2].notes, ["B3", "D4", "G4"])
        XCTAssertEqual(v[3].notes, ["C4", "E4", "A4"])
    }

    func testPhrasesSplitAtGaps() {
        let notes = [0.0, 0.4, 0.8, 2.0, 2.4].map { MelodyNote(start: $0, duration: 0.35, midi: 64, confidence: 1) }
        let p = KeyboardGuide.phrases(notes, offset: 12)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p[0].keys, ["E5", "E5", "E5"])
    }

    func testClimaxAndChanges() {
        func sec(_ t: Double, _ loud: Double, _ acts: [(MusicalRole, Double)]) -> SongSection {
            var s = SongSection(type: .verse, startTime: t, endTime: t + 10)
            s.timbre = SectionTimbre(centroid: 1000, onsetRate: 2, lowEnergyShare: 0.2, highEnergyShare: 0.05, sustain: 0.5, loudness: loud)
            s.activity = acts.map { SectionActivity(role: $0.0, level: $0.1, evidence: "", source: .mixFeatures) }
            return s
        }
        let list = [sec(0, 0.1, [(.pad, 0.8)]), sec(10, 0.2, [(.pad, 0.8), (.percussion, 0.9)]), sec(20, 0.2, []), sec(30, 0.4, [(.percussion, 0.9)]), sec(40, 0.15, [])]
        XCTAssertEqual(ArrangementChanges.climaxIndex(list), 3)
        let changes = ArrangementChanges.describe(from: list[0], to: list[1])
        XCTAssertTrue(changes.contains("Percussion comes in"))
        XCTAssertTrue(changes.contains { $0.hasPrefix("Louder") })
    }

    func testFullBreakdownFromAnalysis() throws {
        let audio = PipelineTests.songWithMelody()
        let out = try SongPipeline.run(song: Song(title: "Breakdown"), audio: audio, patches: FactoryPatches.all)
        let song = out.song
        let insights = try XCTUnwrap(song.insights)
        XCTAssertTrue(Set(insights.scaleNoteNames).isSuperset(of: ["C", "E", "G"]), "\(insights.scaleNoteNames)")
        XCTAssertTrue(insights.rhythmicFeel.hasPrefix("Straight"))
        XCTAssertTrue(insights.style.contains { $0.contains("120 BPM") || $0.contains("BPM") })
        XCTAssertFalse(insights.gaps.contains("Chords"))
        XCTAssertFalse(insights.gaps.contains("Melody"))

        var lib = Library(); lib.mergeFactoryPatches(FactoryPatches.all)
        let ordered = song.orderedSections
        let guide = KeyboardGuide.build(song: song, section: ordered[0], previous: nil, library: lib)
        XCTAssertFalse(guide.chords.isEmpty)
        XCTAssertTrue(guide.leftHandPattern.contains("Root"))
        XCTAssertFalse(guide.phrases.isEmpty, "section with melody has phrases")
        XCTAssertNotNil(guide.melodyRange)
        XCTAssertTrue(guide.toneAdvice.hasPrefix("Use “"))
        XCTAssertEqual(guide.practiceSteps.count, 4)
        XCTAssertEqual(guide.changes, ["Song starts"])
    }

    func testGapsReportedForUnanalysableParts() throws {
        // Steady sine drone: no beat, no chord changes, no melody movement.
        let sr = 22_050.0
        let x = (0..<Int(sr * 12)).map { Float(0.3 * sin(2 * Double.pi * 220 * Double($0) / sr)) }
        let r = try SongAnalyzer.analyze(AudioBuffer(samples: x, sampleRate: sr))
        let gaps = try XCTUnwrap(r.insights?.gaps)
        XCTAssertTrue(gaps.contains { $0.hasPrefix("Tempo") }, "\(gaps)")
        XCTAssertTrue(gaps.contains { $0.hasPrefix("Song structure") })
        XCTAssertFalse(r.chords.isEmpty, "what could be analysed is still returned")
    }
}
