import XCTest
@testable import TonePilotCore

/// T3: the part's playing character is measured on its own harmonics, and the chosen tone's
/// envelope / filter / vibrato are fitted to it by render-and-measure. Synth tones with known
/// settings, so the right answer is known. Accuracy on other sound banks: the DEV tone bench.
final class ToneFitterTests: XCTestCase {
    static let sr = 22_050.0

    /// A harmonically rich synth tone with no vibrato, filter or detune of its own, so every difference
    /// in a test comes from the settings the test applies.
    static func synthPatch() throws -> InstrumentPatch {
        guard var p = FactoryPatches.all.first(where: { $0.synth?.waveform == .saw && $0.family != .bass && $0.family != .pad })
        else { throw XCTSkip("needs a saw synth tone in the factory library") }
        p.synth!.detuneCents = 0; p.synth!.noise = 0; p.synth!.unison = 1
        p.filter = FilterSettings(); p.expression = ExpressionSettings(vibratoDepth: 0)
        p.envelope = Envelope(attack: 0.005, decay: 0.3, sustain: 0.9, release: 0.15)
        return p
    }

    static func notes(_ count: Int = 12, base: Int = 64) -> [MelodyNote] {
        (0..<count).map { i in MelodyNote(start: 0.3 + Double(i) * 0.75, duration: [0.45, 0.6, 0.35, 0.65][i % 4],
                                          midi: base + [0, 2, 4, 7, 5, 3][i % 6], confidence: 1) }
    }

    static func render(_ p: InstrumentPatch, _ notes: [MelodyNote], _ s: ToneFitter.Settings = .init(), seconds: Double = 10) -> [Float] {
        ToneMatcher.render(p, instrument: LoadedInstrument(name: p.name, synth: p.synth!), notes: notes, seconds: seconds, sampleRate: sr, fit: s).samples
    }

    func testMeasurementSeesAttackBrightnessAndVibrato() throws {
        let p = try Self.synthPatch(), ns = Self.notes()
        var slow = p.envelope; slow.attack = 0.15
        let base = try XCTUnwrap(ToneFitter.measure(Self.render(p, ns), sampleRate: Self.sr, notes: ns))
        let soft = try XCTUnwrap(ToneFitter.measure(Self.render(p, ns, .init(envelope: slow)), sampleRate: Self.sr, notes: ns))
        XCTAssertGreaterThan(soft.attack, base.attack * 2, "slow attack measured slower")

        let dark = try XCTUnwrap(ToneFitter.measure(Self.render(p, ns, .init(filter: FilterSettings(enabled: true, cutoff: 900))), sampleRate: Self.sr, notes: ns))
        XCTAssertLessThan(dark.brightness, base.brightness * 0.85, "low-pass measured darker")

        var vib = p.expression ?? .poly; vib.vibratoDepth = 30; vib.vibratoRate = 6; vib.vibratoDelay = 0
        let long = (0..<6).map { MelodyNote(start: 0.3 + Double($0) * 1.6, duration: 1.4, midi: 64 + $0, confidence: 1) }
        let wobble = try XCTUnwrap(ToneFitter.measure(Self.render(p, long, .init(expression: vib)), sampleRate: Self.sr, notes: long))
        let steady = try XCTUnwrap(ToneFitter.measure(Self.render(p, long), sampleRate: Self.sr, notes: long))
        XCTAssertEqual(wobble.vibratoRate, 6, accuracy: 1.2, "vibrato rate")
        XCTAssertGreaterThan(wobble.vibratoDepth, 12, "vibrato depth seen")
        XCTAssertLessThan(steady.vibratoDepth, 6, "no vibrato on a steady tone")
    }

