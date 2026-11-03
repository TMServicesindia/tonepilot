import XCTest
@testable import TonePilotCore

/// Real-instrument sound packs (phase 1): a pack.json as the CI builder writes it decodes, is
/// checked for playability, becomes library patches, plays through ToneEngine's multisample path
/// (looped sustain longer than the recording), and its embeddings join the nearest-sound tables.
final class SoundPackTests: XCTestCase {
    static let sr = 32_000.0

    /// A tiny pack in the builder's exact format: sine "recordings" every octave, 1 s long, looped.
    func makePack(in dir: URL) throws -> SoundPack {
        let packDir = dir.appendingPathComponent("packs/test-sines")
        try FileManager.default.createDirectory(at: packDir, withIntermediateDirectories: true)
        var zones: [[String: Any]] = [], files: [String: Any] = [:]
        let roots = [36, 48, 60, 72, 84, 96]
        for (i, r) in roots.enumerated() {
            let f = 440 * pow(2, (Double(r) - 69) / 12)
            let n = Int(Self.sr)
            // Whole periods in the loop so it is seamless.
            let x = (0..<n).map { Float(0.5 * sin(2 * .pi * f * Double($0) / Self.sr)) }
            let name = String(format: "%03d_v1.wav", r)
            try WAVDecoder.encode16(x, sampleRate: Int(Self.sr)).write(to: packDir.appendingPathComponent(name))
            let period = Self.sr / f, loopLen = Int((Double(Int(0.4 * Self.sr / period)) * period).rounded())
            let lo = i == 0 ? 0 : (roots[i - 1] + r) / 2 + 1, hi = i == roots.count - 1 ? 127 : (r + roots[i + 1]) / 2
            zones.append(["fileName": "packs/test-sines/\(name)", "rootNote": r, "keyRange": ["low": lo, "high": hi],
                          "velocityRange": ["low": 1, "high": 127], "startFrame": 0, "loopStart": 16_000, "loopEnd": 16_000 + loopLen])
            files[name] = ["sha256": "x", "bytes": 0, "frames": n]
        }
        let json: [String: Any] = [
            "format": 1, "id": "test-sines", "version": 1, "name": "Test sines", "family": "strings", "sampleRate": Self.sr,
            "source": ["library": "https://example.org", "license": "CC0-1.0", "commit": "abc", "files": ["a.wav"]],
            "tones": [["id": "877D29BC-7F85-5861-B21B-7B72EFDC878A", "name": "Test strings", "family": "strings",
                       "envelope": ["attack": 0.01, "decay": 0.3, "sustain": 1.0, "release": 0.4], "zones": zones]],
            "files": files,
            "embeddings": ["harmonic": [["patch": "877D29BC-7F85-5861-B21B-7B72EFDC878A", "register": 60, "embedding": [1, 0, 0]]],
                           "plain": [["patch": "877D29BC-7F85-5861-B21B-7B72EFDC878A", "register": 60, "embedding": [0, 1, 0]]]]]
        let data = try JSONSerialization.data(withJSONObject: json)
        try data.write(to: packDir.appendingPathComponent("pack.json"))
        return try SoundPack.decode(data)
    }

    func testPackDecodesChecksAndBecomesPlayablePatches() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pack = try makePack(in: dir)
        XCTAssertEqual(pack.problems(), [], "every 61-key note covered, files listed, loops valid")
        let patch = try XCTUnwrap(pack.patches.first)
        XCTAssertEqual(patch.id.uuidString, "877D29BC-7F85-5861-B21B-7B72EFDC878A", "stable tone id across rebuilds")
        XCTAssertEqual(patch.sourceType, .licensedSample); XCTAssertEqual(patch.family, .strings)
        XCTAssertEqual(patch.license.name, "CC0-1.0")

        // Plays through the engine's multisample path; a held note sustains past the 1 s recording (loop).
        let samples = try patch.sampleZones.map { z in
            let d = try WAVDecoder.decodeMono(url: dir.appendingPathComponent(z.fileName))
            return LoadedInstrument.UserSample(frames: d.frames, sampleRate: d.sampleRate, zone: z)
        }
        let inst = LoadedInstrument(name: patch.name, userSamples: samples, envelope: patch.envelope)
        let note = MelodyNote(start: 0.1, duration: 2.5, midi: 67, confidence: 1)   // between roots → transposed
        let out = ToneMatcher.render(patch, instrument: inst, notes: [note], seconds: 3, sampleRate: Self.sr).samples
        func rms(_ a: Double, _ b: Double) -> Float {
            let s = out[Int(a * Self.sr)..<Int(b * Self.sr)]; return (s.map { $0 * $0 }.reduce(0, +) / Float(s.count)).squareRoot()
        }
        XCTAssertGreaterThan(rms(0.3, 0.9), 0.02)
        XCTAssertGreaterThan(rms(2.0, 2.5), rms(0.3, 0.9) * 0.5, "still sounding at 2–2.5 s: the loop sustains")
        // Pitch of the transposed note (zero crossings).
        let seg = Array(out[Int(0.5 * Self.sr)..<Int(1.5 * Self.sr)])
        var crossings = 0
        for i in 1..<seg.count where (seg[i - 1] < 0) != (seg[i] < 0) { crossings += 1 }
        XCTAssertEqual(Double(crossings) / 2, 440 * pow(2, -2.0 / 12), accuracy: 6, "G4 from the C4/C5 recordings")
    }

    func testPackEmbeddingsJoinTheSearchTables() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pack = try makePack(in: dir)
        let base = PerceptualToneSearch.ToneTable(version: 1, model: "m", embeddingDim: 3,
                                                  entries: [.init(patch: UUID(), register: 60, embedding: [0, 0, 1])])
        let merged = base.adding(pack.embeddings!.harmonic + [.init(patch: UUID(), register: 60, embedding: [1, 2])])
        XCTAssertEqual(merged.entries.count, 2, "pack entry added; a wrong-size entry ignored")
        XCTAssertTrue(merged.isValid)
        XCTAssertEqual(PerceptualToneSearch.rank([1, 0, 0], table: merged).first?.patch, pack.tones[0].id)
    }

    func testProblemsAreReported() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        var pack = try makePack(in: dir)
        pack.tones[0].zones.removeAll { $0.rootNote == 60 || $0.rootNote == 72 }
        XCTAssertTrue(pack.problems().contains { $0.contains("not covered") })
        pack.tones[0].zones[0].fileName = "elsewhere/x.wav"
        XCTAssertTrue(pack.problems().contains { $0.contains("outside the pack folder") })
    }
}
