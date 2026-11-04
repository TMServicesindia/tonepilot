import XCTest
@testable import TonePilotCore

/// Section repeat grouping benchmark (opt-in, never shipped; TODO 5.4). Songs rendered from GeneralUser GS
/// with known sections: each label has its own chords and instruments; repeats may add a part (a second
/// chorus with strings) or change loudness, as in film songs. Scored on pairs of true sections: are two
/// sections grouped together exactly when they share a label? (Read at each true section's midpoint.)
/// DEV songs 1–2 are for tuning; held-out songs 3–4 are only reported. Synthetic: it can show grouping is
/// wrong, not that it is right on real songs. Run with TP_SF2=<GeneralUser-GS.sf2>.
final class SectionGroupingBenchmarks: XCTestCase {
    var load: ((InstrumentPatch) -> LoadedInstrument?)!
    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["TP_SF2"] else { throw XCTSkip("TP_SF2 not set") }
        load = PartMatcher.loader(bank: try SoundFontBank(url: URL(fileURLWithPath: path)))
    }

    struct Part { let label: String; let instruments: [UInt8]; let extra: UInt8?; let gain: Float }
    /// Chords (bar roots) and register per label.
    static let shapes: [String: (roots: [Int], high: Bool)] = [
        "A": ([0, 9, 5, 7], false), "B": ([5, 7, 0, 0], true), "C": ([2, 7, 0, 9], false), "D": ([9, 5, 0, 7], true)]

    func song(_ plan: [Part], bpm: Double, barsPer: Int = 8, sr: Double = 22_050) -> (AudioBuffer, [(String, Double, Double)]) {
        let beat = 60 / bpm, t0 = 0.5
        let seconds = t0 + Double(plan.count * barsPer * 4) * beat + 1
        var mix = [Float](repeating: 0, count: Int(seconds * sr))
        var truth: [(String, Double, Double)] = []
        for (si, part) in plan.enumerated() {
            let start = t0 + Double(si * barsPer * 4) * beat
            truth.append((part.label, start, start + Double(barsPer * 4) * beat))
            let shape = Self.shapes[part.label]!
            for (k, inst) in (part.instruments + [part.extra].compactMap { $0 }).enumerated() {
                var notes: [MelodyNote] = []
                for bar in 0..<barsPer {
                    let root = 48 + shape.roots[bar % 4] + (shape.high ? 12 : 0)
                    for b in 0..<4 {
                        let tt = start + Double(bar * 4 + b) * beat
                        let midi = k == 0 ? root + [0, 7, 12, 16][b] : (k == 1 ? root - 12 + (b % 2) * 7 : root + 12 + [4, 7][b % 2])
                        notes.append(MelodyNote(start: tt, duration: beat * 0.9, midi: midi, confidence: 1))
                    }
                }
                let p = FactoryPatches.patch(forProgram: inst)!
                let r = ToneMatcher.render(p, instrument: load(p)!, notes: notes, seconds: seconds, sampleRate: sr).samples
                for i in 0..<min(mix.count, r.count) { mix[i] += 0.5 * part.gain * r[i] }
            }
        }
        return (AudioBuffer(samples: mix, sampleRate: sr), truth)
    }

    /// Pair precision / recall of "same section" between true sections, from the found groups.
    func score(_ found: [SongSection], _ truth: [(String, Double, Double)]) -> (p: Double, r: Double, groups: String) {
        let g: [String?] = truth.map { t in
            let mid = (t.1 + t.2) / 2
            return found.last { $0.startTime <= mid }?.repetitionGroup
        }
        var tp = 0, fp = 0, fn = 0
        for i in truth.indices { for j in truth.indices where j > i {
            let same = truth[i].0 == truth[j].0, said = g[i] != nil && g[i] == g[j]
            if same && said { tp += 1 } else if said { fp += 1 } else if same { fn += 1 }
        } }
        let p = tp + fp == 0 ? 1 : Double(tp) / Double(tp + fp), r = tp + fn == 0 ? 1 : Double(tp) / Double(tp + fn)
        return (p, r, g.map { $0 ?? "?" }.joined())
    }

    static let dev: [(String, Double, [Part])] = [
        ("dev 1 ABABC", 100, [.init(label: "A", instruments: [0, 49], extra: nil, gain: 1), .init(label: "B", instruments: [61, 33], extra: nil, gain: 1.6),
                              .init(label: "A", instruments: [0, 49], extra: nil, gain: 1), .init(label: "B", instruments: [61, 33], extra: nil, gain: 1.6),
                              .init(label: "C", instruments: [73, 46], extra: nil, gain: 1)]),
        // Second chorus adds strings and is louder; the bridge reuses the verse instruments with other chords.
        ("dev 2 ABAB'CB'", 92, [.init(label: "A", instruments: [4, 32], extra: nil, gain: 1), .init(label: "B", instruments: [24, 32], extra: nil, gain: 1.3),
                                .init(label: "A", instruments: [4, 32], extra: nil, gain: 1), .init(label: "B", instruments: [24, 32], extra: 48, gain: 1.5),
                                .init(label: "C", instruments: [4, 32], extra: nil, gain: 1), .init(label: "B", instruments: [24, 32], extra: 48, gain: 1.5)]),
    ]
    static let heldOut: [(String, Double, [Part])] = [
        ("held-out 3 ABACAB", 110, [.init(label: "A", instruments: [46, 42], extra: nil, gain: 1), .init(label: "B", instruments: [56, 33], extra: nil, gain: 1.4),
                                    .init(label: "A", instruments: [46, 42], extra: 73, gain: 1.1), .init(label: "C", instruments: [19, 33], extra: nil, gain: 0.8),
                                    .init(label: "A", instruments: [46, 42], extra: nil, gain: 1), .init(label: "B", instruments: [56, 33], extra: 48, gain: 1.6)]),
        ("held-out 4 DABAB", 84, [.init(label: "D", instruments: [104, 49], extra: nil, gain: 0.9), .init(label: "A", instruments: [0, 32], extra: nil, gain: 1),
                                  .init(label: "B", instruments: [0, 32], extra: 40, gain: 1.4), .init(label: "A", instruments: [0, 32], extra: nil, gain: 1),
                                  .init(label: "B", instruments: [0, 32], extra: 40, gain: 1.5)]),
    ]

    func testRepeatGrouping() throws {
        for (set, songs) in [("DEV", Self.dev), ("HELD-OUT", Self.heldOut)] {
            for (name, bpm, plan) in songs {
                let (audio, truth) = song(plan, bpm: bpm)
                var opt = SongAnalyzer.Options(); opt.extractMelody = false
                let r = try SongAnalyzer.analyze(audio, options: opt)
                let s = score(r.sections, truth)
                print(String(format: "GROUPING RESULT %@ %@: pair precision %.2f recall %.2f · truth %@ · found %@ (%d sections)",
                             set, name, s.p, s.r, plan.map(\.label).joined(), s.groups, r.sections.count))
            }
        }
    }
}
