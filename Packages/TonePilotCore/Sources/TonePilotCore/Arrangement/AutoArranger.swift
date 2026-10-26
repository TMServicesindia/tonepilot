import Foundation

/// Builds a complete, playable arrangement for every section from the analysis — designed
/// around the target playing style: left hand plays Root → Fifth → Root, right hand plays the melody.
///
/// For each section it chooses:
/// * a right-hand **lead** patch matched to the lead line's register, ornamentation and the
///   section's brightness/sustain,
/// * a left-hand **accompaniment** patch matched to the section's harmonic texture,
/// * optional **support** layers (pad/strings under the lead, subtle bell accents, bass reinforcement)
///   only when the analysis heard those roles,
/// * key split, effects and balance, with a written rationale.
///
/// Repeated sections (same repetition group and type) share one arrangement. Every
/// arrangement is stored twice: an unchanged **AI Original** and an editable **My Version**.
public enum AutoArranger {
    public struct Options: Sendable {
        /// Default boundary between the left and right hand (C4).
        public var defaultSplit: Int = 60
        /// Lowest and highest physical keys (CT-X870IN: C2–C7).
        public var keyboardLow: Int = 36
        public var keyboardHigh: Int = 96
        public init() {}
    }

    struct Candidate {
        let patchId: UUID
        let name: String
        let centroid: ClosedRange<Double>
        let sustain: ClosedRange<Double>
        let ornament: Double
        let register: ClosedRange<Double>
        let vocalAffinity: Double
        let reason: String
    }

    static let leadCandidates: [Candidate] = [
        Candidate(patchId: FactoryPatches.bansuriId, name: "Bansuri-like Flute", centroid: 700...2600, sustain: 0.4...0.9, ornament: 0.9,
                  register: 64...90, vocalAffinity: 0.8, reason: "ornamented, sustained phrases in a flute register"),
        Candidate(patchId: FactoryPatches.id(forProgram: 73), name: "Flute", centroid: 900...3000, sustain: 0.35...0.9, ornament: 0.4,
                  register: 62...96, vocalAffinity: 0.5, reason: "smooth sustained line with moderate ornamentation"),
        Candidate(patchId: FactoryPatches.expressiveViolinId, name: "Expressive Violin Lead", centroid: 1200...3600, sustain: 0.45...1, ornament: 0.8,
                  register: 55...92, vocalAffinity: 0.7, reason: "expressive, sliding, sustained line"),
        Candidate(patchId: FactoryPatches.bansuriLowId, name: "Low Bansuri-like Flute", centroid: 500...2000, sustain: 0.4...0.95, ornament: 0.85,
                  register: 52...80, vocalAffinity: 0.9, reason: "a sung melody in a low, breathy flute register"),
        Candidate(patchId: FactoryPatches.harmoniumId, name: "Harmonium-like Reed", centroid: 600...2400, sustain: 0.5...1, ornament: 0.3,
                  register: 48...84, vocalAffinity: 0.7, reason: "a sustained sung melody with a warm, reedy Indian colour"),
        Candidate(patchId: FactoryPatches.singingSynthLeadId, name: "Singing Synth Lead", centroid: 600...2600, sustain: 0.4...0.95, ornament: 0.7,
                  register: 50...88, vocalAffinity: 0.8, reason: "a sung melody with slides and vibrato, on a smooth synth"),
        Candidate(patchId: FactoryPatches.warmSynthLeadId, name: "Warm Synth Lead", centroid: 1000...3500, sustain: 0.35...0.9, ornament: 0.4,
                  register: 55...92, vocalAffinity: 0.5, reason: "a clear, warm electronic lead"),
        Candidate(patchId: FactoryPatches.id(forProgram: 75), name: "Pan Flute", centroid: 800...2800, sustain: 0.35...0.9, ornament: 0.5,
                  register: 60...90, vocalAffinity: 0.5, reason: "a soft, airy sustained line"),
        Candidate(patchId: FactoryPatches.id(forProgram: 16), name: "Drawbar Organ", centroid: 700...3000, sustain: 0.6...1, ornament: 0.05,
                  register: 48...90, vocalAffinity: 0.2, reason: "steady, held notes with no attack"),
        // The vocal imitation isn't convincing enough to be a default: ranked lower, played softly.
        Candidate(patchId: FactoryPatches.vocalLeadId, name: "Vocal-like Lead", centroid: 500...2200, sustain: 0.4...0.95, ornament: 0.75,
                  register: 48...84, vocalAffinity: 0.6, reason: "a sung melody in vocal range with pitch movement"),
        Candidate(patchId: FactoryPatches.id(forProgram: 0), name: "Grand Piano", centroid: 500...3000, sustain: 0...0.45, ornament: 0.05,
                  register: 48...96, vocalAffinity: 0.2, reason: "clear, steady notes with decaying attacks"),
        Candidate(patchId: FactoryPatches.softSynthLeadId, name: "Soft Synth Lead", centroid: 1800...5000, sustain: 0.3...0.9, ornament: 0.3,
                  register: 55...96, vocalAffinity: 0.3, reason: "a bright electronic lead"),
        Candidate(patchId: FactoryPatches.id(forProgram: 8), name: "Celesta", centroid: 2500...7000, sustain: 0...0.4, ornament: 0,
                  register: 72...108, vocalAffinity: 0, reason: "high, bell-like, percussive notes"),
        Candidate(patchId: FactoryPatches.santoorId, name: "Santoor-like Dulcimer", centroid: 2200...6000, sustain: 0...0.35, ornament: 0.2,
                  register: 60...96, vocalAffinity: 0, reason: "bright rapid plucked/hammered notes"),
        Candidate(patchId: FactoryPatches.veenaId, name: "Veena-like Pluck", centroid: 900...3500, sustain: 0.1...0.5, ornament: 0.8,
                  register: 48...84, vocalAffinity: 0.2, reason: "plucked notes with bends"),
        Candidate(patchId: FactoryPatches.expressiveShehnaiId, name: "Shehnai Lead", centroid: 1000...3200, sustain: 0.5...1, ornament: 0.9,
                  register: 60...88, vocalAffinity: 0.5, reason: "a reedy, highly ornamented sustained line"),
    ]

