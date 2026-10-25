import XCTest
@testable import TonePilotCore

final class SongStudioTests: XCTestCase {
    private func song(melody: Bool = true, stems: Bool = false) -> Song {
        var s = Song(title: "Test", sourceType: .importedFile, userConfirmedRights: true)
        s.beatTimes = stride(from: 0.0, to: 32, by: 0.5).map { $0 }
        s.chordGuide = [
            ChordGuideStep(time: 0, duration: 4, chord: "C", pattern: ChordGuide.pattern(root: 0), confidence: 0.9),
            ChordGuideStep(time: 4, duration: 4, chord: "Am", pattern: ChordGuide.pattern(root: 9), confidence: 0.9),
            ChordGuideStep(time: 8, duration: 4, chord: "F", pattern: ChordGuide.pattern(root: 5), confidence: 0.9),
        ]
        s.sections = [
            SongSection(type: .intro, startTime: 0, endTime: 8),
            SongSection(type: .verse, startTime: 8, endTime: 16),
            SongSection(type: .interlude, startTime: 16, endTime: 24),
        ]
        if melody {
            s.melody = MelodyTrack(notes: [
                MelodyNote(start: 1, duration: 1, midi: 72, confidence: 0.9),
                MelodyNote(start: 9, duration: 1, midi: 74, confidence: 0.9),
                MelodyNote(start: 17, duration: 1, midi: 76, confidence: 0.9),
            ], source: .fullMix, voicedRatio: 0.5)
        }
        return s
    }

    func testOnlyRealTracksAreListed() {
        let full = SongStudio.tracks(for: song(), hasAudio: true).map(\.id)
        XCTAssertEqual(full, [SongStudio.keyboard, SongStudio.original, SongStudio.drums, SongStudio.bass,
                              SongStudio.chords, SongStudio.melody, SongStudio.metronome])

        var bare = Song(title: "No analysis", sourceType: .listened, userConfirmedRights: true)
        bare.sections = []
        XCTAssertEqual(SongStudio.tracks(for: bare, hasAudio: false).map(\.id), [SongStudio.keyboard], "no fictional tracks")

        let withStems = SongStudio.tracks(for: song(), hasAudio: true, stems: [.vocals, .drums, .bass, .other])
        XCTAssertFalse(withStems.contains { $0.id == SongStudio.original }, "stems replace the full mix")
        let vocals = withStems.first { $0.id == SongStudio.stem(.vocals) }
        XCTAssertEqual(vocals?.name, "Original vocals")
        XCTAssertEqual(vocals?.kind, .audio, "a stem is audio, not editable notes")
        XCTAssertEqual(withStems.first { $0.id == SongStudio.chords }?.kind, .generated)
        XCTAssertEqual(withStems.first { $0.id == SongStudio.keyboard }?.kind, .live)
    }

    func testOnOffVolumeAndSolo() {
        var s = AccompanimentSettings()
        SongStudio.applyFirstOpenDefaults(&s, hasAudio: true)
        XCTAssertTrue(s.backingTrack, "the recording plays when you first press Play")
        XCTAssertFalse(s.anyGenerated, "generated parts stay off until chosen")
        s.backingTrack = false
        SongStudio.applyFirstOpenDefaults(&s, hasAudio: true)
        XCTAssertFalse(s.backingTrack, "first-open defaults apply only once")

        SongStudio.setOn(SongStudio.chords, true, &s)
        SongStudio.setOn(SongStudio.drums, true, &s)
        SongStudio.setLevel(SongStudio.chords, 0.3, &s)
        XCTAssertEqual(SongStudio.effectiveLevel(SongStudio.chords, s), 0.3, accuracy: 1e-9)
        SongStudio.toggleSolo(SongStudio.drums, &s)
        XCTAssertEqual(SongStudio.effectiveLevel(SongStudio.chords, s), 0, "others are silent while one is soloed")
        XCTAssertGreaterThan(SongStudio.effectiveLevel(SongStudio.drums, s), 0)
        XCTAssertEqual(SongStudio.effectiveLevel(SongStudio.keyboard, s), 1, "your keyboard is never silenced by a solo")
        SongStudio.toggleSolo(SongStudio.drums, &s)
        XCTAssertNil(s.soloTrack)
        XCTAssertEqual(SongStudio.effectiveLevel(SongStudio.chords, s), 0.3, accuracy: 1e-9)

        let vocals = SongStudio.stem(.vocals)
        SongStudio.setOn(vocals, false, &s)
        XCTAssertFalse(SongStudio.isOn(vocals, s))
        XCTAssertTrue(SongStudio.isOn(SongStudio.stem(.drums), s.with { $0.backingTrack = true }))
    }

