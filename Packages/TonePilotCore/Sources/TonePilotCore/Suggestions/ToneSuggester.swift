import Foundation

/// Rule-based tone suggestions from section timbre descriptors.
///
/// This is deliberately simple and transparent: it says *why* it suggested a
/// family, caps confidence at 0.5 and tags results `.featureHeuristic`, so the UI
/// can show "Suggested from sound character — not instrument recognition".
/// Milestone 5 replaces the scoring with an instrument-recognition model on
/// separated stems while keeping this interface.
public enum ToneSuggester {
    struct Rule {
        let family: InstrumentFamily
        let program: UInt8
        let score: (SectionTimbre) -> Double
        let reason: (SectionTimbre) -> String
    }

    static func ramp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { max(0, min(1, (x - lo) / (hi - lo))) }

    static let rules: [Rule] = [
        Rule(family: .strings, program: 49,
             score: { 0.7 * ramp($0.sustain, 0.4, 0.85) + 0.3 * (1 - ramp($0.onsetRate, 1, 4)) },
             reason: { "Sustained, smooth energy (sustain \(pct($0.sustain))) with few sharp attacks — typical of string sections." }),
        Rule(family: .pad, program: 89,
             score: { 0.8 * ramp($0.sustain, 0.5, 0.9) + 0.2 * (1 - ramp($0.centroid, 1200, 3500)) },
             reason: { "Very steady, warm background (centroid \(Int($0.centroid)) Hz) — a soft pad can recreate this bed." }),
        Rule(family: .piano, program: 0,
             score: { 0.5 * ramp($0.onsetRate, 0.8, 3) + 0.5 * (1 - ramp($0.sustain, 0.3, 0.8)) },
             reason: { "Clear note attacks (\(String(format: "%.1f", $0.onsetRate))/s) that decay between notes — piano-like articulation." }),
        Rule(family: .bell, program: 8,
             score: { 0.6 * ramp($0.highEnergyShare, 0.08, 0.3) + 0.4 * ramp($0.centroid, 2000, 4500) },
             reason: { "Strong high-frequency content (\(pct($0.highEnergyShare)) above 2.5 kHz) — celesta/bell layers add this sparkle." }),
        Rule(family: .flute, program: 73,
             score: { 0.5 * ramp($0.sustain, 0.3, 0.7) + 0.5 * (1 - abs(ramp($0.centroid, 1000, 3000) - 0.6) * 2) * (1 - ramp($0.lowEnergyShare, 0.3, 0.6)) },
             reason: { _ in "Smooth sustained mid-high tone with light low end — a soft flute layer may fit melodic lines." }),
        Rule(family: .pluck, program: 46,
             score: { 0.6 * ramp($0.onsetRate, 2.5, 6) * (1 - ramp($0.sustain, 0.3, 0.7)) + 0.4 * ramp($0.centroid, 1500, 3500) },
             reason: { "Many short, decaying notes (\(String(format: "%.1f", $0.onsetRate))/s) — harp/pluck patches suit arpeggios." }),
        Rule(family: .bass, program: 33,
             score: { ramp($0.lowEnergyShare, 0.35, 0.7) },
             reason: { "\(pct($0.lowEnergyShare)) of the energy is below 250 Hz — add a bass layer on the left-hand split." }),
    ]

    static func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

    public static func suggest(for timbre: SectionTimbre, sectionId: UUID?, count: Int = 3) -> [ToneSuggestion] {
        rules
            .map { ($0, $0.score(timbre)) }
            .sorted { $0.1 > $1.1 }
            .prefix(count)
            .map { rule, score in
                ToneSuggestion(sectionId: sectionId, family: rule.family,
                               patchId: FactoryPatches.id(forProgram: rule.program),
                               reason: rule.reason(timbre), confidence: 0.5 * score, method: .featureHeuristic)
            }
    }
}
