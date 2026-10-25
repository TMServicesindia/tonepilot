import XCTest
@testable import TonePilotCore

/// Builds deterministic test songs so analysis can be verified against known ground truth.
enum SyntheticSong {
    static let sr = 22_050.0

    static func midiFreq(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }

    /// Triad pitches (MIDI) for chord symbols used below.
    static let chords: [String: [Double]] = [
        "C": [60, 64, 67], "F": [65, 69, 72], "G": [67, 71, 74],
        "Am": [57, 60, 64], "Dm": [62, 65, 69], "Em": [64, 67, 71],
    ]

    /// Section A: bright plucked chords re-struck every beat with a kick click (rhythmic, loud).
    /// Section B: dark sustained pad chords, no percussion (smooth, quieter).
    static func render(pattern: [Character], bpm: Double = 120, beatsPerSection: Int = 32) -> AudioBuffer {
        let beat = 60 / bpm
        let sectionLen = Double(beatsPerSection) * beat
        let total = Int(Double(pattern.count) * sectionLen * sr)
        var x = [Float](repeating: 0, count: total)
        var rng: UInt64 = 0x1234_5678
        func noise() -> Float {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            return Float(Int64(bitPattern: rng >> 11) % 2000) / 1000 - 1
        }
        for (si, kind) in pattern.enumerated() {
            let progression = kind == "A" ? ["C", "F", "G", "C"] : ["Am", "Dm", "Em", "Am"]
            let start = Double(si) * sectionLen
            for b in 0..<beatsPerSection {
                let t0 = start + Double(b) * beat
                let chord = chords[progression[b * progression.count / beatsPerSection]]!
                let n0 = Int(t0 * sr), n1 = min(total, Int((t0 + beat) * sr))
                for n in n0..<n1 {
                    let t = Double(n) / sr - t0
                    var v = 0.0
                    for m in chord {
                        let f = midiFreq(m)
                        if kind == "A" {
                            let env = exp(-t * 6)
                            v += env * (sin(2 * .pi * f * t) + 0.5 * sin(4 * .pi * f * t) + 0.3 * sin(6 * .pi * f * t))
                        } else {
                            let tt = Double(n) / sr
                            v += 0.35 * (sin(2 * .pi * f * tt) + 0.2 * sin(4 * .pi * f * tt))
                        }
                    }
                    if kind == "A", t < 0.03 {
                        v += 1.2 * exp(-t * 150) * sin(2 * .pi * 60 * t) + 0.3 * Double(noise()) * exp(-t * 200)
                    }
                    x[n] += Float(v * 0.15)
                }
            }
        }
        return AudioBuffer(samples: x, sampleRate: sr)
    }
}

final class AnalysisTests: XCTestCase {
    func testFFTFindsSinePeak() {
        let n = 2048, sr = 22_050.0, f = 1000.0
        let x = (0..<n).map { Float(sin(2 * .pi * f * Double($0) / sr)) }
        var mag: [Float] = []
        MagnitudeFFT(size: n).magnitudes(x, offset: 0, into: &mag)
        let peak = mag.indices.max { mag[$0] < mag[$1] }!
        XCTAssertEqual(Double(peak) * sr / Double(n), f, accuracy: sr / Double(n))
    }

    func testTempoAndBeatsOnClickTrack() throws {
        let audio = SyntheticSong.render(pattern: ["A", "A"], bpm: 120, beatsPerSection: 16)
        let features = try XCTUnwrap(FeatureExtractor.extract(audio))
        let tempo = try XCTUnwrap(TempoAnalyzer.analyze(features))
        XCTAssertEqual(tempo.bpm, 120, accuracy: 2.5)
        // Beats should land within 40 ms of the true 0.5 s grid.
        let interior = tempo.beats.filter { $0 > 1 && $0 < audio.duration - 1 }
        XCTAssertGreaterThan(interior.count, 20)
        for b in interior {
            let err = abs(b - (b / 0.5).rounded() * 0.5)
            XCTAssertLessThan(err, 0.04, "beat at \(b)")
        }
    }

    func testOtherTempo() throws {
        let audio = SyntheticSong.render(pattern: ["A", "A"], bpm: 92, beatsPerSection: 16)
        let tempo = try XCTUnwrap(TempoAnalyzer.analyze(XCTUnwrap(FeatureExtractor.extract(audio))))
        XCTAssertEqual(tempo.bpm, 92, accuracy: 2.5)
    }