    func testOldSettingsStillDecode() throws {
        let json = #"{"bass":true,"drums":false,"metronome":false,"melodyGuide":false,"backingTrack":true,"drumStyle":"basic","bassLevel":0.7,"drumLevel":0.6,"metronomeLevel":0.5,"guideLevel":0.6,"backingTrackLevel":0.8}"#
        let s = try JSONDecoder().decode(AccompanimentSettings.self, from: Data(json.utf8))
        XCTAssertTrue(s.bass)
        XCTAssertNil(s.chords)
        XCTAssertEqual(SongStudio.level(SongStudio.keyboard, s), 1)
    }

    func testAIPlaysOnlyChosenSections() {
        var song = song()
        let suggested = SongStudio.suggestedAIParts(song)
        XCTAssertEqual(suggested, [song.sections[0].id, song.sections[2].id], "intro and interlude, not the sung verse")
        var acc = AccompanimentSettings(melodyGuide: true)
        acc.guideSections = suggested
        song.accompaniment = acc
        let h = AccompanimentGenerator.Handles(bass: 1, drums: 2, guide: 3, metronome: 4, chords: 5)
        let events = AccompanimentGenerator.events(beats: song.beatTimes, beatsPerBar: 4, chordGuide: [], melody: song.melody!.notes,
                                                   settings: acc, handles: h, sampleRate: 1000, guideRanges: SongStudio.guideRanges(song))
        let starts = events.filter { $0.handle == 3 && $0.velocity > 0 }.map(\.frame)
        XCTAssertEqual(starts, [1000, 17_000], "the verse is left for you to play")
    }

    func testBackgroundChordsAreSmoothTriads() {
        let s = song()
        var acc = AccompanimentSettings()
        acc.chords = true
        acc.chordStyle = .pad
        let h = AccompanimentGenerator.Handles(bass: 1, drums: 2, guide: 3, metronome: 4, chords: 5)
        let events = AccompanimentGenerator.events(beats: s.beatTimes, beatsPerBar: 4, chordGuide: s.chordGuide!, melody: [],
                                                   settings: acc, handles: h, sampleRate: 1000)
        let ons = events.filter { $0.handle == 5 && $0.velocity > 0 }
        func notes(at frame: Int64) -> [Int] { ons.filter { $0.frame == frame }.map { Int($0.note) }.sorted() }
        XCTAssertEqual(notes(at: 0).map { $0 % 12 }.sorted(), [0, 4, 7], "C major")
        XCTAssertEqual(Set(notes(at: 4000).map { $0 % 12 }), [9, 0, 4], "A minor")
        XCTAssertEqual(Set(notes(at: 8000).map { $0 % 12 }), [5, 9, 0], "F major")
        // Smooth voice leading: each chord moves less than an octave in total.
        let moves = zip(notes(at: 0), notes(at: 4000)).map { abs($0 - $1) }.reduce(0, +)
        XCTAssertLessThanOrEqual(moves, 6)
        XCTAssertTrue(notes(at: 0).allSatisfy { (55...80).contains($0) }, "middle register")

        acc.chordStyle = .piano
        let piano = AccompanimentGenerator.events(beats: s.beatTimes, beatsPerBar: 4, chordGuide: s.chordGuide!, melody: [],
                                                  settings: acc, handles: h, sampleRate: 1000)
        XCTAssertEqual(Set(piano.filter { $0.handle == 5 && $0.velocity > 0 && $0.frame < 4000 }.map(\.frame)).count, 8, "struck on each beat")
    }

