import Foundation
import XCTest
@testable import TonePilotCore

/// Inference contract on Linux with the replay back-end, using the Basic Pitch test-model
/// fixture. This proves the contract and the code around inference; real back-end compatibility
/// is proven by the Core ML (macOS CI) and LiteRT (Android emulator) runs of the same contract.
final class InferenceBackendTests: XCTestCase {
    static let fixtureDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/inference/basic_pitch")

    func fixture(modelFile: URL) throws -> InferenceContract.Fixture {
        try InferenceContract.loadFixture(dir: Self.fixtureDir, modelURL: modelFile, tolerance: 1e-3)
    }

    /// A stand-in model file (the replay back-end only checks that it exists).
    func stubModelFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("replay-\(UUID().uuidString).model")
        try Data([1]).write(to: url)
        return url
    }

    func testFixtureIsWellFormed() throws {
        let f = try fixture(modelFile: stubModelFile())
        XCTAssertEqual(f.descriptor.inputs["audio"], [1, 43_844, 1])
        XCTAssertEqual(f.descriptor.outputs["note"], [1, 172, 88])
        XCTAssertEqual(f.descriptor.outputs["onset"], [1, 172, 88])
        XCTAssertEqual(f.descriptor.outputs["contour"], [1, 172, 264])
        XCTAssertEqual(f.descriptor.backendName("note", for: "coreml"), "Identity_1")
        XCTAssertEqual(f.descriptor.backendName("audio", for: "litert"), "input_2")
        XCTAssertTrue(f.expected.values.allSatisfy { $0.values.allSatisfy(\.isFinite) })
        XCTAssertGreaterThan(f.expected["note"]!.values.max() ?? 0, 0.1, "the test chord produces note activations")
    }

    func testReplayBackendPassesTheContract() throws {
        let f = try fixture(modelFile: stubModelFile())
        let backend = ReplayBackend()
        backend.record(f.descriptor.name, outputs: f.expected)
        let report = InferenceContract.run(backend, f)
        XCTAssertTrue(report.passed, "\(report.checks) \(report.notes)")
        XCTAssertEqual(report.maxAbsDiff["note"], 0)
    }

    /// The contract really fails a back-end that returns wrong numbers or shapes.
    func testContractCatchesWrongNumbersAndShapes() throws {
        let f = try fixture(modelFile: stubModelFile())
        let off = ReplayBackend()
        var shifted = f.expected
        shifted["note"] = try Tensor(shape: f.expected["note"]!.shape, values: f.expected["note"]!.values.map { $0 + 0.01 })
        off.record(f.descriptor.name, outputs: shifted)
        let r1 = InferenceContract.run(off, f)
        XCTAssertEqual(r1.checks["numeric-tolerance"], false)
        XCTAssertFalse(r1.passed)

        let badShape = ReplayBackend()
        var wrong = f.expected
        wrong["contour"] = try Tensor(shape: [1, 172, 88], values: [Float](repeating: 0, count: 172 * 88))
        badShape.record(f.descriptor.name, outputs: wrong)
        XCTAssertFalse(InferenceContract.run(badShape, f).passed)
    }

    func testTensorAndDescriptorValidation() throws {
        XCTAssertThrowsError(try Tensor(shape: [2, 3], values: [1, 2, 3]))
        let d = ModelDescriptor(name: "m", inputs: ["x": [1, 2]], outputs: ["y": [1]])
        XCTAssertThrowsError(try d.validate(inputs: [:]))
        XCTAssertThrowsError(try d.validate(inputs: ["x": Tensor(shape: [2, 1], values: [0, 0])]))
        XCTAssertThrowsError(try d.validate(inputs: ["x": Tensor(shape: [1, 2], values: [0, 0]), "z": Tensor(shape: [1], values: [0])]))
        XCTAssertNoThrow(try d.validate(inputs: ["x": Tensor(shape: [1, 2], values: [0, 0])]))
        let r = ReplayBackend()
        XCTAssertThrowsError(try r.load(d, from: URL(fileURLWithPath: "/nonexistent/model"))) { e in
            guard case InferenceError.loadFailed = e else { return XCTFail("\(e)") }
        }
    }

    func testRegistryHoldsThePlatformBackend() {
        let previous = InferenceRegistry.backend
        defer { InferenceRegistry.backend = previous }
        let r = ReplayBackend()
        InferenceRegistry.backend = r
        XCTAssertEqual(InferenceRegistry.backend?.id, "replay")
    }
}
