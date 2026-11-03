import Foundation

/// Sound-engine phase 3: what makes the song recognisable, and how each section feels — as measured
/// suggestions with their own confidences, never one merged score.
///
/// - Hook: the section whose line people know the song by. Distinct sections are ranked by how often
///   they repeat, how prominent their instrumental lead is, and how loud they are; an instrumental lead
///   with no singing over it (a signature BGM line, e.g. Hukum's) gets a bonus. The main tone is taken
///   from the hook's section. You can choose another section; your choice always wins.
/// - Mood: per section, energy (`ToneIntensity`) plus major/minor and brightness, mapped to plain
///   words. A labelled interpretation (rules, not a trained model: the open mood models found are
///   non-commercial), with an interpretation confidence.
public struct SongUnderstanding: Codable, Hashable, Sendable {
    public struct Hook: Codable, Hashable, Sendable {
        public enum Kind: String, Codable, Sendable { case bgm, vocal, mixed }
        public var sectionId: UUID
        public var kind: Kind
        /// Musical-role confidence: how clearly this section stood out from the next best (0...1).
        public var confidence: Double
        public var reason: String
        /// Next-best hook sections (by id), for "use another section".
        public var alternatives: [UUID]
        /// True when you picked it (kept on re-analysis).
        public var chosenByUser: Bool
        public init(sectionId: UUID, kind: Kind, confidence: Double, reason: String, alternatives: [UUID], chosenByUser: Bool) {
            self.sectionId = sectionId; self.kind = kind; self.confidence = confidence; self.reason = reason
            self.alternatives = alternatives; self.chosenByUser = chosenByUser
        }
    }

    public struct Mood: Codable, Hashable, Sendable {
        /// 0...1 energy / intensity.
        public var energy: Double
        /// −1...1: darker / minor ↔ brighter / major.
        public var valence: Double
        public var label: String
        /// Interpretation confidence (0...1): how far from the rule boundaries, and how sure the key is.
        public var confidence: Double
    }

    public var hook: Hook?
    /// By section id.
    public var moods: [String: Mood]
    /// The song's overall feel (the most common section label, weighted by duration).
    public var overall: String?

    public init(hook: Hook?, moods: [String: Mood], overall: String?) {
        self.hook = hook; self.moods = moods; self.overall = overall
    }

    public static func analyse(_ song: Song, timbres: [UUID: SectionTimbre] = [:]) -> SongUnderstanding {
        var song = song
        for i in song.sections.indices where song.sections[i].timbre == nil { song.sections[i].timbre = timbres[song.sections[i].id] }
        var moods: [String: Mood] = [:]
        for s in song.sections { if let m = mood(s, song: song) { moods[s.id.uuidString] = m } }
        var weight: [String: Double] = [:]
        for s in song.sections { if let m = moods[s.id.uuidString] { weight[m.label, default: 0] += s.duration } }
        let overall = weight.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
        var hook = findHook(song)
        if let kept = song.understanding?.hook, kept.chosenByUser, song.sections.contains(where: { $0.id == kept.sectionId }) { hook = kept }
        return SongUnderstanding(hook: hook, moods: moods, overall: overall)
    }

    static func level(_ s: SongSection, _ roles: [MusicalRole]) -> Double {
        (s.activity ?? []).filter { roles.contains($0.role) }.map(\.level).max() ?? 0
    }

    static func findHook(_ song: Song) -> Hook? {
        guard !song.sections.isEmpty else { return nil }
        var groups: [String: [SongSection]] = [:], order: [String] = []
        for s in song.sections.sorted(by: { $0.startTime < $1.startTime }) {
            let key = s.repetitionGroup.map { "\($0)-\(s.type.rawValue)" } ?? s.id.uuidString
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(s)
        }
        let loud = song.sections.compactMap { $0.timbre?.loudness }
        let lo = loud.min() ?? 0, hi = loud.max() ?? 1
        struct Cand { let section: SongSection; let score: Double; let kind: Hook.Kind; let reps: Int; let lead: Double; let vocal: Double }
        let cands: [Cand] = order.compactMap { key in
            guard let members = groups[key], let rep = members.max(by: { $0.duration < $1.duration }) else { return nil }
            let lead = members.map { level($0, [.lead, .motif]) }.max() ?? 0
            let vocal = members.map { level($0, [.vocalMelody]) }.max() ?? 0
            let l = members.compactMap { $0.timbre?.loudness }.max().map { hi > lo ? ($0 - lo) / (hi - lo) : 0.5 } ?? 0.5
            let bgm = lead >= 0.4 && vocal < 0.3
            let kind: Hook.Kind = bgm ? .bgm : (vocal >= 0.4 && lead < 0.3 ? .vocal : .mixed)
            let score = Double(members.count).squareRoot() * (0.4 + max(lead, vocal * 0.8)) * (0.6 + l)
                * (bgm ? 1.3 : 1) * (rep.type == .chorus ? 1.2 : 1) * (rep.isClimax == true ? 1.1 : 1)
            return Cand(section: rep, score: score, kind: kind, reps: members.count, lead: lead, vocal: vocal)
        }.sorted { $0.score > $1.score }
        guard let best = cands.first else { return nil }
        let second = cands.dropFirst().first?.score ?? 0
        let conf = best.score > 0 ? min(1, (best.score - second) / best.score * 2) : 0
        let what: String
        switch best.kind {
        case .bgm: what = "an instrumental line plays here with no singing over it (signature BGM)"
        case .vocal: what = "the sung melody carries this section"
        case .mixed: what = "the lead line and the song's energy peak here"
        }
        let reason = "heard \(best.reps)× in the song; \(what)."
        return Hook(sectionId: best.section.id, kind: best.kind, confidence: conf, reason: reason,
                    alternatives: cands.dropFirst().prefix(3).map(\.section.id), chosenByUser: false)
    }

    static func mood(_ s: SongSection, song: Song) -> Mood? {
        guard let t = s.timbre else { return nil }
        let all = song.sections.compactMap(\.timbre)
        let percussion = level(s, [.percussion])
        let energy = ToneIntensity.value(t, song: all.isEmpty ? [t] : all, percussion: percussion)
        let brightness = max(0, min(1, (t.centroid - 800) / 2200))
        let key = s.key ?? song.key
        let modeTerm: Double = key.map { $0.value.mode == .major ? 0.4 : -0.4 } ?? 0
        let valence = max(-1, min(1, modeTerm + (brightness - 0.5) * 0.6))
        let label: String
        switch (energy, valence >= 0) {
        case (..<0.35, true): label = "calm, warm"
        case (..<0.35, false): label = "tender, melancholic"
        case (..<0.65, true): label = "bright, flowing"
        case (..<0.65, false): label = "emotional, building"
        case (_, true): label = "energetic, celebratory"
        default: label = "intense, dramatic"
        }
        // Distance from the rule boundaries (energy 0.35 / 0.65, valence 0), times how sure the key is.
        let eMargin = min(abs(energy - 0.35), abs(energy - 0.65)) / 0.15
        let vMargin = abs(valence) / 0.3
        let conf = min(1, min(eMargin, vMargin)) * (key?.confidence ?? 0.5)
        return Mood(energy: energy, valence: valence, label: label, confidence: conf)
    }
}
