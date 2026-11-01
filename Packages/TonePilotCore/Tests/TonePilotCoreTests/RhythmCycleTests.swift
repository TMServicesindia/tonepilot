import XCTest
@testable import TonePilotCore

final class RhythmCycleTests: XCTestCase {
    func beats(_ n: Int, period: Double = 0.5) -> [Double] { (0..<n).map { 0.3 + Double($0) * period } }

    func testDownbeatsEveryCycleLengthAreFoundWithPhase() {
        for L in RhythmCycleInference.lengths {
            let b = beats(64), phase = 1
            let d = b.indices.filter { $0 >= phase && ($0 - phase) % L == 0 }.map { b[$0] + 0.02 }
            let c = RhythmCycleInference.infer(.init(beats: b, downbeats: d))
            XCTAssertEqual(c.beatsPerCycle, L, "length \(L)")
            XCTAssertEqual(c.phase, phase, "length \(L)")
            XCTAssertEqual(c.state, .confident, "length \(L)")
            XCTAssertFalse(c.names.isEmpty)
        }
    }

    func testTooFewBeatsIsUnknown() {
        let b = beats(10)
        let c = RhythmCycleInference.infer(.init(beats: b, downbeats: [b[0], b[4], b[8]]))
        XCTAssertEqual(c.state, .unknown)
        XCTAssertNil(c.beatsPerCycle)
    }

    func testNoEvidenceIsUnknown() {
        XCTAssertEqual(RhythmCycleInference.infer(.init(beats: beats(64))).state, .unknown)
    }

    func testIrregularDownbeatsAreNeverConfident() {
        var rng = SystemRandomNumberGenerator()
        let b = beats(64)
        for _ in 0..<20 {
            var d: [Double] = [], i = 0
            while i < b.count { d.append(b[i]); i += Int.random(in: 2...8, using: &rng) }
            let c = RhythmCycleInference.infer(.init(beats: b, downbeats: d))
            XCTAssertNotEqual(c.state, .confident, "random downbeats \(d.count)")
        }
    }

    func testMixedCyclesAreNotConfident() {
        // 3 + 2 + 2 grouping (misra chapu) seen with downbeats on every group start → not a clean 7 or 2.
        let b = beats(70)
        var d: [Double] = [], i = 0, g = 0
        while i < b.count { d.append(b[i]); i += [3, 2, 2][g % 3]; g += 1 }
        let c = RhythmCycleInference.infer(.init(beats: b, downbeats: d))
        XCTAssertNotEqual(c.state, .confident)
    }

    func testAccentsAloneFindTheCycle() {
        let b = beats(48)
        let a = b.indices.map { $0 % 3 == 0 ? 1.0 : 0.2 }
        let c = RhythmCycleInference.infer(.init(beats: b, accents: a))
        XCTAssertEqual(c.beatsPerCycle, 3)
        XCTAssertEqual(c.phase, 0)
    }

    func testAccentsFromAudioPeakOnChordChangesAndBass() {
        // Bass hit + chord change every 4 beats; quiet upper chord on the others.
        let sr = 22_050.0, b = beats(32), n = Int(17.0 * sr)
        var x = [Float](repeating: 0, count: n)
        let chords: [[Double]] = [[261.6, 329.6, 392.0], [220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [196.0, 246.9, 293.7]]
        for (i, t) in b.enumerated() {
            let s = Int(t * sr), e = min(n, s + Int(0.5 * sr)), ch = chords[(i / 4) % 4]
            for k in s..<e {
                let tt = Double(k - s) / sr
                var v = 0.0
                for f in ch { v += 0.1 * sin(2 * .pi * f * Double(k) / sr) }
                if i % 4 == 0 { v += 0.6 * sin(2 * .pi * 55 * tt) * exp(-tt * 6) }
                x[k] += Float(v)
            }
        }
        let a = RhythmCycleInference.accents(AudioBuffer(samples: x, sampleRate: sr), beats: b)
        let c = RhythmCycleInference.infer(.init(beats: b, accents: a))
        XCTAssertEqual(c.beatsPerCycle, 4)
        XCTAssertEqual(c.phase, 0)
    }
}