    static func closeness(_ x: Double, _ r: ClosedRange<Double>, scale: Double) -> Double {
        if r.contains(x) { return 1 }
        let d = x < r.lowerBound ? r.lowerBound - x : x - r.upperBound
        return exp(-d / scale)
    }

    public struct LeadEvidence: Sendable {
        public var centroid: Double
        public var sustain: Double
        public var ornamentRatio: Double
        public var medianPitch: Double?
        public var fromVocals: Bool
    }

    /// Ranks lead patches for the evidence; returns (candidate, score 0...1) best first.
    static func rankLeads(_ e: LeadEvidence) -> [(Candidate, Double)] {
        leadCandidates.map { c in
            var s = 0.3 * closeness(e.centroid, c.centroid, scale: 800)
            s += 0.2 * closeness(e.sustain, c.sustain, scale: 0.2)
            s += 0.25 * (1 - abs(e.ornamentRatio * 1.6 - c.ornament).clamped(to: 0...1))
            if let p = e.medianPitch { s += 0.15 * closeness(p, c.register, scale: 6) } else { s += 0.075 }
            s += 0.1 * (e.fromVocals ? c.vocalAffinity : 0.5)
            if c.patchId == FactoryPatches.vocalLeadId { s *= 0.7 }
            return (c, s)
        }.sorted { $0.1 > $1.1 }
    }

    public struct Result: Sendable {
        public var song: Song
        /// Section ids whose arrangement was (re)generated.
        public var arranged: [UUID]
    }

