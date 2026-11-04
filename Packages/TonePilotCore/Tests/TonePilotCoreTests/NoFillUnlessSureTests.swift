import XCTest
@testable import TonePilotCore

/// Phase 4, shipped: the analysis keeps a broken-chord fill only where the song plays broken chords;
/// block chords get no fill and are listed (with what was heard) so the app can offer one anyway.
final class NoFillUnlessSureTests: XCTestCase {
    typealias D = ArpeggioPattern.Degree

    func testBrokenChordsKeepTheirPattern() throws {
        let r = ArpeggioTests.render(bpm: 96, beatsPerBar: 4, stepsPerBeat: 4, bars: 16,
                                     pattern: [(0, .root), (3, .fifth), (6, .octave), (8, .third), (11, .fifth), (14, .octave)],
                                     progression: ["C", "Am", "F", "G"])
        let arp = try XCTUnwrap(ArpeggioLearner.learnGated(.init(music: r.0, beats: r.1, beatsPerBar: 4, chords: r.2, sections: r.3)))
        XCTAssertFalse(arp.patterns.isEmpty, "a real broken-chord part keeps its fill")
        XCTAssertNil(arp.skipped)
    }

    func testBlockChordsGetNoFillAndAreListed() throws {
        // Whole chords struck together on every beat.
        let hits: [(Int, D)] = [0, 4, 8, 12].flatMap { [($0, D.root), ($0, D.third), ($0, D.fifth), ($0, D.octave)] }
        let r = ArpeggioTests.render(bpm: 96, beatsPerBar: 4, stepsPerBeat: 4, bars: 16, pattern: hits, progression: ["C", "Am", "F", "G"])
        let input = ArpeggioLearner.Input(music: r.0, beats: r.1, beatsPerBar: 4, chords: r.2, sections: r.3)
        let ungated = ArpeggioLearner.learn(input)
        let gated = ArpeggioLearner.learnGated(input)
        let ids = Set(r.3.map(\.id.uuidString))
        let filled = gated.map { Set($0.patterns.filter { !$0.value.sustained }.keys) } ?? []
        XCTAssertTrue(filled.isDisjoint(with: ids), "no broken-chord fill over block chords (ungated learner: \(ungated?.patterns.count ?? 0) fills)")
        if let gated, gated.patterns.isEmpty { XCTAssertNotNil(gated.skipped, "kept so the app can say why") }
    }

    func testSkippedSectionsFollowYourSections() throws {
        let analysed = SongSection(type: .verse, startTime: 10, endTime: 30, provenance: .algorithm)
        let mine = SongSection(type: .verse, startTime: 10.2, endTime: 30, provenance: .user)
        var new = SongArpeggio(patterns: [:], bpm: 96)
        new.skipped = [analysed.id.uuidString: AccompanimentClassifier.Kind.blockChords.rawValue]
        let merged = try XCTUnwrap(Song.mergedArpeggio(old: nil, new: new, sections: [mine], analysed: [analysed]))
        XCTAssertEqual(merged.skipped?[mine.id.uuidString], "blockChords")
        // A fill you add yourself plays even with no learned pattern.
        var arp = merged
        arp.styleChoices = [mine.id.uuidString: ArpeggioStyles.all[0].id]
        XCTAssertNotNil(arp.playable(for: mine.id))
        let back = try JSONDecoder().decode(SongArpeggio.self, from: JSONEncoder().encode(arp))
        XCTAssertEqual(back, arp)
    }
}
