import XCTest
@testable import TonePilotCore

final class StemTests: XCTestCase {
    func testChunksCoverTheSongAndMergeBackExactly() {
        let n = 10_007
        let input = (0..<n).map { Float(sin(Double($0) * 0.01)) }
        let plan = StemChunkPlan(total: n, chunkLength: 3000, overlap: 400)
        XCTAssertEqual(plan.chunks.count, 4)
        XCTAssertEqual(plan.chunks.first?.start, 0)
        XCTAssertEqual(plan.chunks.last?.end, n)
        var merger = StemMerger(plan: plan, trackCount: 2)
        var out: [[Float]] = [[], []]
        for c in plan.chunks {
            // "Separation" that returns the input on track 0 and its negative on track 1.
            let block = Array(input[c.start..<c.end])
            let done = merger.add(c.index, [block, block.map { -$0 }])
            out[0] += done[0]; out[1] += done[1]
        }
        XCTAssertEqual(out[0].count, n)
        XCTAssertEqual(out[1].count, n)
        for i in stride(from: 0, to: n, by: 37) {
            XCTAssertEqual(out[0][i], input[i], accuracy: 1e-5)
            XCTAssertEqual(out[1][i], -input[i], accuracy: 1e-5)
        }
    }

    func testOverlapsAreCrossFaded() {
        let plan = StemChunkPlan(total: 2000, chunkLength: 1000, overlap: 100)
        var merger = StemMerger(plan: plan, trackCount: 1)
        // Block 0 says 0, block 1 says 1: the overlap must ramp smoothly from 0 to 1.
        var out = merger.add(0, [[Float](repeating: 0, count: plan.chunks[0].length)])[0]
        out += merger.add(1, [[Float](repeating: 1, count: plan.chunks[1].length)])[0]
        XCTAssertEqual(out.count, 2000)
        XCTAssertEqual(out[899], 0)
        XCTAssertEqual(out[1000], 0.5, accuracy: 0.01)
        XCTAssertEqual(out[1100], 1)
        let steps = zip(out[900..<1100], out[901..<1101]).map { $1 - $0 }
        XCTAssertTrue(steps.allSatisfy { $0 >= 0 && $0 < 0.01 }, "no jumps")
    }

    func testStemsGiveCleanerChordsThanTheMix() throws {
        let harmonic = SyntheticSong.render(pattern: ["B", "B"], beatsPerSection: 32)   // Am Dm Em Am pads
        // A loud "singer" on notes outside the chords, which confuses chord detection on the mix.
        var voice = [Float](repeating: 0, count: harmonic.samples.count)
        let notes: [Double] = [70, 66, 73, 63]
        for i in voice.indices {
            let t = Double(i) / harmonic.sampleRate
            let m = notes[Int(t / 1.5) % notes.count]
            let f = SyntheticSong.midiFreq(m)
            voice[i] = Float(0.5 * (sin(2 * .pi * f * t) + 0.5 * sin(4 * .pi * f * t)))
        }
        let mix = AudioBuffer(samples: zip(harmonic.samples, voice).map { $0 + $1 }, sampleRate: harmonic.sampleRate)
        func accuracy(_ r: SongAnalysisResult) -> Double {
            let expected = ["Am", "Dm", "Em", "Am"]
            let section = 32 * 0.5
            var hits = 0, total = 0
            for t in stride(from: 1.0, to: 30.0, by: 0.5) {
                let want = expected[Int(t.truncatingRemainder(dividingBy: section) / (section / 4))]
                let got = r.chords.last { $0.time <= t }?.symbol
                total += 1
                if got == want { hits += 1 }
            }
            return Double(hits) / Double(total)
        }
        var opts = SongAnalyzer.Options()
        opts.extractMelody = false
        let plain = try SongAnalyzer.analyze(mix, options: opts)
        opts.stems = [.other: harmonic, .vocals: AudioBuffer(samples: voice, sampleRate: harmonic.sampleRate)]
        let separated = try SongAnalyzer.analyze(mix, options: opts)
        XCTAssertGreaterThan(accuracy(separated), 0.8, "chords from the instrument stem")
        XCTAssertGreaterThanOrEqual(accuracy(separated), accuracy(plain))
    }

    func testSeparatedDefaultsAndAIPartsFromTheRecording() {
        var song = Song(title: "S", sourceType: .importedFile, userConfirmedRights: true)
        song.sections = [SongSection(type: .intro, startTime: 0, endTime: 8),
                         SongSection(type: .verse, startTime: 8, endTime: 16),
                         SongSection(type: .interlude, startTime: 16, endTime: 24)]
        song.melody = MelodyTrack(notes: [MelodyNote(start: 1, duration: 1, midi: 72, confidence: 0.9),
                                          MelodyNote(start: 9, duration: 1, midi: 72, confidence: 0.9),
                                          MelodyNote(start: 17, duration: 1, midi: 72, confidence: 0.9)],
                                  source: .vocalStem, voicedRatio: 0.5)
        var s = AccompanimentSettings(bass: true, drums: true)
        let all: [StemInfo.Kind] = [.vocals, .drums, .bass, .other]
        SongStudio.applyStemDefaults(&s, stems: all)
        XCTAssertFalse(SongStudio.isOn(SongStudio.stem(.vocals), s), "vocals off so you can play the melody")
        XCTAssertTrue(SongStudio.isOn(SongStudio.stem(.drums), s))
        XCTAssertTrue(SongStudio.isOn(SongStudio.stem(.other), s))
        XCTAssertFalse(s.drums || s.bass, "generated extras off")
        XCTAssertEqual(s.aiPartTrack, SongStudio.stem(.other))
        XCTAssertFalse(SongStudio.aiPartsOn(s))

        // AI plays the recording's own instruments only in the intro and interlude.
        let intro = song.sections[0].id, verse = song.sections[1].id, interlude = song.sections[2].id
        s.guideSections = SongStudio.suggestedAIParts(song, source: s.aiPartTrack)
        XCTAssertEqual(s.guideSections, [intro, interlude])
        SongStudio.setAIParts(true, &s)
        let other = SongStudio.stem(.other)
        XCTAssertGreaterThan(SongStudio.effectiveLevel(other, s, section: intro), 0)
        XCTAssertEqual(SongStudio.effectiveLevel(other, s, section: verse), 0, "silent where you play")
        XCTAssertGreaterThan(SongStudio.effectiveLevel(SongStudio.stem(.drums), s, section: verse), 0, "the band keeps playing")

        // Switch the source to the vocals: the AI sings the hard sung parts.
        SongStudio.setAIPartSource(SongStudio.stem(.vocals), &s)
        XCTAssertTrue(SongStudio.aiPartsOn(s))
        XCTAssertEqual(SongStudio.suggestedAIParts(song, source: s.aiPartTrack), [verse])
        s.guideSections = [verse]
        XCTAssertGreaterThan(SongStudio.effectiveLevel(SongStudio.stem(.vocals), s, section: verse), 0)
        XCTAssertEqual(SongStudio.effectiveLevel(SongStudio.stem(.vocals), s, section: intro), 0)
        XCTAssertGreaterThan(SongStudio.effectiveLevel(other, s, section: verse), 0, "music plays normally again")

        // Or the AI melody notes.
        SongStudio.setAIPartSource(SongStudio.melody, &s)
        XCTAssertNil(s.aiPartTrack)
        XCTAssertTrue(s.melodyGuide)
    }
}
