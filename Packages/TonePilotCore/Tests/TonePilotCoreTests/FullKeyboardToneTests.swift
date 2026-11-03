import XCTest
@testable import TonePilotCore

/// Owner, 3 Nov: no AI key map. Every layer of an AI tone plays on all keys (61-key keyboard, no
/// octave shift), and the tone is the song's own sounds blended — the main sound plus the song's
/// accompaniment parts (backing / piano / guitar) when they were matched.
final class FullKeyboardToneTests: XCTestCase {
    func song(parts: [String: PartMatch]) -> Song {
        var chorus = SongSection(type: .chorus, startTime: 0, endTime: 16, provenance: .algorithm)
        chorus.label = "Pallavi"
        chorus.activity = [SectionActivity(role: .lead, level: 0.8, evidence: "test", source: .stems), SectionActivity(role: .pad, level: 0.6, evidence: "test", source: .stems)]
        var s = Song(title: "Hook", sections: [chorus])
        s.melody = MelodyTrack(notes: (0..<16).map { MelodyNote(start: Double($0), duration: 0.8, midi: 50 + $0 % 7, confidence: 1) }, source: .fullMix, voicedRatio: 0.9)
        s.partMatches = parts
        return s
    }

    func match(_ part: String, _ program: UInt8) -> PartMatch {
        let p = FactoryPatches.patch(forProgram: program)!
        return PartMatch(part: part, patchId: p.id, name: p.name, similarity: 0.5, eq: EQSettings(), reverbMix: 20, section: "Pallavi",
                         method: PartMatcher.perceptualMethod, perceptualScore: 0.9)
    }

    func testEveryLayerPlaysOnAllKeysAndTheSongsSoundsAreBlended() throws {
        // A strings hook (like a BGM line) over slow strings and a piano part.
        let s = song(parts: ["lead": match("lead", 40), "backing": match("backing", 49), "piano": match("piano", 0)])
        let arranged = AutoArranger.arrange(s, patches: FactoryPatches.all).song
        let tone = try XCTUnwrap(arranged.arrangement(for: arranged.sections[0]))
        XCTAssertGreaterThanOrEqual(tone.layers.count, 2)
        for l in tone.layers {
            XCTAssertEqual(l.keyRange, KeyRange(low: 0, high: 127), "\(l.role.map { "\($0)" } ?? "?") layer covers every key")
            XCTAssertEqual(l.octave, 0, "no AI octave shift")
        }
        let ids = Set(tone.layers.map(\.patchId))
        XCTAssertTrue(ids.contains(FactoryPatches.id(forProgram: 40)), "main sound: the song's lead part")
        XCTAssertTrue(ids.contains(FactoryPatches.id(forProgram: 49)) || ids.contains(FactoryPatches.id(forProgram: 0)), "blended with the song's own accompaniment")
        XCTAssertFalse(tone.layers.contains { $0.role == .bass || $0.role == .accent }, "no guessed bass / celesta layers")
        XCTAssertFalse(tone.rationale?.contains("Left hand") ?? true)
        XCTAssertLessThanOrEqual(tone.layers.map(\.volume).reduce(0, +), 1.1 + 1e-9, "layers sounding together stay within headroom")
    }

    func testTheSplitStaysAvailableAsAnOption() throws {
        var o = AutoArranger.Options(); o.splitKeyboard = true
        let s = song(parts: ["lead": match("lead", 40), "backing": match("backing", 49)])
        let out = AutoArranger.arrange(s, patches: FactoryPatches.all, options: o).song
        let tone = try XCTUnwrap(out.arrangement(for: out.sections[0]))
        XCTAssertTrue(tone.layers.contains { $0.keyRange != KeyRange(low: 0, high: 127) }, "split mode still maps hands")
    }
}
