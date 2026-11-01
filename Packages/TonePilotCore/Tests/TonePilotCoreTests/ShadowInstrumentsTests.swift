import XCTest
@testable import TonePilotCore

/// Shadow mode is a comparison only: these tests check the head maths (same as scikit-learn),
/// the decision rule (same as calibrate.py), section pooling and the agreement summary.
final class ShadowInstrumentsTests: XCTestCase {
    /// Two-dimensional toy head: "violin" (Strings) fires on dim 0, "flute" (Western winds) on dim 1.
    func head(thresholds: [Float] = [0.8, 0.6]) -> ShadowInstruments.Head {
        .init(version: 1, source: "test", embeddingDim: 2, mean: [1, 0], scale: [2, 1],
              inst: .init(labels: ["flute", "tabla", "violin"], weights: [[0, 4], [], [4, 0]], bias: [-2, 0, -2]),
              fam: .init(labels: ["Strings", "Western winds"], weights: [[3, 0], [0, 3]], bias: [-1, -1]),
              familyOf: ["violin": "Strings", "flute": "Western winds", "tabla": "Indian percussion"], thresholds: thresholds)
    }

    func testScoresMatchLogisticRegression() {
        let s = head().scores([3, 0.5])           // z = [(3-1)/2, 0.5/1] = [1, 0.5]
        let sig: (Float) -> Float = { 1 / (1 + exp(-$0)) }
        XCTAssertEqual(s.inst[0], sig(4 * 0.5 - 2), accuracy: 1e-6)    // flute
        XCTAssertEqual(s.inst[1], 0)                                   // no head trained → 0
        XCTAssertEqual(s.inst[2], sig(4 * 1 - 2), accuracy: 1e-6)      // violin
        XCTAssertEqual(s.fam[0], sig(3 * 1 - 1), accuracy: 1e-6)
        XCTAssertEqual(s.fam[1], sig(3 * 0.5 - 1), accuracy: 1e-6)
    }

    func testDecisionRuleMatchesCalibrationScript() {
        let h = head()
        XCTAssertEqual(ShadowInstruments.decide(inst: [0.1, 0, 0.9], fam: [0.9, 0.1], head: h).level, "instrument")
        XCTAssertEqual(ShadowInstruments.decide(inst: [0.1, 0, 0.9], fam: [0.9, 0.1], head: h).family, "Strings")
        let fam = ShadowInstruments.decide(inst: [0.1, 0, 0.7], fam: [0.2, 0.65], head: h)
        XCTAssertEqual(fam.level, "family"); XCTAssertEqual(fam.family, "Western winds"); XCTAssertNil(fam.instrument)
        XCTAssertEqual(ShadowInstruments.decide(inst: [0.1, 0, 0.7], fam: [0.5, 0.5], head: h).level, "unknown")
    }

    func testBadHeadIsRejected() {
        let h = head()
        let bad = ShadowInstruments.Head(version: 1, source: "x", embeddingDim: 3, mean: h.mean, scale: h.scale, inst: h.inst, fam: h.fam,
                                         familyOf: h.familyOf, thresholds: h.thresholds)
        XCTAssertThrowsError(try bad.validate())
    }

