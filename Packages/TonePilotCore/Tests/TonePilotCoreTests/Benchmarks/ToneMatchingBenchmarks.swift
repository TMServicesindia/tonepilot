import XCTest
@testable import TonePilotCore

/// Tone-matching bench on rendered multi-instrument songs with known instruments (GeneralUser GS).
/// Separation is imitated by leaking the other parts into each stem. Run with TP_SF2=<path to
/// GeneralUser-GS.sf2>; skipped otherwise. Prints the accuracy table.
final class ToneMatchingBenchmarks: XCTestCase {
    struct Case { let name: String; let lead: UInt8; let backing: UInt8; let low: Int }
    static let cases: [Case] = [
        .init(name: "Flute", lead: 73, backing: 48, low: 72), .init(name: "Violin", lead: 40, backing: 89, low: 67),
        .init(name: "Shehnai", lead: 111, backing: 48, low: 67), .init(name: "Trumpet", lead: 56, backing: 49, low: 62),
        .init(name: "Alto sax", lead: 65, backing: 4, low: 60), .init(name: "Sitar", lead: 104, backing: 89, low: 62),
        .init(name: "Saw lead", lead: 81, backing: 50, low: 64), .init(name: "Nylon guitar", lead: 24, backing: 48, low: 60),
        .init(name: "Piano", lead: 0, backing: 49, low: 64), .init(name: "Accordion", lead: 21, backing: 48, low: 62),
        .init(name: "Clarinet", lead: 71, backing: 89, low: 60), .init(name: "Pan flute", lead: 75, backing: 48, low: 70),
    ]

    func testToneMatchingOnRenderedSongs() throws {
        guard let path = ProcessInfo.processInfo.environment["TP_SF2"] else { throw XCTSkip("set TP_SF2 to run the bench") }
        let bank = try SoundFontBank(url: URL(fileURLWithPath: path))
        let load = PartMatcher.loader(bank: bank)
        let sr = 44_100.0, seconds = 30.0
        func gm(_ p: UInt8) -> InstrumentPatch { FactoryPatches.patch(forProgram: p)! }
        func render(_ p: UInt8, _ notes: [MelodyNote]) -> [Float] {
            let patch = gm(p)
            return ToneMatcher.render(patch, instrument: load(patch)!, notes: notes, seconds: seconds, sampleRate: sr).samples
        }
        var leadHits = 0, leadFamily = 0, backingHits = 0, backingFamily = 0
        var rows: [String] = []
        for (ci, c) in Self.cases.enumerated() {
            var seed = UInt32(ci * 7919 + 13)
            func rnd(_ n: Int) -> Int { seed = seed &* 1_664_525 &+ 1_013_904_223; return Int(seed >> 8) % n }
            let scale = [0, 2, 4, 5, 7, 9, 11, 12]
            var t = 0.4, lead: [MelodyNote] = []
            while t < seconds - 1 {
                let d = [0.3, 0.45, 0.6, 0.9][rnd(4)]
                lead.append(MelodyNote(start: t, duration: d * 0.9, midi: c.low + scale[rnd(8)], confidence: 1))
                t += d + (rnd(5) == 0 ? 0.3 : 0)
            }
            let vocal: [MelodyNote] = stride(from: 0.2, to: seconds - 1, by: 0.7).map { MelodyNote(start: $0, duration: 0.6, midi: 60 + scale[rnd(8)], confidence: 1) }
            let chords: [MelodyNote] = stride(from: 0.0, to: seconds - 2, by: 2.0).flatMap { s -> [MelodyNote] in
                let root = 48 + [0, 5, 7, 9][Int(s / 2) % 4]
                return [0, 4, 7].map { MelodyNote(start: s, duration: 1.95, midi: root + $0, confidence: 1) }
            }
            let bassNotes: [MelodyNote] = stride(from: 0.0, to: seconds - 1, by: 0.5).map { MelodyNote(start: $0, duration: 0.45, midi: 36 + [0, 5, 7, 9][Int($0 / 2) % 4], confidence: 1) }
            let l = render(c.lead, lead), b = render(c.backing, chords), v = render(52, vocal), bs = render(33, bassNotes)
            // Imitated separation: each stem keeps some of the others.
            var leadSamples = l, backSamples = b
            for i in 0..<l.count {
                let other: Float = 0.15 * v[i] + 0.1 * bs[i]
                leadSamples[i] += 0.2 * b[i] + other
                backSamples[i] += 0.2 * l[i] + other
            }
            let leadStem = AudioBuffer(samples: leadSamples, sampleRate: sr)
            let backStem = AudioBuffer(samples: backSamples, sampleRate: sr)
            var chorus = SongSection(type: .chorus, startTime: 0, endTime: seconds, provenance: .algorithm)
            chorus.timbre = SectionTimbre(centroid: 2000, onsetRate: 3, lowEnergyShare: 0.3, highEnergyShare: 0.1, sustain: 0.5, loudness: 0.2)
            let song = Song(title: c.name, sections: [chorus])
            let m = PartMatcher.match(song: song, parts: [.lead: leadStem, .backing: backStem], patches: FactoryPatches.all, instrument: load)
            func judge(_ match: PartMatch?, truth: UInt8) -> (Bool, Bool, String) {
                guard let match, let p = FactoryPatches.all.first(where: { $0.id == match.patchId }) else { return (false, false, "—") }
                let exact = p.soundFont?.program == truth
                let family = exact || p.family == gm(truth).family
                return (exact, family, "\(match.name) \(Int(match.similarity * 100))%")
            }
            let (le, lf, ls) = judge(m["lead"], truth: c.lead), (be, bf, bsName) = judge(m["backing"], truth: c.backing)
            leadHits += le ? 1 : 0; leadFamily += lf ? 1 : 0; backingHits += be ? 1 : 0; backingFamily += bf ? 1 : 0
            rows.append("BENCH \(c.name) [\(gm(c.lead).name)]: lead → \(ls) \(le ? "✓" : lf ? "~" : "✗") | backing [\(gm(c.backing).name)] → \(bsName) \(be ? "✓" : bf ? "~" : "✗")")
        }
        rows.forEach { print($0) }
        let n = Self.cases.count
        print("BENCH RESULT lead: \(leadHits)/\(n) exact sound, \(leadFamily)/\(n) right family; backing: \(backingHits)/\(n) exact, \(backingFamily)/\(n) family")
    }
}