    func testFitRecoversHowThePartPlaysThroughLeakage() throws {
        let p = try Self.synthPatch()
        let ns = (0..<10).map { i in MelodyNote(start: 0.3 + Double(i) * 1.1, duration: [0.9, 0.6, 0.8][i % 3], midi: 62 + [0, 3, 5, 7, 10][i % 5], confidence: 1) }
        var env = p.envelope; env.attack = 0.12; env.release = 0.5
        var ex = p.expression ?? .poly; ex.vibratoDepth = 25; ex.vibratoRate = 5.5; ex.vibratoDelay = 0.15
        let truth = ToneFitter.Settings(envelope: env, filter: FilterSettings(enabled: true, cutoff: 1800), expression: ex)
        // Target: the tone played the song's way, plus another part leaking in.
        let other = FactoryPatches.all.first { $0.synth != nil && $0.id != p.id && $0.family != .percussion }!
        let chords = stride(from: 0.0, to: 11, by: 2).flatMap { s in [48, 52, 55].map { MelodyNote(start: s, duration: 1.9, midi: $0, confidence: 1) } }
        let leak = Self.render(other, chords, seconds: 12)
        let target = zip(Self.render(p, ns, truth, seconds: 12), leak).map { $0 + 0.2 * $1 }

        let fit = try XCTUnwrap(ToneFitter.fit(patch: p, instrument: LoadedInstrument(name: p.name, synth: p.synth!),
                                               target: AudioBuffer(samples: target, sampleRate: Self.sr), notes: ns))
        XCTAssertLessThan(fit.distanceAfter, fit.distanceBefore * 0.6, "fitted tone measurably closer (\(fit.distanceBefore) → \(fit.distanceAfter))")
        let a = try XCTUnwrap(fit.settings.envelope?.attack)
        XCTAssertEqual(log(a / 0.12), 0, accuracy: log(2.5), "attack recovered (\(a) s vs 0.12 s)")
        let v = try XCTUnwrap(fit.settings.expression)
        XCTAssertEqual(v.vibratoRate, 5.5, accuracy: 1.2)
        XCTAssertEqual(v.vibratoDepth, 25, accuracy: 14)
        XCTAssertNotNil(fit.settings.filter, "brightness matched with a filter")
        XCTAssertFalse(fit.summary.isEmpty)
        print("FIT patch \(p.name) synth \(p.synth!) expr \(String(describing: p.expression)) filter \(p.filter)\n target \(fit.target)\n before \(fit.before)\n after \(fit.after)")
        print("FIT \(fit.summary) distance \(String(format: "%.2f", fit.distanceBefore)) → \(String(format: "%.2f", fit.distanceAfter))")
    }

    func testSameSoundNeedsNoChangeAndAFailedCheckDropsTheFit() throws {
        let p = try Self.synthPatch(), ns = Self.notes()
        let inst = LoadedInstrument(name: p.name, synth: p.synth!)
        let same = try XCTUnwrap(ToneFitter.fit(patch: p, instrument: inst, target: AudioBuffer(samples: Self.render(p, ns), sampleRate: Self.sr), notes: ns))
        XCTAssertTrue(same.settings.isEmpty, "identical sound: tone left as it is (\(same.summary))")

        var env = p.envelope; env.attack = 0.2
        let slow = AudioBuffer(samples: Self.render(p, ns, .init(envelope: env)), sampleRate: Self.sr)
        let rejected = try XCTUnwrap(ToneFitter.fit(patch: p, instrument: inst, target: slow, notes: ns, verify: { _ in false }))
        XCTAssertTrue(rejected.settings.isEmpty, "independent check said no: nothing applied")
        let accepted = try XCTUnwrap(ToneFitter.fit(patch: p, instrument: inst, target: slow, notes: ns, verify: { _ in true }))
        XCTAssertNotNil(accepted.settings.envelope); XCTAssertTrue(accepted.verified)
    }

    func testSettingsApplyToALayerAndOldMatchesDecode() {
        var layer = Layer(patchId: UUID())
        ToneFitter.Settings(envelope: Envelope(attack: 0.1), expression: .expressiveLead).apply(to: &layer)
        XCTAssertEqual(layer.envelopeOverride?.attack, 0.1); XCTAssertNil(layer.filterOverride); XCTAssertEqual(layer.expressionOverride, .expressiveLead)
    }
}
