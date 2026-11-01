import XCTest
@testable import TonePilotCore

/// "No fill unless sure" (investigation; not wired into the app): basic safety properties on
/// additive-tone material, so they hold in every build without the SoundFont benchmark.
final class AccompanimentClassifierTests: XCTestCase {
    static let sr = 22_050.0, beat = 0.6

    /// 8 bars of 4/4 over C | Am | F | G. `notes(bar, beat) -> [(offsetInBeat, midi, duration)]`.
    static func song(_ notes: (Int, Int) -> [(Double, Int, Double)]) -> (AudioBuffer, [Double], [ChordEvent], SongSection) {
        let bars = 8, total = Double(bars * 4) * beat + 1
        var x = [Float](repeating: 0, count: Int(total * sr))
        for bar in 0..<bars { for b in 0..<4 { for (off, m, dur) in notes(bar, b) {
            let t0 = (Double(bar * 4 + b) + off) * beat, f = 440 * pow(2, Double(m - 69) / 12)
            let s = Int(t0 * sr), e = min(x.count, s + Int(dur * sr))
            guard s < e else { continue }
            for k in s..<e { let t = Double(k - s) / sr; x[k] += Float(0.2 * sin(2 * .pi * f * t) * exp(-t * 3) + 0.06 * sin(4 * .pi * f * t) * exp(-t * 4)) }
        } } }
        let beats = (0...(bars * 4)).map { Double($0) * beat }
        let names = ["C", "Am", "F", "G"]
        let chords = (0..<bars).map { ChordEvent(time: Double($0 * 4) * beat, duration: 4 * beat, symbol: names[$0 % 4], confidence: 1) }
        return (AudioBuffer(samples: x, sampleRate: sr), beats, chords, SongSection(type: .verse, startTime: 0, endTime: Double(bars * 4) * beat))
    }
    static let roots = [48, 45, 41, 43], minor = [false, true, false, false]

    func verdict(_ s: (AudioBuffer, [Double], [ChordEvent], SongSection)) -> AccompanimentClassifier.Verdict {
        AccompanimentClassifier.classify(.init(music: s.0), beats: s.1, chords: s.2, section: s.3)
    }

    func testSilenceGetsNoFill() {
        let v = verdict(Self.song { _, _ in [] })
        XCTAssertFalse(v.allowsArpeggio)
    }

    func testHeldChordsNeverGetAnArpeggio() {
        let v = verdict(Self.song { bar, b in
            guard b == 0 else { return [] }
            let r = Self.roots[bar % 4]
            return [(0, r, 4 * Self.beat * 0.98), (0, r + (Self.minor[bar % 4] ? 3 : 4), 4 * Self.beat * 0.98), (0, r + 7, 4 * Self.beat * 0.98)]
        })
        XCTAssertFalse(v.allowsArpeggio, "held chords: \(v.kind) \(v.evidence)")
    }

    func testBrokenChordsAreAllowed() {
        // Eighths R 5 8 5 on every beat pair, one note at a time.
        let v = verdict(Self.song { bar, b in
            let r = Self.roots[bar % 4]
            return [(0, r, Self.beat * 0.45), (0.5, b % 2 == 0 ? r + 7 : r + 12, Self.beat * 0.45)]
        })
        XCTAssertEqual(v.kind, .brokenChord, "\(v.evidence)")
        XCTAssertTrue(v.allowsArpeggio, "\(v.evidence)")
    }

    func testBlockChordsAreNotArpeggios() {
        let v = verdict(Self.song { bar, _ in
            let r = Self.roots[bar % 4], third = r + (Self.minor[bar % 4] ? 3 : 4)
            return [0.0, 0.5].flatMap { off in [(off, r, Self.beat * 0.4), (off, third, Self.beat * 0.4), (off, r + 7, Self.beat * 0.4), (off, r + 12, Self.beat * 0.4)] }
        })
        XCTAssertFalse(v.allowsArpeggio, "block chords: \(v.kind) \(v.evidence)")
    }
}
