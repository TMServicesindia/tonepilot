import XCTest
@testable import TonePilotCore

/// The perceptual nearest-sound path end to end with a stand-in embedding model: each section's own
/// lead sound is found (pallavi vs charanam), marked perceptual, trusted, and used by the arranger
/// for that section's right hand. Accuracy itself is measured in the tone bench (sealed TEST).
final class PerceptualPartMatchTests: XCTestCase {
    /// Stand-in model: per-band mean of the window (a crude timbre summary; deterministic).
    static func standInEmbed(_ w: [Float]) -> [Float] {
        (0..<128).map { m in w[(m * 101)..<(m * 101 + 101)].reduce(0, +) / 101 }
    }

    static func synthLoader(_ p: InstrumentPatch) -> LoadedInstrument? { p.synth.map { LoadedInstrument(name: p.name, synth: $0) } }

    func testEachSectionGetsItsOwnNearestLeadSound() throws {
        let synths = FactoryPatches.all.filter { $0.synth != nil && $0.family != .percussion && $0.family != .bass }
        // Two clearly different synth tones as the song's two lead sounds.
        guard let a = synths.first(where: { $0.family == .synthLead }), let b = synths.first(where: { $0.family == .pad || $0.family == .flute }) else {
            throw XCTSkip("needs a synth lead and a pad/flute synth in the factory library")
        }
        let candidates = [a, b] + synths.filter { $0.id != a.id && $0.id != b.id }.prefix(4)
        let sr = 22_050.0, sr32 = EfficientATFrontEnd.sampleRate
        func phrase(_ t0: Double) -> [MelodyNote] {
            (0..<14).map { i in MelodyNote(start: t0 + 0.3 + Double(i) * 0.5, duration: 0.42, midi: 62 + [0, 2, 4, 7, 9, 7, 4][i % 7], confidence: 1) }
        }
        let verseNotes = phrase(0), chorusNotes = phrase(8)
        func render(_ p: InstrumentPatch, _ notes: [MelodyNote], seconds: Double, rate: Double) -> [Float] {
            ToneMatcher.render(p, instrument: Self.synthLoader(p)!, notes: notes, seconds: seconds, sampleRate: rate).samples
        }
        // Lead stem: tone A in the verse, tone B in the chorus.
        func stem(rate: Double) -> [Float] {
            let x = render(a, verseNotes, seconds: 16, rate: rate), y = render(b, chorusNotes, seconds: 16, rate: rate)
            return zip(x, y).map { $0 + $1 }
        }
        let lead22 = AudioBuffer(samples: stem(rate: sr), sampleRate: sr)
        let lead32 = stem(rate: sr32)
        // Tables: every candidate playing the same phrases (the CI table uses standard phrases instead).
        func entries(masked: Bool) -> [PerceptualToneSearch.ToneTable.Entry] {
            candidates.flatMap { p -> [PerceptualToneSearch.ToneTable.Entry] in
                [verseNotes, chorusNotes.map { n -> MelodyNote in var m = n; m.start -= 8; return m }].enumerated().compactMap { i, notes in
                    let x = render(p, notes, seconds: 8, rate: sr32)
                    guard let e = PerceptualToneSearch.embedding(samples: x, notes: masked ? notes : nil, embed: Self.standInEmbed) else { return nil }
                    return .init(patch: p.id, register: i, embedding: e)
                }
            }
        }
        let hook = PartMatcher.PerceptualHook(
            harmonic: .init(version: 1, model: "stand-in", embeddingDim: 128, entries: entries(masked: true)),
            plain: .init(version: 1, model: "stand-in", embeddingDim: 128, entries: entries(masked: false)),
            audio32k: { kind, start, end in
                guard kind == .lead else { return nil }
                let i0 = max(0, Int(start * sr32)), i1 = min(lead32.count, Int(end * sr32))
                return i1 > i0 ? Array(lead32[i0..<i1]) : nil
            },
            embed: Self.standInEmbed)

        var verse = SongSection(type: .verse, startTime: 0, endTime: 8, provenance: .algorithm)
        verse.label = "Charanam"
        var chorus = SongSection(type: .chorus, startTime: 8, endTime: 16, provenance: .algorithm)
        chorus.label = "Pallavi"
        var song = Song(title: "Two sounds", sections: [verse, chorus])

        let leads = PartMatcher.matchSectionLeads(song: song, parts: [.lead: lead22], patches: candidates, instrument: Self.synthLoader, perceptual: hook)
        XCTAssertEqual(leads[verse.id.uuidString]?.patchId, a.id, "charanam's own lead sound")
        XCTAssertEqual(leads[chorus.id.uuidString]?.patchId, b.id, "pallavi's own lead sound")
        XCTAssertTrue(leads.values.allSatisfy { $0.isPerceptual && $0.isTrusted })

        // The arranger plays each section's own sound on the right hand.
        song.sectionLeadMatches = leads
        let arranged = AutoArranger.arrange(song, patches: candidates + FactoryPatches.all).song
        for (section, expected) in [(verse, a.id), (chorus, b.id)] {
            let arr = try XCTUnwrap(arranged.arrangement(for: arranged.sections.first { $0.id == section.id }!))
            let right = arr.layers.first { [.lead, .vocalMelody, .motif].contains($0.role) }
            XCTAssertEqual(right?.patchId, expected, "\(section.label) right hand")
        }

        // The whole-part match takes the perceptual path too.
        let part = PartMatcher.match(song: song, parts: [.lead: lead22], patches: candidates, instrument: Self.synthLoader, perceptual: hook)
        XCTAssertEqual(part["lead"]?.method, PartMatcher.perceptualMethod)
    }

    func testWithoutHookTheFingerprintPathIsUnchanged() {
        let m = PartMatch(part: "lead", patchId: UUID(), name: "x", similarity: 0.5, eq: EQSettings(), reverbMix: 10, section: "s")
        XCTAssertFalse(m.isPerceptual)
        XCTAssertFalse(m.isTrusted)          // below PartMatcher.trusted, as before
        // Old saved songs (no new keys) still decode.
        let old = #"{"part":"lead","patchId":"7091CE00-0000-4000-8000-000000000049","name":"Flute","similarity":0.7,"eq":{"lowDB":0,"midDB":0,"midFrequency":1200,"highDB":0},"reverbMix":20,"section":"Chorus"}"#
        let decoded = try? JSONDecoder().decode(PartMatch.self, from: Data(old.utf8))
        XCTAssertNotNil(decoded); XCTAssertNil(decoded?.method); XCTAssertTrue(decoded?.isTrusted == true)
    }
}
