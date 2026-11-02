import XCTest
@testable import TonePilotCore

/// Diagnostics for the tone-matching bench (TP_SF2 required; TP_SF2_TARGET for a cross-bank target).
/// Is the note extraction from the leaky stem what loses the instrument? Asserts nothing.
final class ToneMatchDiagnostics: XCTestCase {
    func testTrueNotesVersusExtractedNotes() throws {
        guard let path = ProcessInfo.processInfo.environment["TP_SF2"] else { throw XCTSkip("set TP_SF2") }
        let bank = try SoundFontBank(url: URL(fileURLWithPath: path))
        let load = PartMatcher.loader(bank: bank)
        let targetBank = try ProcessInfo.processInfo.environment["TP_SF2_TARGET"].map { try SoundFontBank(url: URL(fileURLWithPath: $0)) }
        let sr = 44_100.0, seconds = 24.0
        func gm(_ p: UInt8) -> InstrumentPatch { FactoryPatches.patch(forProgram: p)! }
        func render(_ p: UInt8, _ notes: [MelodyNote]) -> [Float] {
            let patch = gm(p)
            let inst = targetBank.flatMap { try? LoadedInstrument(bank: $0, bankNumber: 0, program: Int(p), name: patch.name) } ?? load(patch)!
            return ToneMatcher.render(patch, instrument: inst, notes: notes, seconds: seconds, sampleRate: sr).samples
        }
        var trueFam = 0, extFam = 0
        for (ci, c) in ToneMatchingBenchmarks.cases.enumerated() {
            var seed = UInt32(ci * 7919 + 13)
            func rnd(_ n: Int) -> Int { seed = seed &* 1_664_525 &+ 1_013_904_223; return Int(seed >> 8) % n }
            let scale = [0, 2, 4, 5, 7, 9, 11, 12]
            var t = 0.4, lead: [MelodyNote] = []
            while t < seconds - 1 {
                let d = [0.3, 0.45, 0.6, 0.9][rnd(4)]
                lead.append(MelodyNote(start: t, duration: d * 0.9, midi: c.low + scale[rnd(8)], confidence: 1))
                t += d + (rnd(5) == 0 ? 0.3 : 0)
            }
            let chords: [MelodyNote] = stride(from: 0.0, to: seconds - 2, by: 2.0).flatMap { s -> [MelodyNote] in
                let root = 48 + [0, 5, 7, 9][Int(s / 2) % 4]
                return [0, 4, 7].map { MelodyNote(start: s, duration: 1.95, midi: root + $0, confidence: 1) }
            }
            let l = render(c.lead, lead), b = render(c.backing, chords)
            var mix = l
            for i in 0..<l.count { mix[i] += 0.2 * b[i] }
            let stem = AudioBuffer(samples: mix, sampleRate: sr)
            let cands = PartMatcher.candidates(for: .lead, patches: FactoryPatches.all, heard: [:])
            let truthFamily = gm(c.lead).family
            func fam(_ m: ToneMatcher.Match?) -> (Bool, String) {
                guard let m, let p = FactoryPatches.all.first(where: { $0.id == m.patchId }) else { return (false, "—") }
                return (p.family == truthFamily, "\(m.name) [\(p.family.rawValue)]")
            }
            let a = fam(ToneMatcher.bestMatches(target: stem, notes: lead, candidates: cands, instrument: load).first)
            let track = MelodyExtractor.extract(stem, source: .fullMix)
            let ext = track?.notes ?? []
            // How many extracted notes sit on a true note's pitch (±1 semitone) at that time.
            let onPitch = ext.filter { e in lead.contains { abs($0.start - e.start) < 0.15 && abs($0.midi - e.midi) <= 1 } }.count
            let octave = ext.filter { e in lead.contains { abs($0.start - e.start) < 0.15 && abs(abs($0.midi - e.midi) - 12) <= 1 } }.count
            let bE = fam(ToneMatcher.bestMatches(target: stem, notes: ext, candidates: cands, instrument: load).first)
            trueFam += a.0 ? 1 : 0; extFam += bE.0 ? 1 : 0
            print("NOTES \(c.name) [\(truthFamily.rawValue)]: true notes → \(a.1) \(a.0 ? "✓" : "✗") | extracted (\(ext.count) notes, \(onPitch) on pitch, \(octave) octave-off of \(lead.count)) → \(bE.1) \(bE.0 ? "✓" : "✗")")
        }
        print("NOTES RESULT family: true notes \(trueFam)/12, extracted notes \(extFam)/12")
    }
}