    /// Generates arrangements for every section (or only `onlySection`). Existing AI Originals for
    /// the regenerated sections are replaced; My Versions the user already edited are kept unless
    /// `onlySection` asks for that section explicitly ("Regenerate This Section").
    public static func arrange(_ input: Song, timbres: [UUID: SectionTimbre] = [:], patches: [InstrumentPatch],
                               onlySection: UUID? = nil, options: Options = Options()) -> Result {
        var song = input
        let available = Dictionary(patches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let sections = song.orderedSections
        var built: [String: (ai: Arrangement, mine: Arrangement)] = [:]
        var arranged: [UUID] = []
        var newSuggestions = song.toneSuggestions

        for section in sections {
            if let only = onlySection, section.id != only { continue }
            // Keep the user's own choices on full re-runs.
            if onlySection == nil, let current = song.arrangement(for: section), current.origin == .myVersion,
               current.updatedAt.timeIntervalSince(current.createdAt) > 1 { continue }
            if onlySection == nil, let current = song.arrangement(for: section), current.origin == nil || current.origin == .user,
               current.name != "Main tone" { continue }

            let groupKey = onlySection == nil ? "\(section.repetitionGroup ?? section.id.uuidString)-\(section.type.rawValue)" : section.id.uuidString
            let pair: (ai: Arrangement, mine: Arrangement)
            if let existing = built[groupKey] {
                pair = existing
            } else {
                let timbre = timbres[section.id] ?? section.timbre ?? SectionTimbre(centroid: 1500, onsetRate: 2, lowEnergyShare: 0.2, highEnergyShare: 0.05, sustain: 0.5, loudness: 0.1)
                let (ai, suggestions) = buildArrangement(for: section, song: song, timbre: timbre, available: available, options: options)
                newSuggestions.removeAll { $0.sectionId == section.id && $0.method == .featureHeuristic }
                newSuggestions += suggestions
                pair = (ai, ai.makeMyVersion())
                built[groupKey] = pair
                // Replace previous AI Original / My Version of this section.
                if let old = song.arrangement(for: section), old.origin == .myVersion || old.origin == .aiOriginal {
                    let oldIds: Set<UUID> = [old.id, old.derivedFrom].compactMap { $0 }.reduce(into: Set()) { $0.insert($1) }
                    let stillUsed = song.sections.contains { $0.id != section.id && $0.arrangementId.map(oldIds.contains) == true }
                    if !stillUsed { song.arrangements.removeAll { oldIds.contains($0.id) } }
                }
                song.arrangements += [pair.ai, pair.mine]
            }
            if let i = song.sections.firstIndex(where: { $0.id == section.id }) {
                song.sections[i].arrangementId = pair.mine.id
            }
            arranged.append(section.id)
        }
        song.toneSuggestions = newSuggestions
        song.updatedAt = Date()
        return Result(song: song, arranged: arranged)
    }

    static func buildArrangement(for section: SongSection, song: Song, timbre t: SectionTimbre, available: [UUID: InstrumentPatch],
                                 options: Options) -> (Arrangement, [ToneSuggestion]) {
        let activity = Dictionary((section.activity ?? []).map { ($0.role, $0) }, uniquingKeysWith: { a, b in a.level >= b.level ? a : b })
        func level(_ r: MusicalRole) -> Double { activity[r]?.level ?? 0 }
        let notes = song.melody?.notes(in: section.startTime, section.endTime) ?? []
        let hasLead = max(level(.lead), level(.vocalMelody)) > 0.2 && notes.count >= 3
        let ornamentRatio = notes.isEmpty ? 0 : Double(notes.filter(\.isOrnamented).count) / Double(notes.count)
        let median = notes.isEmpty ? nil : Double(notes.map(\.midi).sorted()[notes.count / 2])
        let fromVocals = song.melody?.source == .vocalStem || level(.vocalMelody) > 0.4

        // Split point: just under the melody's lowest note, kept between G3 and F4.
        var split = options.defaultSplit
        var leadOctave = 0
        if let lo = notes.map(\.midi).min() {
            var playedLow = lo
            // A low (e.g. male) melody is played an octave up and sounded back down, so the
            // left hand keeps its Root–Fifth–Root space.
            while playedLow < 57 { playedLow += 12; leadOctave -= 1 }
            split = max(55, min(65, playedLow - 1))
            if let hi = notes.map(\.midi).max(), hi - 12 * leadOctave > options.keyboardHigh { leadOctave += 1 }
        }
        let leftRange = KeyRange(low: UInt8(options.keyboardLow - 12), high: UInt8(split - 1))
        let rightRange = KeyRange(low: UInt8(split), high: 127)

        var layers: [Layer] = []
        var why: [String] = []
        var suggestions: [ToneSuggestion] = []

        // 1. Right hand: lead (sung melody or instrumental motif).
        let evidence = LeadEvidence(centroid: t.centroid, sustain: t.sustain, ornamentRatio: ornamentRatio, medianPitch: median, fromVocals: fromVocals)
        let ranked = rankLeads(evidence).filter { available[$0.0.patchId] != nil }
        if let (best, score) = ranked.first {
            let isInstrumental = !hasLead
            let quiet = best.patchId == FactoryPatches.vocalLeadId
            let lead = Layer(patchId: best.patchId, volume: quiet ? 0.45 : (section.type == .chorus ? 0.85 : 0.75), octave: leadOctave,
                             keyRange: rightRange, role: isInstrumental ? .motif : (fromVocals ? .vocalMelody : .lead))
            layers.append(lead)
            why.append("Right hand: \(best.name) — \(best.reason)\(isInstrumental ? " (instrumental motif)" : "").")
            for (c, s) in ranked.prefix(3) {
                suggestions.append(ToneSuggestion(sectionId: section.id, family: available[c.patchId]?.family ?? .other, patchId: c.patchId,
                                                  reason: "Lead option: \(c.reason).", confidence: 0.6 * s, method: .featureHeuristic))
            }
            _ = score
        }

        // 2. Left hand: accompaniment for Root–Fifth–Root.
        let padLevel = level(.pad), keysLevel = level(.keys)
        let leftPatch: UUID
        let leftWhy: String
        if padLevel > keysLevel + 0.1 {
            leftPatch = t.centroid < 1200 && available[FactoryPatches.warmAnalogPadId] != nil && section.type != .chorus
                ? FactoryPatches.warmAnalogPadId : FactoryPatches.id(forProgram: 49)
            leftWhy = "sustained harmony dominates, so broken chords ring as strings/pad"
        } else {
            leftPatch = section.type == .chorus ? FactoryPatches.id(forProgram: 0) : (available[FactoryPatches.softPianoId] != nil ? FactoryPatches.softPianoId : FactoryPatches.id(forProgram: 0))
            leftWhy = "articulated accompaniment — piano keeps Root–Fifth–Root patterns clear"
        }
        layers.append(Layer(patchId: leftPatch, volume: 0.6, pan: -0.1, keyRange: leftRange, role: padLevel > keysLevel + 0.1 ? .pad : .harmony))
        why.append("Left hand: \(leftWhy).")

        // 3. Support layers only when heard.
        if padLevel > 0.45 {
            layers.append(Layer(patchId: FactoryPatches.id(forProgram: section.type == .chorus ? 48 : 49), volume: 0.35, pan: 0.15,
                                keyRange: rightRange, role: .pad))
            why.append("Strings under the right hand: a sustained bed is present (\(Int(padLevel * 100))%).")
        }
        if level(.accent) > 0.45 || (section.type == .interlude && level(.accent) > 0.3) {
            layers.append(Layer(patchId: FactoryPatches.id(forProgram: 8), volume: 0.28, pan: 0.25, octave: 1,
                                keyRange: KeyRange(low: UInt8(max(split, 64)), high: 127), role: .accent))
            why.append("Subtle celesta an octave up: bright bell-like accents detected.")
        }
        if level(.bass) > 0.55 {
            layers.append(Layer(patchId: FactoryPatches.id(forProgram: 33), volume: 0.45, octave: -1, keyRange: leftRange, role: .bass))
            why.append("Bass doubles your left-hand root an octave down: strong low end in this section.")
        }

        // Effects by section character.
        var master = MasterEffects()
        switch section.type {
        case .intro, .instrumentalIntro, .outro: master.reverbLevel = 1.0; master.reverbSize = 0.75
        case .interlude, .instrumentalBreak: master.reverbLevel = 0.95; master.delayLevel = 0.7
        case .chorus: master.reverbLevel = 0.8; master.eq = EQSettings(highDB: 1.5)
        default: master.reverbLevel = 0.75
        }
        let name = "\(section.label) (AI)"
        let arrangement = Arrangement(name: name, layers: Array(layers.prefix(ToneEngine.liveSlotCount)),
                                      masterGain: section.type == .chorus ? 0.85 : 0.8, master: master, origin: .aiOriginal,
                                      rationale: why.joined(separator: " ") + " Closest available sounds — approximations, not the original studio instruments.")
        return (arrangement, suggestions)
    }

    /// Where the guide should show the melody (semitones) so it falls on the right-hand keys,
    /// matching the lead layer's octave compensation.
    public static func guideOffset(for arrangement: Arrangement?) -> Int {
        guard let lead = arrangement?.layers.first(where: { [.lead, .vocalMelody, .motif].contains($0.role) }) else { return 0 }
        return -lead.octave * 12
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
