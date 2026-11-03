import XCTest
@testable import TonePilotCore

/// Sound-engine phase 2: the blend search finds a layered sound when the song's sound is layered, and
/// keeps one sound when one is enough. Stand-in embedding (band-mean of each window), synth tones.
final class BlendSearchTests: XCTestCase {
    static let sr = EfficientATFrontEnd.sampleRate
    /// Band means with the overall level removed: compares spectral shape (raw log-mel means all look
    /// alike, so their cosines sit near 1 and can't separate blends).
    static func standIn(_ w: [Float]) -> [Float] {
        let v = PerceptualPartMatchTests.standInEmbed(w)
        let mean = v.reduce(0, +) / Float(v.count)
        return v.map { $0 - mean }
    }
    static func load(_ p: InstrumentPatch) -> LoadedInstrument? { p.synth.map { LoadedInstrument(name: p.name, synth: $0) } }

    /// Distinct synth tones (different waveforms / brightness), so blends are distinguishable.
    static func tones() throws -> [InstrumentPatch] {
        let synths = FactoryPatches.all.filter { $0.synth != nil && $0.family != .percussion && $0.family != .bass }
        var seen = Set<String>(), out: [InstrumentPatch] = []
        for p in synths where !seen.contains("\(p.synth!.waveform)-\(p.filter.enabled)") {
            seen.insert("\(p.synth!.waveform)-\(p.filter.enabled)"); out.append(p)
        }
        guard out.count >= 4 else { throw XCTSkip("needs 4 distinct synth tones") }
        return out
    }

    static let notes: [MelodyNote] = (0..<14).map { i in
        MelodyNote(start: 0.2 + Double(i) * 0.55, duration: 0.45, midi: 64 + [0, 2, 4, 7, 9, 7, 4][i % 7], confidence: 1)
    }

    static func render(_ p: InstrumentPatch) -> [Float] {
        var x = ToneMatcher.render(p, instrument: load(p)!, notes: notes, seconds: 8.5, sampleRate: sr).samples
        let rms = (x.map { Double($0) * Double($0) }.reduce(0, +) / Double(x.count)).squareRoot()
        for i in x.indices { x[i] *= Float(0.1 / rms) }
        return x
    }

    func testFindsTheLayeredSoundWhenTheSongIsLayered() throws {
        let t = try Self.tones()
        // Two clearly different sounds (a bright filtered saw and a pure sine) at 80 % balance.
        let a = t[0], b = try XCTUnwrap(t.first { $0.synth?.waveform == .sine })
        let target = zip(Self.render(a), Self.render(b)).map { $0 + 0.8 * $1 }
        let r = try XCTUnwrap(BlendSearch.search(hook: target, notes: Self.notes, main: nil, candidates: t,
                                                 instrument: Self.load, embed: Self.standIn))
        let ids = Set(r.layers.map(\.patchId))
        XCTAssertTrue(ids.contains(a.id) && ids.contains(b.id), "both layers of the song's sound found: \(r.reasons)")
        XCTAssertGreaterThan(r.score, r.singleScore, "the blend beats the best single sound")
        XCTAssertEqual(r.layers.first?.balance, 1)
    }

    func testKeepsOneSoundWhenOneIsEnough() throws {
        let t = try Self.tones()
        let target = Self.render(t[2])
        let r = try XCTUnwrap(BlendSearch.search(hook: target, notes: Self.notes, main: nil, candidates: t,
                                                 instrument: Self.load, embed: Self.standIn))
        XCTAssertEqual(r.layers.map(\.patchId), [t[2].id], "no unnecessary layers: \(r.reasons)")
        XCTAssertEqual(r.singleBest, t[2].id)
        XCTAssertFalse(r.alternatives.contains(t[2].id))
    }

    func testLimitsAndLabelsAreRespected() throws {
        let t = try Self.tones()
        let target = zip(Self.render(t[0]), Self.render(t[1])).map { $0 + 0.55 * $1 }
        var p = BlendSearch.Parameters(); p.maxLayers = 1; p.approximateBelow = 1.01
        let r = try XCTUnwrap(BlendSearch.search(hook: target, notes: Self.notes, main: nil, candidates: t,
                                                 instrument: Self.load, embed: Self.standIn, parameters: p))
        XCTAssertEqual(r.layers.count, 1, "layer limit respected")
        XCTAssertTrue(r.approximate, "labelled approximate below the threshold")
    }
}
