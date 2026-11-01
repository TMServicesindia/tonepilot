import Foundation
import XCTest
@testable import TonePilotBridge
@testable import TonePilotCore

/// The pieces the Android emulator runs (FixtureCheck, CallbackInferenceBackend) behave the same
/// here, so an Android failure points at the platform, not the shared code.
final class CrossPlatformFixtureTests: XCTestCase {
    func testBridgeTestSongIsIdenticalToTheRecordedOne() {
        let a = FixtureCheck.syntheticSong(pattern: ["A", "B", "A", "B"], beatsPerSection: 32)
        let b = SyntheticSong.render(pattern: ["A", "B", "A", "B"], beatsPerSection: 32)
        XCTAssertEqual(a.samples, b.samples)
        XCTAssertEqual(a.sampleRate, b.sampleRate)
    }

    func testMixOnlyFixtureCheckPasses() throws {
        let expected = try Data(contentsOf: PipelineFixtures.dir.appendingPathComponent("mix-only.json"))
        let (ok, d) = try FixtureCheck.checkMixOnly(expectedJSON: expected)
        XCTAssertTrue(ok, d ?? "")
    }

    /// The C-callback back-end passes the same contract, with a callback written in Swift that
    /// answers from the fixture by back-end tensor name (exercises the whole C ABI).
    func testCallbackBackendPassesTheContractThroughTheCInterface() throws {
        let model = FileManager.default.temporaryDirectory.appendingPathComponent("cb-\(UUID().uuidString).tflite")
        try Data([1]).write(to: model)
        let fixture = try InferenceContract.loadFixture(dir: InferenceBackendTests.fixtureDir, modelURL: model, tolerance: 1e-3)
        TestCallback.fixture = fixture
        let backend = CallbackInferenceBackend(function: TestCallback.handle)
        let report = InferenceContract.run(backend, fixture)
        XCTAssertTrue(report.passed, "\(report.checks) \(report.notes)")
        XCTAssertEqual(report.maxAbsDiff["contour"], 0)
    }
}

/// Mimics the Android side of tp_set_inference_callback: parse the JSON request, answer in the
/// documented response format, write outputs into the caller's buffer.
enum TestCallback {
    nonisolated(unsafe) static var fixture: InferenceContract.Fixture?
    nonisolated(unsafe) static var loaded: Set<String> = []

    static let handle: TPInferFunction = { request, input, inputCount, output, capacity, response, responseCap in
        func reply(_ obj: [String: Any]) -> Int32 {
            let s = String(data: try! JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!
            _ = s.withCString { strncpy(response, $0, Int(responseCap) - 1) }
            return obj["ok"] as? Bool == true ? 0 : 1
        }
        guard let f = TestCallback.fixture,
              let req = try? JSONSerialization.jsonObject(with: Data(String(cString: request).utf8)) as? [String: Any],
              let op = req["op"] as? String, let model = req["model"] as? String else { return reply(["ok": false, "error": "bad request"]) }
        switch op {
        case "load":
            guard let path = req["path"] as? String, FileManager.default.fileExists(atPath: path) else {
                return reply(["ok": false, "kind": "loadFailed", "error": "no file"])
            }
            TestCallback.loaded.insert(model)
            return reply(["ok": true])
        case "unload":
            TestCallback.loaded.remove(model)
            return reply(["ok": true])
        case "run":
            guard TestCallback.loaded.contains(model) else { return reply(["ok": false, "kind": "modelNotLoaded", "error": "not loaded"]) }
            let total = (req["inputs"] as? [[String: Any]] ?? []).reduce(0) { $0 + ($1["count"] as? Int ?? 0) }
            guard Int64(total) == inputCount else { return reply(["ok": false, "error": "input size"]) }
            var offset = 0, specs: [[String: Any]] = []
            for spec in req["outputs"] as? [[String: Any]] ?? [] {
                let name = spec["name"] as! String
                guard let logical = f.descriptor.outputs.keys.first(where: { f.descriptor.backendName($0, for: "litert") == name }),
                      let t = f.expected[logical], offset + t.count <= Int(capacity), let output else { return reply(["ok": false, "error": "output"]) }
                for i in 0..<t.count { output[offset + i] = t.values[i] }
                specs.append(["name": name, "shape": t.shape, "offset": offset, "count": t.count])
                offset += t.count
            }
            return reply(["ok": true, "outputs": specs])
        default:
            return reply(["ok": false, "error": "unknown op"])
        }
    }
}
