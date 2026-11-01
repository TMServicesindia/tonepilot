import Foundation
import XCTest
@testable import TonePilotCore

/// Phase 2: the Swift side of Beat This! must reproduce the official Python front-end and
/// post-processing. Fixtures come from `beat-this-convert.yml` (official code + small0 checkpoint).
final class BeatThisTests: XCTestCase {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/rhythm/beat_this", isDirectory: true)

    static func floats(_ name: String) throws -> [Float] { try InferenceContract.readFloats(dir.appendingPathComponent(name)) }
    static func audio() throws -> [Float] {
        let d = try Data(contentsOf: dir.appendingPathComponent("audio.s16"))
        return d.withUnsafeBytes { raw in raw.bindMemory(to: Int16.self).map { Float(Int16(littleEndian: $0)) / 32767 } }
    }
    struct Reference: Decodable { let beats: [Double]; let downbeats: [Double]; let frames: Int }
    static func reference() throws -> Reference { try JSONDecoder().decode(Reference.self, from: Data(contentsOf: dir.appendingPathComponent("reference.json"))) }

    func testLogMelMatchesOfficialFrontEnd() throws {
        let ref = try Self.floats("mel.f32"), r = try Self.reference()
        let mel = BeatThis.logMel(try Self.audio())
        XCTAssertEqual(mel.frames, r.frames)
        XCTAssertEqual(mel.values.count, ref.count)
        var maxDiff: Float = 0, maxVal: Float = 0
        for i in 0..<min(ref.count, mel.values.count) { maxDiff = max(maxDiff, abs(ref[i] - mel.values[i])); maxVal = max(maxVal, abs(ref[i])) }
        print(String(format: "BEAT_THIS log-mel max |diff| %.2e (max value %.2f)", maxDiff, maxVal))
        XCTAssertLessThan(maxDiff, 1e-3)
    }

    func testPostprocessingMatchesOfficialTimes() throws {
        let r = try Self.reference()
        let out = BeatThis.postprocess(beat: try Self.floats("beat.f32"), downbeat: try Self.floats("downbeat.f32"))
        XCTAssertEqual(out.beats.count, r.beats.count)
        XCTAssertEqual(out.downbeats.count, r.downbeats.count)
        for (a, b) in zip(out.beats, r.beats) { XCTAssertEqual(a, b, accuracy: 1e-9) }
        for (a, b) in zip(out.downbeats, r.downbeats) { XCTAssertEqual(a, b, accuracy: 1e-9) }
    }

    func testChunkStartsMatchOfficialSplit() {
        // split_piece(…, 1500, border 6, avoid_short_end): starts = arange(-6, n-6, 1488), last moved to n-1494.
        XCTAssertEqual(BeatThis.chunkStarts(frames: 1701), [-6, 207])
        XCTAssertEqual(BeatThis.chunkStarts(frames: 1000), [-6])
        XCTAssertEqual(BeatThis.chunkStarts(frames: 4000), [-6, 1482, 2506])
    }

    /// The chunking/aggregation reproduces the official whole-piece logits when the back-end
    /// returns the reference logits for each chunk window (a replay of the real model).
    func testAggregationReproducesReferenceLogits() throws {
        let beat = try Self.floats("beat.f32"), down = try Self.floats("downbeat.f32"), r = try Self.reference()
        final class Window: InferenceBackend, @unchecked Sendable {
            let id = "window"
            func isLoaded(_ model: String) -> Bool { true }
            let beat: [Float], down: [Float], frames: Int
            var calls = 0; let starts: [Int]
            init(beat: [Float], down: [Float], frames: Int) { self.beat = beat; self.down = down; self.frames = frames; starts = BeatThis.chunkStarts(frames: frames).reversed() }
            func load(_ d: ModelDescriptor, from url: URL) throws {}
            func unload(_ model: String) {}
            func run(_ model: String, inputs: [String: Tensor]) throws -> [String: Tensor] {
                let s = starts[calls]; calls += 1
                var b = [Float](repeating: 0, count: BeatThis.chunk), dd = b
                for i in 0..<BeatThis.chunk where s + i >= 0 && s + i < frames { b[i] = beat[s + i]; dd[i] = down[s + i] }
                return ["beat": try Tensor(shape: [1, BeatThis.chunk], values: b), "downbeat": try Tensor(shape: [1, BeatThis.chunk], values: dd)]
            }
        }
        let mel = (frames: r.frames, values: [Float](repeating: 0, count: r.frames * BeatThis.nMels))
        let out = try BeatThis.frameLogits(mel: mel, backend: Window(beat: beat, down: down, frames: r.frames))
        XCTAssertEqual(out.beat, beat)
        XCTAssertEqual(out.downbeat, down)
    }
}
