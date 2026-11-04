import XCTest
@testable import TonePilotCore

/// P3.3: 4-part + 6-part fusion — agreement raises confidence, disagreement keeps both candidates,
/// the fused default takes the melody from 4 parts and piano / guitar from 6 parts, your choice rebuilds the tones.
final class PartFusionTests: XCTestCase {
    let patches = FactoryPatches.all

    func patch(_ family: InstrumentFamily, skip: Int = 0) throws -> InstrumentPatch {
        let list = patches.filter { $0.family == family }
        XCTAssertGreaterThan(list.count, skip, "library has \(family) tones")
        return list[skip]
    }

    func match(_ part: StemInfo.Kind, _ p: InstrumentPatch, score: Double = 0.6) -> PartMatch {
        PartMatch(part: part.rawValue, patchId: p.id, name: p.name, similarity: 0.7, eq: EQSettings(), reverbMix: 0.2,
                  section: "Chorus", method: PartMatcher.perceptualMethod, perceptualScore: score)
    }

    func testAgreementRaisesConfidenceAndDisagreementKeepsBoth() throws {
        let flute = try patch(.flute), strings = try patch(.strings), strings2 = try patch(.strings, skip: 1), piano = try patch(.piano)
        let id = UUID(), id2 = UUID()
        let quiet = PartFusion.MatchSet(parts: 4, matches: ["other": match(.other, flute), "backing": match(.backing, strings)],
                                        sectionLeads: [id.uuidString: match(.other, flute), id2.uuidString: match(.other, strings)])
        let six = PartFusion.MatchSet(parts: 6, matches: ["lead": match(.lead, flute), "backing": match(.backing, strings2), "piano": match(.piano, piano)],
                                      sectionLeads: [id.uuidString: match(.lead, flute), id2.uuidString: match(.lead, piano)])
        let f = PartFusion.fuse(quiet: quiet, six: six, patches: patches)
        let melody = try XCTUnwrap(f.entries[PartFusion.melodyKey])
        XCTAssertEqual(melody.agreement, .same, "lead vs Music are compared as the melody")
        XCTAssertGreaterThan(melody.confidence, (0.6 + 1) / 2, "two separations agreeing are surer than one")
        XCTAssertEqual(f.entries["backing"]?.agreement, .sameFamily)
        XCTAssertEqual(f.entries["piano"]?.agreement, .onlyOne)
        let differ = try XCTUnwrap(f.entries[PartFusion.sectionKey(id2)])
        XCTAssertEqual(differ.agreement, .different)
        XCTAssertEqual(differ.quiet, strings.name); XCTAssertEqual(differ.six, piano.name)
        XCTAssertLessThan(differ.confidence, melody.confidence)
        XCTAssertTrue(PartFusion.describe(differ).contains(strings.name) && PartFusion.describe(differ).contains(piano.name), "both candidates are shown")
    }

    func testFusedTakesMelodyFrom4PartsAndPianoFrom6() throws {
        let flute = try patch(.flute), violin = try patch(.strings), piano = try patch(.piano), guitar = try patch(.guitar)
        let id = UUID()
        let quiet = PartFusion.MatchSet(parts: 4, matches: ["other": match(.other, flute)], sectionLeads: [id.uuidString: match(.other, flute)])
        let six = PartFusion.MatchSet(parts: 6, matches: ["other": match(.other, violin), "piano": match(.piano, piano), "guitar": match(.guitar, guitar)],
                                      sectionLeads: [id.uuidString: match(.other, violin), UUID().uuidString: match(.other, violin)])
        let f = PartFusion.fuse(quiet: quiet, six: six, patches: patches)
        let fused = f.set(for: .fused)
        XCTAssertEqual(fused.matches["other"]?.patchId, flute.id)
        XCTAssertEqual(fused.matches["piano"]?.patchId, piano.id)
        XCTAssertEqual(fused.matches["guitar"]?.patchId, guitar.id)
        XCTAssertEqual(fused.sectionLeads[id.uuidString]?.patchId, flute.id, "section leads from 4 parts")
        XCTAssertEqual(fused.sectionLeads.count, 2, "sections only the 6-part model matched are kept")
        XCTAssertEqual(f.set(for: .six).matches["other"]?.patchId, violin.id)
        XCTAssertNil(f.set(for: .quiet).matches["piano"])
    }

    /// Choosing the other model's matches rebuilds the section tones and the main tone from them.
    func testChoiceRebuildsTheMainTone() throws {
        let flute = try patch(.flute), violin = try XCTUnwrap(patches.first { $0.family == .strings && ($0.tags ?? []).contains("lead") } ?? patches.first { $0.family == .strings })
        var song = SongUnderstandingTests.makeSong()
        let quiet = PartFusion.MatchSet(parts: 4, matches: ["other": match(.other, flute, score: 0.9)], sectionLeads: [:])
        let six = PartFusion.MatchSet(parts: 6, matches: ["other": match(.other, violin, score: 0.9)], sectionLeads: [:])
        song.fusion = PartFusion.fuse(quiet: quiet, six: six, patches: patches)
        PartFusion.apply(.fused, to: &song)
        XCTAssertTrue(song.fusion?.isCurrent(song) == true)
        song = AutoArranger.arrange(song, patches: patches).song
        func mainLayers(_ s: Song) -> [UUID] { s.arrangements.first { $0.name == "Main tone" && $0.origin != .aiOriginal }?.layers.map(\.patchId) ?? [] }
        XCTAssertTrue(mainLayers(song).contains(flute.id), "fused: the 4-part model's melody tone")
        PartFusion.apply(.six, to: &song)
        XCTAssertEqual(song.fusion?.choice, .six)
        song = AutoArranger.arrange(song, patches: patches).song
        XCTAssertTrue(mainLayers(song).contains(violin.id), "6 parts only: the 6-part model's melody tone")
        XCTAssertTrue(song.fusion?.isCurrent(song) == true)
        // A re-analysis that replaces the matches makes the fusion stale (the UI hides it).
        song.partMatches = ["other": match(.other, flute, score: 0.5)]
        XCTAssertFalse(song.fusion?.isCurrent(song) == true)
        // Survives saving.
        let back = try JSONDecoder().decode(Song.self, from: JSONEncoder().encode(song))
        XCTAssertEqual(back.fusion, song.fusion)
    }
}
