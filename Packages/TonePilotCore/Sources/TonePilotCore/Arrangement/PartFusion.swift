import Foundation

/// Sound-engine P3.3: the part matches from both separation models, compared and combined.
///
/// The 4-part model (vocals, drums, bass, music) and the 6-part model (adds piano and guitar) hear
/// the song's instruments differently, so the nearest library tones measured on their parts can
/// differ. After the first separation is usable, the app separates the song again with the other
/// model in the background and matches its parts the same way. Both sets are kept:
/// - where both models pick the same tone (or the same instrument family) the match is more certain;
/// - where they disagree, both candidates are shown and you choose.
///
/// The default ("fused") takes the melody (lead and each section's lead) and backing from the 4-part
/// model, which the owner found gives the better main tone, and piano / guitar from the 6-part model,
/// the only one that has those parts. That default is the owner's listening judgement (Nov 2026), not
/// a measured gate. "4 parts only" and "6 parts only" use one model's matches unchanged.
public struct PartFusion: Codable, Hashable, Sendable {
    public enum Agreement: String, Codable, Sendable {
        /// Both models picked the same tone.
        case same
        /// Different tones of the same instrument family.
        case sameFamily
        case different
        /// Only one model has this part (e.g. piano / guitar on the 6-part model).
        case onlyOne
    }

    /// One separation's matches.
    public struct MatchSet: Codable, Hashable, Sendable {
        /// "4" or "6" (number of separated parts).
        public var parts: Int
        public var matches: [String: PartMatch]
        public var sectionLeads: [String: PartMatch]
        public init(parts: Int, matches: [String: PartMatch], sectionLeads: [String: PartMatch]) {
            self.parts = parts; self.matches = matches; self.sectionLeads = sectionLeads
        }
        public var title: String { "\(parts) parts" }
        /// The melody match (lead when Music was split, else the Music part).
        public var melody: PartMatch? { matches[StemInfo.Kind.lead.rawValue] ?? matches[StemInfo.Kind.other.rawValue] }
    }

    public struct Entry: Codable, Hashable, Sendable {
        public var agreement: Agreement
        /// Tone names from the 4-part / 6-part models (nil = that model has no match here).
        public var quiet: String?
        public var six: String?
        /// Combined confidence (0...1): agreement between two independent separations raises it.
        public var confidence: Double
    }

    public enum Choice: String, Codable, Sendable, CaseIterable {
        case fused, quiet, six
        public var title: String {
            switch self {
            case .fused: return "Both models (melody from 4 parts, piano & guitar from 6 parts)"
            case .quiet: return "4 parts only"
            case .six: return "6 parts only"
            }
        }
    }

    public var quiet: MatchSet
    public var six: MatchSet
    /// Keys: "melody", "backing", "piano", "guitar", and "section:<section id>".
    public var entries: [String: Entry]
    public var choice: Choice

    public static let melodyKey = "melody"
    public static func sectionKey(_ id: UUID) -> String { "section:\(id.uuidString)" }

    /// Compares the two models' matches. `patches` gives each tone's family.
    public static func fuse(quiet: MatchSet, six: MatchSet, patches: [InstrumentPatch], choice: Choice = .fused) -> PartFusion {
        let family = Dictionary(patches.map { ($0.id, $0.family) }, uniquingKeysWith: { a, _ in a })
        func entry(_ a: PartMatch?, _ b: PartMatch?) -> Entry? {
            guard a != nil || b != nil else { return nil }
            let agreement: Agreement
            if let a, let b {
                if a.patchId == b.patchId { agreement = .same }
                else if let fa = family[a.patchId], fa == family[b.patchId], fa != .other { agreement = .sameFamily }
                else { agreement = .different }
            } else {
                agreement = .onlyOne
            }
            // Each model's own certainty: perceptual picks count as their measured search score, the
            // fingerprint path as its match %. Agreement of two separations lifts it; disagreement halves it.
            func own(_ m: PartMatch?) -> Double {
                guard let m else { return 0 }
                return max(0, min(1, m.perceptualScore.map { ($0 + 1) / 2 } ?? m.similarity))
            }
            let base = max(own(a), own(b))
            let confidence: Double
            switch agreement {
            case .same: confidence = 1 - (1 - own(a)) * (1 - own(b))   // two independent hits
            case .sameFamily: confidence = min(1, base * 1.1)
            case .different: confidence = base * 0.5
            case .onlyOne: confidence = base
            }
            return Entry(agreement: agreement, quiet: a?.name, six: b?.name, confidence: confidence)
        }
        var entries: [String: Entry] = [:]
        entries[melodyKey] = entry(quiet.melody, six.melody)
        for k in [StemInfo.Kind.backing, .piano, .guitar] {
            entries[k.rawValue] = entry(quiet.matches[k.rawValue], six.matches[k.rawValue])
        }
        for id in Set(quiet.sectionLeads.keys).union(six.sectionLeads.keys) {
            guard let uuid = UUID(uuidString: id) else { continue }
            entries[sectionKey(uuid)] = entry(quiet.sectionLeads[id], six.sectionLeads[id])
        }
        return PartFusion(quiet: quiet, six: six, entries: entries, choice: choice)
    }

