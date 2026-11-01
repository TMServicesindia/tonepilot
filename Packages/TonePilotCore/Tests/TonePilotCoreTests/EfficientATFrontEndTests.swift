import Foundation
import XCTest
@testable import TonePilotCore

/// Gate 2: the Swift EfficientAT mel front-end must reproduce the PyTorch front-end
/// (fixture from coreml-gate2.yml, EfficientAT a425fdc, mn10_as preprocessing).
final class EfficientATFrontEndTests: XCTestCase {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/instruments/efficientat", isDirectory: true)

    func testLogMelMatchesPyTorch() throws {
        let audio = try InferenceContract.readFloats(Self.dir.appendingPathComponent("audio.f32"))
        let ref = try InferenceContract.readFloats(Self.dir.appendingPathComponent("mel.f32"))
        let mel = EfficientATFrontEnd.logMel(audio)
        XCTAssertEqual(mel.frames, 250)
        XCTAssertEqual(mel.values.count, ref.count)
        var maxDiff: Float = 0
        for i in 0..<min(ref.count, mel.values.count) { maxDiff = max(maxDiff, abs(ref[i] - mel.values[i])) }
        print(String(format: "EFFICIENTAT front-end max |diff| %.2e", maxDiff))
        XCTAssertLessThan(maxDiff, 1e-3)
    }

    func testSpeedFourMinuteSong() {
        let x = (0..<(240 * 32_000)).map { Float(sin(Double($0) * 0.05)) * 0.3 }
        let t0 = Date(); let m = EfficientATFrontEnd.logMel(x); let dt = Date().timeIntervalSince(t0)
        print(String(format: "SPEED EfficientAT front-end: %.2f s for 240 s of audio (%d frames)", dt, m.frames))
    }
}
