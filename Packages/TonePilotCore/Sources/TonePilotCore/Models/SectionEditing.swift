import Foundation

public enum SectionEditError: Error, Equatable {
    case sectionNotFound
    case splitPointOutsideSection
    case sectionsNotAdjacent
    case invalidRange
}

/// Pure editing operations on a song's section list. Every edit marks the
/// touched sections as user-provided, since the user has now confirmed them.
public enum SectionEditor {
    /// Minimum section length in seconds; avoids zero-length slivers from accidental taps.
    public static let minimumDuration = 0.5

    public static func split(_ sections: [SongSection], id: UUID, at time: Double) throws -> [SongSection] {
        guard let i = sections.firstIndex(where: { $0.id == id }) else { throw SectionEditError.sectionNotFound }
        let s = sections[i]
        guard time - s.startTime >= minimumDuration, s.endTime - time >= minimumDuration else {
            throw SectionEditError.splitPointOutsideSection
        }
        var first = s
        first.endTime = time
        first.provenance = .user
        first.confidence = 1
        var second = SongSection(type: s.type, label: s.label + " (2)", startTime: time, endTime: s.endTime,
                                 arrangementId: s.arrangementId, repetitionGroup: s.repetitionGroup)
        second.notes = s.notes
        var result = sections
        result[i] = first
        result.insert(second, at: i + 1)
        return result.sorted { $0.startTime < $1.startTime }
    }

    /// Merges two sections that touch (end of one == start of the other, within 10 ms).
    /// The earlier section's type, label and arrangement are kept.
    public static func merge(_ sections: [SongSection], _ a: UUID, _ b: UUID) throws -> [SongSection] {
        guard let sa = sections.first(where: { $0.id == a }), let sb = sections.first(where: { $0.id == b }) else {
            throw SectionEditError.sectionNotFound
        }
        let (first, second) = sa.startTime <= sb.startTime ? (sa, sb) : (sb, sa)
        guard abs(first.endTime - second.startTime) < 0.01 else { throw SectionEditError.sectionsNotAdjacent }
        var merged = first
        merged.endTime = second.endTime
        merged.provenance = .user
        merged.confidence = 1
        return sections
            .filter { $0.id != second.id }
            .map { $0.id == merged.id ? merged : $0 }
            .sorted { $0.startTime < $1.startTime }
    }

    /// Resizes a section and pushes the neighbouring boundaries so sections never overlap.
    public static func resize(_ sections: [SongSection], id: UUID, start: Double, end: Double,
                              songDuration: Double?) throws -> [SongSection] {
        let upper = songDuration ?? .greatestFiniteMagnitude
        let start = max(0, start)
        let end = min(upper, end)
        guard end - start >= minimumDuration else { throw SectionEditError.invalidRange }
        var ordered = sections.sorted { $0.startTime < $1.startTime }
        guard let i = ordered.firstIndex(where: { $0.id == id }) else { throw SectionEditError.sectionNotFound }
        if i > 0, ordered[i - 1].endTime > start {
            guard start - ordered[i - 1].startTime >= minimumDuration else { throw SectionEditError.invalidRange }
            ordered[i - 1].endTime = start
        }
        if i + 1 < ordered.count, ordered[i + 1].startTime < end {
            guard ordered[i + 1].endTime - end >= minimumDuration else { throw SectionEditError.invalidRange }
            ordered[i + 1].startTime = end
        }
        ordered[i].startTime = start
        ordered[i].endTime = end
        ordered[i].provenance = .user
        ordered[i].confidence = 1
        return ordered
    }

    /// The section playing at `time`, if any.
    public static func section(at time: Double, in sections: [SongSection]) -> SongSection? {
        sections.first { time >= $0.startTime && time < $0.endTime }
    }
}
