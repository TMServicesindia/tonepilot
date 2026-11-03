import XCTest
@testable import TonePilotCore

/// Phase 3: the hook (signature BGM line or sung hook) and section moods, as labelled suggestions with
/// their own confidences; the main tone comes from the hook; your hook choice survives re-analysis.
final class SongUnderstandingTests: XCTestCase {
    static let calm = SectionTimbre(centroid: 1100, onsetRate: 1.0, lowEnergyShare: 0.2, highEnergyShare: 0.02, sustain: 0.75, loudness: 0.05)
    static let loud = SectionTimbre(centroid: 2700, onsetRate: 6.0, lowEnergyShare: 0.4, highEnergyShare: 0.2, sustain: 0.35, loudness: 0.3)

    /// A Hukum-like song: a signature instrumental line (intro + interludes, no singing), sung verses and choruses.
    func song() -> Song {
        func s(_ type: SectionType, _ label: String, _ start: Double, group: String, lead: Double, vocal: Double, _ t: SectionTimbre) -> SongSection {
            var x = SongSection(type: type, startTime: start, endTime: start + 15, provenance: .algorithm)
            x.label = label; x.repetitionGroup = group; x.timbre = t
            x.activity = [SectionActivity(role: .lead, level: lead, evidence: "t", source: .stems),
                          SectionActivity(role: .vocalMelody, level: vocal, evidence: "t", source: .stems),
                          SectionActivity(role: .percussion, level: t.loudness > 0.2 ? 0.9 : 0.2, evidence: "t", source: .stems)]
            x.key = Estimate(MusicalKey(tonic: 9, mode: .minor), confidence: 0.8, provenance: .algorithm)
            return x
        }
        let sections = [s(.intro, "Intro BGM", 0, group: "A", lead: 0.85, vocal: 0.05, Self.loud),
                        s(.verse, "Pallavi", 15, group: "B", lead: 0.2, vocal: 0.85, Self.calm),
                        s(.interlude, "BGM", 30, group: "A", lead: 0.85, vocal: 0.05, Self.loud),
                        s(.chorus, "Charanam", 45, group: "C", lead: 0.3, vocal: 0.9, Self.loud),
                        s(.interlude, "BGM", 60, group: "A", lead: 0.8, vocal: 0.1, Self.loud),
                        s(.verse, "Pallavi", 75, group: "B", lead: 0.2, vocal: 0.85, Self.calm)]
        var song = Song(title: "Hook test", sections: sections)
        song.melody = MelodyTrack(notes: (0..<100).map { MelodyNote(start: Double($0) * 0.9, duration: 0.6, midi: 62 + $0 % 7, confidence: 0.8) },
                                  source: .vocalStem, voicedRatio: 0.8)
        return song
    }

    func testFindsTheSignatureBGMLineAndTakesTheMainToneFromIt() throws {
        let out = AutoArranger.arrange(song(), patches: FactoryPatches.all).song
        let u = try XCTUnwrap(out.understanding)
        let hook = try XCTUnwrap(u.hook)
        let hookSection = try XCTUnwrap(out.sections.first { $0.id == hook.sectionId })
        XCTAssertEqual(hookSection.repetitionGroup, "A", "the instrumental line heard 3× is the hook")
        XCTAssertEqual(hook.kind, .bgm)
        XCTAssertGreaterThan(hook.confidence, 0); XCTAssertLessThanOrEqual(hook.confidence, 1)
        XCTAssertFalse(hook.alternatives.isEmpty)
        let main = try XCTUnwrap(out.arrangements.first { $0.name == "Main tone" && $0.origin != .aiOriginal })
        XCTAssertTrue(main.rationale?.contains("hook") == true, "the main tone says it comes from the hook")
        XCTAssertEqual(main.layers.map(\.patchId), out.arrangement(for: hookSection)?.layers.map(\.patchId), "main tone = the hook section's tone")
    }

    func testYourHookChoiceSurvivesReanalysis() throws {
        var s = AutoArranger.arrange(song(), patches: FactoryPatches.all).song
        let pallavi = try XCTUnwrap(s.sections.first { $0.label == "Pallavi" })
        s.understanding?.hook = .init(sectionId: pallavi.id, kind: .vocal, confidence: 1, reason: "chosen", alternatives: [], chosenByUser: true)
        let again = AutoArranger.arrange(s, patches: FactoryPatches.all).song
        XCTAssertEqual(again.understanding?.hook?.sectionId, pallavi.id)
        XCTAssertTrue(again.understanding?.hook?.chosenByUser == true)
    }

    func testMoodsAreLabelledSuggestionsWithTheirOwnConfidence() throws {
        let s = song()
        let u = SongUnderstanding.analyse(s)
        let calm = try XCTUnwrap(u.moods[s.sections[1].id.uuidString]), loud = try XCTUnwrap(u.moods[s.sections[0].id.uuidString])
        XCTAssertLessThan(calm.energy, loud.energy)
        XCTAssertEqual(calm.label, "tender, melancholic", "quiet + minor")
        XCTAssertTrue(["intense, dramatic", "energetic, celebratory"].contains(loud.label))
        XCTAssertTrue((0...1).contains(calm.confidence) && (0...1).contains(loud.confidence))
        XCTAssertNotNil(u.overall)
    }
}