    /// Matches one separation's parts exactly as the analysis does (every part, then each distinct
    /// section's lead when the nearest-sound search is available). Heavy: run off the main thread.
    public static func matchSet(parts: Int, song: Song, stems: [StemInfo.Kind: AudioBuffer], patches: [InstrumentPatch],
                                instrument: (InstrumentPatch) -> LoadedInstrument?, perceptual: PartMatcher.PerceptualHook?,
                                progress: ((Double) -> Bool)? = nil) -> MatchSet {
        let matches = PartMatcher.match(song: song, parts: stems, patches: patches, instrument: instrument, perceptual: perceptual) { p in
            progress?(p * (perceptual == nil ? 1 : 0.7)) ?? true
        }
        let leads = perceptual.map { PartMatcher.matchSectionLeads(song: song, parts: stems, patches: patches, instrument: instrument, perceptual: $0) } ?? [:]
        _ = progress?(1)
        return MatchSet(parts: parts, matches: matches, sectionLeads: leads)
    }

    /// The matches the arranger uses for `choice`.
    public func set(for choice: Choice) -> (matches: [String: PartMatch], sectionLeads: [String: PartMatch]) {
        switch choice {
        case .quiet: return (quiet.matches, quiet.sectionLeads)
        case .six: return (six.matches, six.sectionLeads)
        case .fused:
            var m: [String: PartMatch] = [:]
            // Melody + backing from the 4-part model (the melody falls back to the 6-part one if it has none).
            if let melody = quiet.melody ?? six.melody { m[melody.part] = melody }
            if let b = quiet.matches[StemInfo.Kind.backing.rawValue] ?? six.matches[StemInfo.Kind.backing.rawValue] { m[b.part] = b }
            for k in [StemInfo.Kind.piano, .guitar] { if let p = six.matches[k.rawValue] ?? quiet.matches[k.rawValue] { m[k.rawValue] = p } }
            return (m, six.sectionLeads.merging(quiet.sectionLeads) { _, q in q })
        }
    }

    /// True while the song still uses matches from this fusion (a re-analysis replaces them).
    public func isCurrent(_ song: Song) -> Bool {
        let s = set(for: choice)
        return (song.partMatches ?? [:]) == s.matches && (song.sectionLeadMatches ?? [:]) == s.sectionLeads
    }

    /// Applies `choice` to the song's matches (call the arranger afterwards to rebuild the tones).
    public static func apply(_ choice: Choice, to song: inout Song) {
        guard var f = song.fusion else { return }
        f.choice = choice
        let s = f.set(for: choice)
        song.partMatches = s.matches.isEmpty ? nil : s.matches
        song.sectionLeadMatches = s.sectionLeads.isEmpty ? nil : s.sectionLeads
        song.fusion = f
    }

    /// The entry that describes the main tone: its hook section's lead, else the melody part.
    public func mainEntry(_ song: Song) -> Entry? {
        if let hook = song.understanding?.hook, let e = entries[Self.sectionKey(hook.sectionId)] { return e }
        return entries[Self.melodyKey]
    }

    /// Plain words for an entry, e.g. "4- and 6-part models agree: Flute".
    public static func describe(_ e: Entry) -> String {
        switch e.agreement {
        case .same: return "Both separations agree: \(e.quiet ?? e.six ?? "")"
        case .sameFamily: return "Both separations hear the same instrument: \(e.quiet ?? "") / \(e.six ?? "")"
        case .different: return "Separations differ: 4 parts heard \(e.quiet ?? "—"), 6 parts heard \(e.six ?? "—")"
        case .onlyOne: return "Only the \(e.quiet != nil ? "4" : "6")-part model heard this: \(e.quiet ?? e.six ?? "")"
        }
    }
}
