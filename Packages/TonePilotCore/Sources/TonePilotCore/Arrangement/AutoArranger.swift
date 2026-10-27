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
        /// Instrument families this tone stands in for (`InstrumentEvidence`).
        var families: [String] = []
        /// Section intensity range it suits (0 calm ... 1 mass).
        var energy: ClosedRange<Double> = 0...0.7
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

    /// Families and intensity for the original candidates, plus the powerful ones.
    static let candidates: [Candidate] = {
        var list = leadCandidates.map { c -> Candidate in
            var c = c
            switch c.patchId {
            case FactoryPatches.bansuriId, FactoryPatches.bansuriLowId, FactoryPatches.id(forProgram: 75):
                c.families = ["flute"]; c.energy = 0...0.55
            case FactoryPatches.id(forProgram: 73): c.families = ["flute"]; c.energy = 0...0.65
            case FactoryPatches.expressiveViolinId: c.families = ["strings"]; c.energy = 0.1...0.8
            case FactoryPatches.harmoniumId: c.families = ["organ", "reed"]; c.energy = 0...0.6
            case FactoryPatches.singingSynthLeadId: c.families = ["synth"]; c.energy = 0.2...0.6
            case FactoryPatches.warmSynthLeadId, FactoryPatches.softSynthLeadId: c.families = ["synth"]; c.energy = 0.3...0.75
            case FactoryPatches.id(forProgram: 16): c.families = ["organ"]; c.energy = 0.2...0.7
            case FactoryPatches.id(forProgram: 0): c.families = ["piano"]; c.energy = 0...0.7
            case FactoryPatches.id(forProgram: 8): c.families = ["bells"]; c.energy = 0...0.5
            case FactoryPatches.santoorId, FactoryPatches.veenaId: c.families = ["plucked"]; c.energy = 0...0.65
            case FactoryPatches.expressiveShehnaiId: c.families = ["reed"]; c.energy = 0.2...0.85
            case FactoryPatches.vocalLeadId: c.families = ["voice"]; c.energy = 0...0.5
            default: break
            }
            return c
        }
        list += [
            Candidate(patchId: FactoryPatches.powerBrassId, name: "Power Brass", centroid: 900...4000, sustain: 0.3...1, ornament: 0.1,
                      register: 55...90, vocalAffinity: 0.3, reason: "a loud, punchy line — a mass song's brass lead", families: ["brass"], energy: 0.55...1),
            Candidate(patchId: FactoryPatches.drivenSynthBrassId, name: "Driven Synth Brass", centroid: 1200...5000, sustain: 0.3...1, ornament: 0.1,
                      register: 52...90, vocalAffinity: 0.3, reason: "a powerful electronic brass line", families: ["brass", "synth"], energy: 0.6...1),
            Candidate(patchId: FactoryPatches.powerSawLeadId, name: "Power Saw Lead", centroid: 1500...6000, sustain: 0.3...1, ornament: 0.2,
                      register: 55...96, vocalAffinity: 0.3, reason: "an aggressive, bright synth lead for high-energy sections", families: ["synth"], energy: 0.6...1),
            Candidate(patchId: FactoryPatches.id(forProgram: 30), name: "Distortion Guitar", centroid: 1200...5000, sustain: 0.4...1, ornament: 0.3,
                      register: 45...84, vocalAffinity: 0.2, reason: "a distorted electric-guitar line", families: ["electricGuitar"], energy: 0.6...1),
            Candidate(patchId: FactoryPatches.id(forProgram: 27), name: "Clean Electric Guitar", centroid: 900...3500, sustain: 0.1...0.6, ornament: 0.3,
                      register: 45...84, vocalAffinity: 0.2, reason: "a clean electric-guitar line", families: ["electricGuitar", "acousticGuitar"], energy: 0.2...0.75),
            Candidate(patchId: FactoryPatches.id(forProgram: 56), name: "Trumpet", centroid: 900...3600, sustain: 0.3...1, ornament: 0.3,
                      register: 55...86, vocalAffinity: 0.4, reason: "a bright brass melody", families: ["brass"], energy: 0.35...0.9),
            Candidate(patchId: FactoryPatches.id(forProgram: 65), name: "Alto Sax", centroid: 700...3000, sustain: 0.35...1, ornament: 0.5,
                      register: 52...84, vocalAffinity: 0.5, reason: "a smooth, reedy saxophone melody", families: ["reed"], energy: 0.25...0.8),
            Candidate(patchId: FactoryPatches.id(forProgram: 52), name: "Choir", centroid: 400...2500, sustain: 0.6...1, ornament: 0.2,
                      register: 48...84, vocalAffinity: 0.6, reason: "chant-like held voices", families: ["choir"], energy: 0.3...1),
            // Film Tone Library.
            Candidate(patchId: FactoryPatches.anthemSupersawId, name: "Anthem Supersaw", centroid: 1800...7000, sustain: 0.3...1, ornament: 0.15,
                      register: 52...96, vocalAffinity: 0.3, reason: "a huge, wide synth hook for a mass anthem", families: ["synth"], energy: 0.7...1),
            Candidate(patchId: FactoryPatches.supersawLeadId, name: "Supersaw Lead", centroid: 1500...6000, sustain: 0.3...1, ornament: 0.25,
                      register: 55...96, vocalAffinity: 0.35, reason: "a bright, wide dance lead", families: ["synth"], energy: 0.5...0.9),
            Candidate(patchId: FactoryPatches.classicSynthBrassId, name: "Classic Synth Brass", centroid: 1000...4500, sustain: 0.3...1, ornament: 0.1,
                      register: 52...90, vocalAffinity: 0.3, reason: "punchy synth-brass phrases", families: ["brass", "synth"], energy: 0.45...0.9),
            Candidate(patchId: FactoryPatches.nadaswaramLeadId, name: "Nadaswaram-like Lead", centroid: 1200...4000, sustain: 0.5...1, ornament: 0.85,
                      register: 60...90, vocalAffinity: 0.5, reason: "a loud, ornamented reed line — temple and mass-song colour", families: ["reed"], energy: 0.55...1),
            Candidate(patchId: FactoryPatches.epicHornsId, name: "Epic French Horns", centroid: 500...2500, sustain: 0.5...1, ornament: 0.1,
                      register: 48...80, vocalAffinity: 0.3, reason: "a broad, cinematic horn melody", families: ["brass"], energy: 0.5...1),
            Candidate(patchId: FactoryPatches.distortedGuitarLeadId, name: "Distorted Guitar Lead", centroid: 1200...5000, sustain: 0.4...1, ornament: 0.4,
                      register: 48...88, vocalAffinity: 0.25, reason: "a singing, distorted guitar solo line", families: ["electricGuitar"], energy: 0.6...1),
            Candidate(patchId: FactoryPatches.melodySaxId, name: "Melody Sax", centroid: 700...3000, sustain: 0.35...1, ornament: 0.6,
                      register: 52...84, vocalAffinity: 0.5, reason: "an expressive sax melody with slides", families: ["reed"], energy: 0.2...0.7),
            Candidate(patchId: FactoryPatches.heroWhistleLeadId, name: "Whistle Lead", centroid: 1500...5000, sustain: 0.4...1, ornament: 0.6,
                      register: 67...96, vocalAffinity: 0.4, reason: "a pure, whistled high melody", families: ["flute"], energy: 0.2...0.7),
        ]
        return list
    }()

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
        /// 0 calm ... 1 mass (`ToneIntensity`).
        public var intensity: Double = 0.4
        /// Instrument families heard (family → 0...1); empty when not recognised.
        public var instruments: [String: Double] = [:]
    }

    /// Ranks lead patches for the evidence; returns (candidate, score 0...1) best first.
    /// Order of importance: the instruments actually heard, the section's intensity, then the
    /// timbre (brightness, sustain, ornaments, register).
    static func rankLeads(_ e: LeadEvidence) -> [(Candidate, Double)] {
        // Instrument evidence, relative to the strongest family heard (the singer's voice doesn't count:
        // a sung melody gets the instrument that suits the song, not a voice imitation).
        let heard = e.instruments.filter { $0.key != "voice" && $0.value > 0.05 }
        let top = heard.values.max() ?? 0
        return candidates.map { c in
            var timbre = 0.3 * closeness(e.centroid, c.centroid, scale: 800)
            timbre += 0.2 * closeness(e.sustain, c.sustain, scale: 0.2)
            timbre += 0.25 * (1 - abs(e.ornamentRatio * 1.6 - c.ornament).clamped(to: 0...1))
            if let p = e.medianPitch { timbre += 0.15 * closeness(p, c.register, scale: 6) } else { timbre += 0.075 }
            timbre += 0.1 * (e.fromVocals ? min(c.vocalAffinity, 0.6) : 0.5)
            let energy = closeness(e.intensity, c.energy, scale: 0.12)
            var s: Double
            if top > 0 {
                let family = (c.families.compactMap { heard[$0] }.max() ?? 0) / top
                s = 0.45 * family + 0.3 * energy + 0.25 * timbre
            } else {
                s = 0.45 * energy + 0.55 * timbre
            }
            // Voice imitations only when nothing else fits.
            if c.patchId == FactoryPatches.vocalLeadId { s *= 0.6 }
            if c.patchId == FactoryPatches.singingSynthLeadId, (heard["synth"] ?? 0) < 0.5 * max(top, 0.01) { s *= 0.8 }
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
        func timbre(_ section: SongSection) -> SectionTimbre {
            timbres[section.id] ?? section.timbre ?? SectionTimbre(centroid: 1500, onsetRate: 2, lowEnergyShare: 0.2, highEnergyShare: 0.05, sustain: 0.5, loudness: 0.1)
        }
        // The song's lead: the tone that wins the most song time. Sections only differ from it when
        // their own best is clearly better (avoids Bansuri → Synth → Bansuri across similar verses).
        var votes: [UUID: Double] = [:]
        for section in sections {
            if let best = rankLeads(leadEvidence(for: section, song: song, timbre: timbre(section))).first(where: { available[$0.0.patchId] != nil }) {
                votes[best.0.patchId, default: 0] += best.1 * max(1, section.duration)
            }
        }
        let preferredLead = votes.max { $0.value < $1.value }?.key

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
                let (ai, suggestions) = buildArrangement(for: section, song: song, timbre: timbre(section), available: available,
                                                         options: options, preferredLead: preferredLead)
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
        if onlySection == nil { refreshMainTone(&song) }
        song.updatedAt = Date()
        return Result(song: song, arranged: arranged)
    }

    static let aiMainTonePrefix = "AI main tone"

    /// The song's main tone (one tone for the whole song), made from the song: the arrangement of
    /// its most representative section — the lead that covers the most song time (the chorus and
    /// loud parts count more), taken from its most intense section.
    public static func aiMainTone(for song: Song) -> Arrangement? {
        let withTone = song.sections.compactMap { s -> (SongSection, Arrangement)? in song.arrangement(for: s).map { (s, $0) } }
        guard !withTone.isEmpty else { return nil }
        func lead(_ a: Arrangement) -> UUID? { a.layers.first { [.lead, .vocalMelody, .motif].contains($0.role) }?.patchId ?? a.layers.first?.patchId }
        // A section's weight: its length, more for the chorus / climax / loud parts (the song's hook).
        func weight(_ s: SongSection) -> Double {
            (s.type == .chorus ? 2 : 1) * (s.isClimax == true ? 1.3 : 1) * (s.timbre.map { 0.5 + $0.loudness * 10 } ?? 1) * max(1, s.duration)
        }
        var time: [UUID: Double] = [:]
        for (s, a) in withTone { if let l = lead(a) { time[l, default: 0] += weight(s) } }
        guard let mainLead = time.max(by: { $0.value < $1.value })?.key else { return nil }
        let pick = withTone.filter { lead($0.1) == mainLead }.max { weight($0.0) < weight($1.0) }
        guard let (section, source) = pick else { return nil }
        var tone = Arrangement(name: "Main tone", layers: source.layers, masterGain: source.masterGain, master: source.master)
        tone.rationale = "\(aiMainTonePrefix) from \(section.label): " + (source.rationale ?? "")
        return tone
    }

    /// Adds the AI main tone, or refreshes it when the current one is the old generic stack or an
    /// earlier AI main tone. A main tone you edited yourself is kept.
    public static func refreshMainTone(_ song: inout Song) {
        guard let fresh = aiMainTone(for: song) else { return }
        let used = Set(song.sections.compactMap(\.arrangementId))
        let generic = Set(Arrangement.starterFilmStack().layers.map(\.patchId))
        if let i = song.arrangements.firstIndex(where: { !used.contains($0.id) && $0.origin != .aiOriginal && $0.name == "Main tone" }) {
            let current = song.arrangements[i]
            let isGeneric = Set(current.layers.map(\.patchId)) == generic && current.layers.count == 3
            // An AI main tone you saved in the editor is yours from then on.
            let isAI = current.rationale?.hasPrefix(aiMainTonePrefix) == true && current.updatedAt.timeIntervalSince(current.createdAt) <= 1
            guard isGeneric || isAI else { return }
            var replaced = fresh
            replaced.id = current.id
            song.arrangements[i] = replaced
        } else {
            song.arrangements.append(fresh)
        }
    }

    /// Section intensity (0...1) against the rest of the song.
    static func intensity(of section: SongSection, in song: Song, timbre t: SectionTimbre) -> Double {
        let all = song.sections.compactMap(\.timbre)
        let percussion = section.activity?.first { $0.role == .percussion }?.level ?? 0
        return ToneIntensity.value(t, song: all.isEmpty ? [t] : all, percussion: percussion)
    }

    static func leadEvidence(for section: SongSection, song: Song, timbre t: SectionTimbre) -> LeadEvidence {
        let activity = Dictionary((section.activity ?? []).map { ($0.role, $0) }, uniquingKeysWith: { a, b in a.level >= b.level ? a : b })
        let notes = song.melody?.notes(in: section.startTime, section.endTime) ?? []
        let ornamentRatio = notes.isEmpty ? 0 : Double(notes.filter(\.isOrnamented).count) / Double(notes.count)
        let median = notes.isEmpty ? nil : Double(notes.map(\.midi).sorted()[notes.count / 2])
        let fromVocals = song.melody?.source == .vocalStem || (activity[.vocalMelody]?.level ?? 0) > 0.4
        var e = LeadEvidence(centroid: t.centroid, sustain: t.sustain, ornamentRatio: ornamentRatio, medianPitch: median, fromVocals: fromVocals)
        e.intensity = intensity(of: section, in: song, timbre: t)
        e.instruments = section.instruments ?? [:]
        return e
    }

    static func buildArrangement(for section: SongSection, song: Song, timbre t: SectionTimbre, available: [UUID: InstrumentPatch],
                                 options: Options, preferredLead: UUID? = nil) -> (Arrangement, [ToneSuggestion]) {
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
        var evidence = LeadEvidence(centroid: t.centroid, sustain: t.sustain, ornamentRatio: ornamentRatio, medianPitch: median, fromVocals: fromVocals)
        let power = intensity(of: section, in: song, timbre: t)
        evidence.intensity = power
        evidence.instruments = section.instruments ?? [:]
        let level3 = ToneIntensity.level(power)
        let ranked = rankLeads(evidence).filter { available[$0.0.patchId] != nil }
        // One lead for the whole song unless this section clearly calls for another.
        let chosen = ranked.first.map { best in
            ranked.first { $0.0.patchId == preferredLead && $0.1 >= best.1 - 0.1 } ?? best
        }
        if let (best, _) = chosen {
            let isInstrumental = !hasLead
            let quiet = best.patchId == FactoryPatches.vocalLeadId
            let volume = quiet ? 0.45 : (level3 == .powerful ? 0.85 : section.type == .chorus ? 0.8 : 0.72)
            let lead = Layer(patchId: best.patchId, volume: volume, octave: leadOctave,
                             keyRange: rightRange, role: isInstrumental ? .motif : (fromVocals ? .vocalMelody : .lead))
            layers.append(lead)
            let heard = evidence.instruments.filter { $0.key != "voice" }.max { $0.value < $1.value }
            why.append("Right hand: \(best.name) — \(best.reason)\(isInstrumental ? " (instrumental motif)" : "")"
                       + "\(heard.map { "; heard: \($0.key) \(Int($0.value * 100))%" } ?? ""); intensity \(level3.rawValue).")
            for (c, s) in ranked.prefix(3) {
                suggestions.append(ToneSuggestion(sectionId: section.id, family: available[c.patchId]?.family ?? .other, patchId: c.patchId,
                                                  reason: "Lead option: \(c.reason).", confidence: min(1, s), method: .featureHeuristic))
            }
        }

        // 2. Left hand: accompaniment for Root–Fifth–Root.
        let padLevel = level(.pad), keysLevel = level(.keys)
        var leftPatch: UUID
        var leftWhy: String
        if padLevel > keysLevel + 0.1 {
            leftPatch = t.centroid < 1200 && available[FactoryPatches.warmAnalogPadId] != nil && section.type != .chorus
                ? FactoryPatches.warmAnalogPadId : FactoryPatches.id(forProgram: 49)
            leftWhy = "sustained harmony dominates, so broken chords ring as strings/pad"
        } else {
            leftPatch = section.type == .chorus ? FactoryPatches.id(forProgram: 0) : (available[FactoryPatches.softPianoId] != nil ? FactoryPatches.softPianoId : FactoryPatches.id(forProgram: 0))
            leftWhy = "articulated accompaniment — piano keeps Root–Fifth–Root patterns clear"
        }
        if level3 == .powerful {
            let brass = (evidence.instruments["brass"] ?? 0) >= 0.25
            let synth = (evidence.instruments["synth"] ?? 0) >= 0.4 && !brass
            if synth {
                leftPatch = FactoryPatches.supersawChordsId
                leftWhy = "powerful electronic section — the left hand plays wide supersaw chords"
            } else {
                leftPatch = brass || power >= 0.78 ? FactoryPatches.brassStabsId : FactoryPatches.powerStringsId
                leftWhy = brass ? "powerful section with brass — the left hand plays brass stabs" : "powerful section — the left hand plays punchy strings"
            }
            if available[leftPatch] == nil { leftPatch = FactoryPatches.id(forProgram: 61) }
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
        if level(.bass) > 0.55 || (level3 == .powerful && level(.bass) > 0.4) {
            let sub = level3 == .powerful && available[FactoryPatches.subBassId] != nil
            layers.append(Layer(patchId: sub ? FactoryPatches.subBassId : FactoryPatches.id(forProgram: 33), volume: sub ? 0.5 : 0.45,
                                octave: -1, keyRange: leftRange, role: .bass))
            why.append(sub ? "Sub synth bass under your left-hand root: heavy low end in a powerful section."
                           : "Bass doubles your left-hand root an octave down: strong low end in this section.")
        }
        // Clean gain staging: layers that sound together never add up past the engine's headroom
        // (the limiter stays a safety net, not part of the sound).
        for probe: UInt8 in [48, 72] {
            let together = layers.filter { $0.keyRange.contains(probe) }.reduce(0) { $0 + $1.volume }
            if together > 1.1 { let k = 1.1 / together; for i in layers.indices where layers[i].keyRange.contains(probe) { layers[i].volume *= k } }
        }

        // Effects by section character.
        var master = MasterEffects()
        switch level3 == .powerful ? .chorus : section.type {
        case .intro, .instrumentalIntro, .outro: master.reverbLevel = 1.0; master.reverbSize = 0.75
        case .interlude, .instrumentalBreak: master.reverbLevel = 0.95; master.delayLevel = 0.7
        case .chorus where level3 == .powerful: master.reverbLevel = 0.55; master.eq = EQSettings(lowDB: 1, midDB: 1, midFrequency: 2000, highDB: 2)
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