    func testKeyEstimateForCMajorProgression() throws {
        let audio = SyntheticSong.render(pattern: ["A", "A"], beatsPerSection: 16)
        let features = try XCTUnwrap(FeatureExtractor.extract(audio))
        let key = try XCTUnwrap(HarmonyAnalyzer.estimateKey(chroma: features.chroma))
        XCTAssertEqual(key.value, MusicalKey(tonic: 0, mode: .major))
        XCTAssertEqual(key.provenance, .algorithm)
    }

    func testKeyEstimateForAMinorProgression() throws {
        let audio = SyntheticSong.render(pattern: ["B", "B"], beatsPerSection: 16)
        let key = try XCTUnwrap(HarmonyAnalyzer.estimateKey(chroma: XCTUnwrap(FeatureExtractor.extract(audio)).chroma))
        XCTAssertEqual(key.value, MusicalKey(tonic: 9, mode: .minor))
    }

    func testChordRecognitionFollowsProgression() throws {
        let audio = SyntheticSong.render(pattern: ["A"], beatsPerSection: 32)
        let result = try SongAnalyzer.analyze(audio)
        let symbols = result.chords.filter { $0.duration >= 1 }.map(\.symbol)
        // Expect C F G C (each 8 beats = 4 s).
        XCTAssertEqual(symbols, ["C", "F", "G", "C"], "got \(result.chords.map { "\($0.symbol)@\($0.time)" })")
    }

    func testStructureFindsRepeatedSections() throws {
        let audio = SyntheticSong.render(pattern: ["A", "B", "A", "B"], beatsPerSection: 32)
        let result = try SongAnalyzer.analyze(audio)
        let starts = result.sections.map(\.startTime)
        XCTAssertEqual(result.sections.count, 4, "sections: \(result.sections.map { ($0.label, $0.startTime) })")
        for (found, expected) in zip(starts, [0.0, 16, 32, 48]) {
            XCTAssertEqual(found, expected, accuracy: 1.0)
        }
        let groups = result.sections.map { $0.repetitionGroup ?? "?" }
        XCTAssertEqual(groups[0], groups[2])
        XCTAssertEqual(groups[1], groups[3])
        XCTAssertNotEqual(groups[0], groups[1])
        XCTAssertTrue(result.sections.allSatisfy { $0.provenance == .algorithm && $0.confidence <= 0.5 },
                      "guessed labels must stay low-confidence")
        XCTAssertEqual(result.sections.last?.endTime ?? 0, audio.duration, accuracy: 0.01)
    }

    func testSuggestionsDifferBetweenPluckedAndSustainedSections() throws {
        let audio = SyntheticSong.render(pattern: ["A", "B", "A", "B"], beatsPerSection: 32)
        let result = try SongAnalyzer.analyze(audio)
        let first = result.sections[0], second = result.sections[1]
        let ta = try XCTUnwrap(result.timbres[first.id]), tb = try XCTUnwrap(result.timbres[second.id])
        XCTAssertGreaterThan(tb.sustain, ta.sustain)
        XCTAssertGreaterThan(ta.onsetRate, tb.onsetRate)
        let topB = result.suggestions.first { $0.sectionId == second.id }
        XCTAssertTrue([.strings, .pad].contains(topB?.family), "sustained section should suggest strings/pad, got \(String(describing: topB?.family))")
        let topA = result.suggestions.first { $0.sectionId == first.id }
        XCTAssertTrue([.piano, .pluck].contains(topA?.family), "plucked section got \(String(describing: topA?.family))")
        XCTAssertTrue(result.suggestions.allSatisfy { $0.method == .featureHeuristic && $0.confidence <= 0.5 })
    }

    func testRejectsShortAndSilentAudioAndSupportsCancel() {
        XCTAssertThrowsError(try SongAnalyzer.analyze(AudioBuffer(samples: [Float](repeating: 0, count: 22_050), sampleRate: 22_050))) {
            XCTAssertEqual($0 as? SongAnalysisError, .tooShort)
        }
        XCTAssertThrowsError(try SongAnalyzer.analyze(AudioBuffer(samples: [Float](repeating: 0, count: 22_050 * 10), sampleRate: 22_050))) {
            XCTAssertEqual($0 as? SongAnalysisError, .silent)
        }
        let audio = SyntheticSong.render(pattern: ["A"], beatsPerSection: 32)
        XCTAssertThrowsError(try SongAnalyzer.analyze(audio, progress: { _ in false })) {
            XCTAssertEqual($0 as? SongAnalysisError, .cancelled)
        }
    }
}