    func testSectionsPooledAndComparedWithProduction() throws {
        // 4 s of audio; the stand-in model says "violin" in the first 2 s and "flute" after.
        let sr = Int(EfficientATFrontEnd.sampleRate)
        var x = [Float](repeating: 0, count: 4 * sr)
        for i in 0..<x.count { x[i] = 0.3 * sin(Float(i) * 0.05) }
        let a = UUID(), b = UUID(), c = UUID()
        let sections = [ShadowInstruments.SectionInput(id: a, label: "Intro", start: 0, end: 2),
                        .init(id: b, label: "Verse", start: 2, end: 4.2), .init(id: c, label: "Tail", start: 4.2, end: 9)]
        var calls = 0
        let report = try ShadowInstruments.analyse(samples: x, sections: sections,
                                                   production: [a: ["strings": 0.7, "piano": 0.2], b: ["piano": 0.6], c: ["voice": 0.9]],
                                                   head: head()) { window in
            XCTAssertEqual(window.count, 128 * 101)
            calls += 1
            return calls <= 3 ? [5, 0] : [1, 3]      // first windows (centres 0.5, 1.0, 1.5 s) violin-like, then flute-like
        }
        XCTAssertEqual(Int(report.timing["windows"]!), calls)
        let byId = Dictionary(uniqueKeysWithValues: report.sections.map { ($0.sectionId, $0) })
        XCTAssertEqual(byId[a]?.shadow.instrument, "violin")
        XCTAssertEqual(byId[a]?.agreesWithProduction, true)            // strings ↔ Strings
        XCTAssertEqual(byId[b]?.shadow.family, "Western winds")
        XCTAssertEqual(byId[b]?.agreesWithProduction, false)           // piano ↔ Keys only
        XCTAssertEqual(byId[c]?.windows, 0)
        XCTAssertNil(byId[c]?.agreesWithProduction)                    // nothing to compare
        XCTAssertEqual(report.summary["agree"], 1); XCTAssertEqual(report.summary["disagree"], 1)
        XCTAssertEqual(report.summary["not_comparable"], 1)
        XCTAssertTrue(report.label.contains("developer-only"))
        // The report must be JSON-encodable (it's written to the developer folder).
        XCTAssertNoThrow(try JSONEncoder().encode(report))
    }

    func testTooShortAudio() {
        XCTAssertThrowsError(try ShadowInstruments.analyse(samples: [Float](repeating: 0, count: 1000), sections: [], production: [:],
                                                           head: head()) { _ in [0, 0] }) { XCTAssertEqual($0 as? ShadowInstruments.ShadowError, .tooShort) }
    }
}

/// Speed budget for shadow mode's own work on a 4-minute song: mel front-end + head scoring of every
/// window, with the real head size (960-dim embedding, 53 instrument + 13 family heads). The Core ML
/// call itself is measured separately (Gate 2, Mac CI; iPhone pending). Budget 10 s, release only.
final class ShadowInstrumentsSpeedTests: XCTestCase {
    func testShadowWorkOnFourMinuteSongIsQuick() throws {
        #if DEBUG
        throw XCTSkip("speed budgets are checked in release builds (swift test -c release)")
        #endif
        let d = 960
        func lin(_ n: Int) -> ShadowInstruments.Head.Linear {
            .init(labels: (0..<n).map { "l\($0)" }, weights: (0..<n).map { j in (0..<d).map { Float(($0 + j) % 7) * 0.001 } }, bias: [Float](repeating: -1, count: n))
        }
        let inst = lin(53), fam = lin(13)
        let head = ShadowInstruments.Head(version: 1, source: "speed", embeddingDim: d, mean: [Float](repeating: 0, count: d),
                                          scale: [Float](repeating: 1, count: d), inst: inst, fam: fam,
                                          familyOf: Dictionary(uniqueKeysWithValues: inst.labels.map { ($0, "l0") }), thresholds: [0.9, 0.9])
        let x = (0..<(240 * 32_000)).map { Float(sin(Double($0) * 0.05)) * 0.3 }
        let sections = (0..<12).map { ShadowInstruments.SectionInput(id: UUID(), label: "S\($0)", start: Double($0) * 20, end: Double($0 + 1) * 20) }
        let embedding = (0..<d).map { Float($0 % 5) * 0.1 }
        let t0 = Date()
        let report = try ShadowInstruments.analyse(samples: x, sections: sections, production: [:], head: head) { _ in embedding }
        let dt = Date().timeIntervalSince(t0)
        print(String(format: "SPEED shadow mode (front-end + head, no Core ML): %.2f s for 240 s of audio (%d windows)", dt, Int(report.timing["windows"] ?? 0)))
        XCTAssertLessThan(dt, 10)
    }
}
