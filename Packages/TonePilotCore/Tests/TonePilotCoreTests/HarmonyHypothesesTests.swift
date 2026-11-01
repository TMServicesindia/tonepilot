import XCTest
@testable import TonePilotCore

final class HarmonyHypothesesTests: XCTestCase {
    static let sr = 22_050.0

    /// Additive "piano-like" tones (6 harmonics) for each beat's notes.
    static func render(_ beats: [[Int]], beat: Double = 0.6) -> (AudioBuffer, [Double]) {
        let n = Int((Double(beats.count) * beat + 0.5) * sr)
        var x = [Float](repeating: 0, count: n)
        for (i, notes) in beats.enumerated() {
            let s = Int(Double(i) * beat * sr), e = min(n, s + Int(beat * sr))
            for m in notes {
                let f = 440 * pow(2, Double(m - 69) / 12)
                for k in s..<e {
                    let t = Double(k - s) / sr
                    var v = 0.0
                    for h in 1...6 { v += pow(0.6, Double(h - 1)) * sin(2 * .pi * f * Double(h) * Double(k) / sr) }
                    x[k] += Float(0.05 * v * exp(-t * 1.5))
                }
            }
        }
        return (AudioBuffer(samples: x, sampleRate: sr), (0...beats.count).map { Double($0) * beat })
    }

    func label(_ spans: [HarmonyHypotheses.Span], at t: Double) -> String {
        spans.last { $0.time <= t && t < $0.time + $0.duration }?.label ?? "-"
    }

    func testMajorMinorAndChangesOnAnyBeat() {
        // C | C | Am | F (change on beat 3) | G | Em
        let chords: [[Int]] = [[36, 60, 64, 67], [36, 60, 64, 67], [45, 57, 60, 64], [41, 53, 57, 60], [43, 55, 59, 62], [40, 55, 59, 64]]
        let (audio, beats) = Self.render(Array(repeating: chords, count: 3).flatMap { $0 })
        let spans = HarmonyHypotheses.analyze(audio, beats: beats)
        let expected = ["C", "C", "Am", "F", "G", "Em"]
        for rep in 1..<3 { for (j, e) in expected.enumerated() { XCTAssertEqual(label(spans, at: Double(rep * 6 + j) * 0.6 + 0.3), e, "beat \(rep * 6 + j)") } }
    }

    func testBassIsEvidenceNotVerdict() {
        // C/E (first inversion) and F over a C pedal stay C and F.
        let beats: [[Int]] = Array(repeating: [[40, 60, 64, 67], [40, 60, 64, 67], [36, 65, 69, 72], [36, 65, 69, 72]], count: 4).flatMap { $0 }
        let (audio, b) = Self.render(beats)
        let spans = HarmonyHypotheses.analyze(audio, beats: b)
        XCTAssertEqual(label(spans, at: 4 * 0.6 + 0.3), "C")
        XCTAssertEqual(label(spans, at: 6 * 0.6 + 0.3), "F")
    }

    func testDroneIsNeverForcedToATriad() {
        // Sa–Pa (C, G) sustained with a melody walking the scale: a drone, not C major.
        let scale = [72, 74, 76, 77, 79, 81, 83, 84]
        let beats: [[Int]] = (0..<24).map { [36, 48, 55, scale[$0 % 8]] }
        let (audio, b) = Self.render(beats)
        let spans = HarmonyHypotheses.analyze(audio, beats: b)
        let mid = label(spans, at: 12 * 0.6 + 0.3)
        XCTAssertEqual(mid, "drone:C")
        XCTAssertEqual(spans.first { $0.label == "drone:C" }?.state, .drone)
    }

    func testAlternativesAreRankedAndExcludeTheChoice() {
        let (audio, b) = Self.render(Array(repeating: [45, 57, 60, 64], count: 12))
        let spans = HarmonyHypotheses.analyze(audio, beats: b)
        let s = spans.first { $0.label == "Am" }
        XCTAssertNotNil(s)
        XCTAssertFalse(s!.alternatives.contains("Am"))
        XCTAssertFalse(s!.alternatives.isEmpty)
    }

    /// Speed: a 4-minute song at 100 BPM (400 beats) must stay well inside the analysis budget.
    func testSpeedFourMinuteSong() {
        let notes: [[Int]] = [[36, 60, 64, 67], [45, 57, 60, 64], [41, 53, 57, 60], [43, 55, 59, 62]]
        let (audio, beats) = Self.render((0..<400).map { notes[($0 / 4) % 4] })
        let t0 = Date()
        _ = HarmonyHypotheses.analyze(audio, beats: beats)
        let dt = Date().timeIntervalSince(t0)
        print(String(format: "SPEED harmony hypotheses: %.2f s for %.0f s of audio", dt, audio.duration))
        #if !DEBUG
        XCTAssertLessThan(dt, 10, "harmony must take < 10 s per 4-minute song (release)")
        #endif
    }
}
