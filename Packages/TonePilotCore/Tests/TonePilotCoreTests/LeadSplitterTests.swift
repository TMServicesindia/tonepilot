import XCTest
@testable import TonePilotCore

/// Lead / Backing split of the Music part on a synthetic mix with known parts.
final class LeadSplitterTests: XCTestCase {
    static let sr = 22_050.0

    /// A flute-like melody (changing notes, vibrato) over a sustained chord pad.
    static func parts(seconds: Double) -> (lead: [Float], backing: [Float]) {
        let n = Int(seconds * sr)
        var lead = [Float](repeating: 0, count: n), backing = lead
        let tune = [72.0, 74, 76, 79, 77, 76, 74, 72]
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            let note = tune[Int(t / 0.5) % tune.count]
            // Vibrato ±0.4% at 5.5 Hz; the phase is accumulated so the pitch stays on the note.
            let f = 440 * pow(2, (note - 69) / 12) * (1 + 0.004 * sin(2 * .pi * 5.5 * t))
            phase += 2 * .pi * f / sr
            var v = 0.0
            for h in 1...6 { v += sin(phase * Double(h) + Double(h)) / Double(h) }
            lead[i] = Float(0.18 * v)
            var p = 0.0
            for m in [48.0, 52, 55] { let g = 440 * pow(2, (m - 69) / 12); for h in 1...4 { p += sin(2 * .pi * g * Double(h) * t) / Double(h * h) } }
            backing[i] = Float(0.07 * p)
        }
        return (lead, backing)
    }

    func sdr(_ ref: [Float], _ est: [Float]) -> Double {
        var s = 0.0, e = 0.0
        for i in ref.indices { s += Double(ref[i] * ref[i]); let d = Double(ref[i] - est[i]); e += d * d }
        return 10 * log10(s / max(e, 1e-12))
    }

    func testSplitsLeadFromBackingAndAddsUpExactly() throws {
        let (lead, backing) = Self.parts(seconds: 8)
        let mix = zip(lead, backing).map { $0 + $1 }
        let r = try XCTUnwrap(LeadSplitter.split(channels: [mix], sampleRate: Self.sr))
        // Ignore the edges (first/last window).
        let a = 4096, b = mix.count - 4096
        let leadSDR = sdr(Array(lead[a..<b]), Array(r.lead[0][a..<b]))
        let backingSDR = sdr(Array(backing[a..<b]), Array(r.backing[0][a..<b]))
        print("SPLIT lead \(leadSDR) dB, backing \(backingSDR) dB, lead share \(r.leadShare)")
        XCTAssertGreaterThan(leadSDR, 8, "the melody ends up in Lead")
        XCTAssertGreaterThan(backingSDR, 6, "the chords stay in Backing")
        let worst = (0..<mix.count).map { abs(r.lead[0][$0] + r.backing[0][$0] - mix[$0]) }.max()!
        XCTAssertLessThan(worst, 1e-4, "Lead + Backing = the Music part")
    }

    func testComplexFFTRoundTrip() {
        let fft = ComplexFFT(size: 1024)
        var re = (0..<1024).map { Float(sin(Double($0) * 0.3) + 0.2 * cos(Double($0) * 1.7)) }, im = [Float](repeating: 0, count: 1024)
        let original = re
        fft.forward(&re, &im)
        fft.inverse(&re, &im)
        XCTAssertLessThan(zip(re, original).map { abs($0 - $1) }.max()!, 1e-4)
    }
}

extension LeadSplitterTests {
    func testChordsAloneStayInBacking() throws {
        let (_, backing) = Self.parts(seconds: 6)
        let r = try XCTUnwrap(LeadSplitter.split(channels: [backing], sampleRate: Self.sr))
        XCTAssertLessThan(r.leadShare, 0.35, "no lead line: most of it stays in Backing (\(r.leadShare))")
    }
}

extension SpeedBudgetTests {
    /// Splitting a 4-minute stereo Music part into Lead and Backing.
    func testLeadSplitIsQuick() throws {
        try budgetsApply()
        let sr = 44_100.0, n = Int(240 * sr)
        let (lead, backing) = LeadSplitterTests.parts(seconds: 240 * sr / LeadSplitterTests.sr)
        let mono = (0..<n).map { lead[$0 % lead.count] + backing[$0 % backing.count] }
        var r: LeadSplitter.Result?
        let took = seconds { r = LeadSplitter.split(channels: [mono, mono], sampleRate: sr) }
        print("SPEED lead split: \(String(format: "%.1f", took)) s for 240 s of stereo audio")
        XCTAssertNotNil(r)
        XCTAssertLessThan(took, 40, "lead split took \(took) s")
    }
}
