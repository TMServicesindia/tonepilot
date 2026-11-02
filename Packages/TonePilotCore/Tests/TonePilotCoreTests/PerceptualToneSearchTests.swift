import XCTest
@testable import TonePilotCore

/// Perceptual tone search: the Swift front-end's harmonic mask matches the Python research path,
/// windowing matches, and ranking picks the nearest library tone (best register).
final class PerceptualToneSearchTests: XCTestCase {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/instruments/efficientat", isDirectory: true)
    func fixture(_ name: String) throws -> [Float] { try InferenceContract.readFloats(Self.dir.appendingPathComponent("\(name).f32")) }

    func testHarmonicMaskMatchesPythonResearchPath() throws {
        let audio = try fixture("audio"), ref = try fixture("mel_harmonic_mask")
        let notes = [MelodyNote(start: 0.2, duration: 0.6, midi: 64, confidence: 1),
                     MelodyNote(start: 0.9, duration: 0.5, midi: 67, confidence: 1),
                     MelodyNote(start: 1.5, duration: 0.8, midi: 71, confidence: 1)]
        let mel = EfficientATFrontEnd.logMel(audio, keepHarmonicsOf: notes)
        XCTAssertEqual(mel.values.count, ref.count)
        var worst: Float = 0
        for i in 0..<min(ref.count, mel.values.count) { worst = max(worst, abs(ref[i] - mel.values[i])) }
        print(String(format: "PERCEPTUAL masked mel max |diff| vs Python %.2e", worst))
        XCTAssertLessThan(worst, 1e-3)
        // Unmasked path is unchanged.
        XCTAssertEqual(EfficientATFrontEnd.logMel(audio).values, EfficientATFrontEnd.logMel(audio, keepHarmonicsOf: nil).values)
    }

    func testWindowsMatchPythonPadding() {
        let frames = 250, values = (0..<(128 * frames)).map { Float($0 % 7) }
        let w = PerceptualToneSearch.windows(frames: frames, values: values)
        XCTAssertEqual(w.count, 3)   // starts 0, 50, 100 (149 would overrun 250 - 101 = 149 → included)
        let short = PerceptualToneSearch.windows(frames: 40, values: [Float](repeating: 1, count: 128 * 40))
        XCTAssertEqual(short.count, 1)
        XCTAssertEqual(short[0][100], Float((log(1e-5) + 4.5) / 5), accuracy: 1e-6)   // padded tail
    }

    func testRankPicksNearestToneAndBestRegister() {
        let a = UUID(), b = UUID()
        let table = PerceptualToneSearch.ToneTable(version: 1, model: "test", embeddingDim: 3, entries: [
            .init(patch: a, register: 48, embedding: [1, 0, 0]), .init(patch: a, register: 60, embedding: [0, 1, 0]),
            .init(patch: b, register: 48, embedding: [0.7, 0.7, 0])])
        XCTAssertTrue(table.isValid)
        let r = PerceptualToneSearch.rank([0, 1, 0.05], table: table)
        XCTAssertEqual(r.first?.patch, a)                                         // a's 60 register matches exactly
        XCTAssertEqual(PerceptualToneSearch.rank([0, 1, 0], table: table, allowed: [b]).map(\.patch), [b])
        XCTAssertTrue(PerceptualToneSearch.rank([1, 2], table: table).isEmpty)   // wrong dimension
    }

    func testEmbeddingIsMeanOverWindows() throws {
        let x = (0..<(32_000 * 3)).map { Float(sin(Double($0) * 0.05)) * 0.3 }
        var calls = 0
        let e = PerceptualToneSearch.embedding(samples: x, notes: nil) { w -> [Float] in
            XCTAssertEqual(w.count, 128 * 101); calls += 1; return [Float(calls), 1]
        }
        XCTAssertNotNil(e)
        XCTAssertEqual(Double(e![1]), 1, accuracy: 1e-6)
        XCTAssertEqual(Double(e![0]), Double(calls + 1) / 2, accuracy: 1e-6)
    }
}

/// Speed budget: the perceptual search's own work for one 24 s part (masked front-end + windowing +
/// ranking against a full-size table: 130 tones × 3 registers × 960 dims), stand-in model. The Core ML
/// call itself is measured on device (TonePilot Lab) and was ≈ 4 ms per window on Mac CI. Release only.
final class PerceptualToneSearchSpeedTests: XCTestCase {
    func testPerceptualSearchForOnePartIsQuick() throws {
        #if DEBUG
        throw XCTSkip("speed budgets are checked in release builds (swift test -c release)")
        #endif
        let sr = EfficientATFrontEnd.sampleRate
        let x = (0..<Int(24 * sr)).map { Float(sin(Double($0) * 0.05)) * 0.3 }
        let notes = (0..<40).map { MelodyNote(start: 0.3 + Double($0) * 0.55, duration: 0.45, midi: 60 + ($0 * 5) % 12, confidence: 1) }
        let entries = (0..<390).map { i in PerceptualToneSearch.ToneTable.Entry(patch: UUID(), register: i % 3, embedding: (0..<960).map { Float(($0 + i) % 11) * 0.1 }) }
        let table = PerceptualToneSearch.ToneTable(version: 1, model: "speed", embeddingDim: 960, entries: entries)
        let t0 = Date()
        let e = PerceptualToneSearch.embedding(samples: x, notes: notes) { _ in [Float](repeating: 0.5, count: 960) }
        let ranked = PerceptualToneSearch.rank(e!, table: table)
        let dt = Date().timeIntervalSince(t0)
        print(String(format: "SPEED perceptual tone search (front-end + mask + rank, no Core ML): %.2f s for a 24 s part, %d tones", dt, ranked.count))
        XCTAssertLessThan(dt, 3)
    }
}