    func testMutingAPartKeepsTheSongRunningAndKeyboardLevelIsSeparate() throws {
        let e = ToneEngine(sampleRate: 48_000)
        let c = ToneEngineController(engine: e)
        let cache = InstrumentCache(soundFontDirectory: FileManager.default.temporaryDirectory, sampleDirectory: FileManager.default.temporaryDirectory)
        let pad = try XCTUnwrap(FactoryPatches.all.first { $0.id == FactoryPatches.warmAnalogPadId })
        XCTAssertNil(c.setAccompaniment(.chords, patch: pad, volume: 0.8, cache: cache))
        let h = AccompanimentGenerator.Handles(bass: c.accompanimentHandle(.bass), drums: c.accompanimentHandle(.drums),
                                               guide: c.accompanimentHandle(.melodyGuide), metronome: c.accompanimentHandle(.metronome),
                                               chords: c.accompanimentHandle(.chords))
        var acc = AccompanimentSettings()
        acc.chords = true
        let s = song(melody: false)
        c.setSequence(AccompanimentGenerator.events(beats: s.beatTimes, beatsPerBar: 4, chordGuide: s.chordGuide!, melody: [],
                                                    settings: SongStudio.sequencingSettings(acc), handles: h, sampleRate: 48_000))
        c.setTransport(playing: true, seconds: 0)
        func render(_ seconds: Double) -> Float {
            let n = Int(seconds * 48_000)
            var l = [Float](repeating: 0, count: n), r = l
            l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
                var done = 0
                while done < n { let k = min(512, n - done); e.render(frames: k, left: lp.baseAddress! + done, right: rp.baseAddress! + done); done += k }
            } }
            return Measure.rms(l, (n / 2)..<n)
        }
        XCTAssertGreaterThan(render(1), 0.005, "chords play")
        // Switch the part off: silent, while the song clock keeps going.
        XCTAssertNil(c.setAccompaniment(.chords, patch: nil, volume: 0, cache: cache))
        _ = render(1)
        XCTAssertLessThan(render(1), 0.0005)
        XCTAssertTrue(e.isTransportPlaying)
        XCTAssertGreaterThan(e.transportSeconds, 2.9)
        // And back on: the next chord (at 4 s) is heard.
        XCTAssertNil(c.setAccompaniment(.chords, patch: pad, volume: 0.8, cache: cache))
        XCTAssertGreaterThan(render(2), 0.005)

        // Keyboard level scales the live tone only.
        let live = Arrangement(name: "Pad", layers: [Layer(patchId: pad.id, volume: 0.8)])
        let patches = Dictionary(uniqueKeysWithValues: FactoryPatches.all.map { ($0.id, $0) })
        _ = c.apply(live, patches: patches, cache: cache)
        XCTAssertNil(c.setAccompaniment(.chords, patch: nil, volume: 0, cache: cache))
        c.setTransport(playing: false, seconds: 0)
        _ = render(3)
        let router = NoteRouter()
        c.perform(router.setArrangement(live))
        c.perform(router.handle(.noteOn(channel: 1, note: 60, velocity: 100)))
        _ = render(2)   // past the pad's slow attack
        let full = render(0.5)
        c.setMixLevels(live: 0.25, accompaniment: 1, arrangement: live)
        _ = render(0.5) // reverb from before the change fades
        let quiet = render(0.5)
        XCTAssertGreaterThan(full, 0.005)
        XCTAssertEqual(quiet / full, 0.25, accuracy: 0.08)
    }

    func testWaveformPeaks() {
        var x = [Float](repeating: 0.1, count: 1000)
        x[750] = -0.5
        let w = SongStudio.waveform(x, bins: 4)
        XCTAssertEqual(w.count, 4)
        XCTAssertEqual(w[3], 1)
        XCTAssertEqual(w[0], 0.2, accuracy: 1e-6)
    }
}

private extension AccompanimentSettings {
    func with(_ change: (inout AccompanimentSettings) -> Void) -> AccompanimentSettings { var c = self; change(&c); return c }
}
