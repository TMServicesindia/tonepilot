import Foundation

/// Shareable preset file (`.tonepilot`): composite tones plus any non-factory patches they use.
/// Sample audio is not embedded — sample patches list the files they need so the receiver
/// can supply their own authorised copies.
public struct PresetDocument: Codable, Sendable {
    public static let format = "tonepilot.preset"
    public var format: String
    public var version: Int
    public var arrangements: [Arrangement]
    public var patches: [InstrumentPatch]
    public var requiredSampleFiles: [String]
    public var exportedAt: Date

    public init(arrangements: [Arrangement], library: Library) {
        format = Self.format
        version = 1
        self.arrangements = arrangements
        let factory = Set(FactoryPatches.all.map(\.id))
        let ids = Set(arrangements.flatMap { $0.layers.map(\.patchId) })
        patches = library.patches.filter { ids.contains($0.id) && !factory.contains($0.id) }
        requiredSampleFiles = Array(Set(patches.flatMap { $0.sampleZones.map(\.fileName) })).sorted()
        exportedAt = Date()
    }
}

public enum PresetExchange {
    public enum Failure: Error, Equatable { case notAPreset, newerVersion(Int) }

    public static func export(_ arrangements: [Arrangement], from library: Library) throws -> Data {
        try LibraryCodec.encoder().encode(PresetDocument(arrangements: arrangements, library: library))
    }

    /// Adds the presets to the library as global tones (new ids, so nothing is overwritten).
    /// Returns the imported arrangements and sample files the user still needs to provide.
    public static func importPresets(_ data: Data, into library: inout Library) throws -> (arrangements: [Arrangement], missingSamples: [String]) {
        let doc: PresetDocument
        do { doc = try LibraryCodec.decoder().decode(PresetDocument.self, from: data) } catch { throw Failure.notAPreset }
        guard doc.format == PresetDocument.format else { throw Failure.notAPreset }
        guard doc.version <= 1 else { throw Failure.newerVersion(doc.version) }
        var patchMap: [UUID: UUID] = [:]
        for p in doc.patches {
            if library.patch(id: p.id) == p { patchMap[p.id] = p.id; continue }
            var copy = p
            copy.id = library.patch(id: p.id) == nil ? p.id : UUID()
            patchMap[p.id] = copy.id
            library.upsert(copy)
        }
        var imported: [Arrangement] = []
        for a in doc.arrangements {
            var copy = a.duplicated(name: a.name)
            copy.origin = .user
            copy.layers = copy.layers.map { var l = $0; l.patchId = patchMap[l.patchId] ?? l.patchId; return l }
            library.globalArrangements.append(copy)
            imported.append(copy)
        }
        return (imported, doc.requiredSampleFiles)
    }
}

public extension Song {
    /// The AI Original a section's My Version came from.
    func aiOriginal(for section: SongSection) -> Arrangement? {
        guard let current = arrangement(for: section) else { return nil }
        if current.origin == .aiOriginal { return current }
        guard let source = current.derivedFrom else { return nil }
        return arrangements.first { $0.id == source }
    }

    /// Throws away the user's edits for this section by copying the AI Original again.
    mutating func restoreAIOriginal(for sectionId: UUID) {
        guard let i = sections.firstIndex(where: { $0.id == sectionId }), let ai = aiOriginal(for: sections[i]) else { return }
        let old = sections[i].arrangementId
        let mine = ai.makeMyVersion()
        arrangements.append(mine)
        sections[i].arrangementId = mine.id
        if let old, old != ai.id, !sections.contains(where: { $0.arrangementId == old }) {
            arrangements.removeAll { $0.id == old }
        }
    }

    /// Gives one section its own copy of a shared arrangement (before editing just that section).
    mutating func detachArrangement(for sectionId: UUID) -> Arrangement? {
        guard let i = sections.firstIndex(where: { $0.id == sectionId }), let current = arrangement(for: sections[i]) else { return nil }
        guard sections.filter({ $0.arrangementId == current.id }).count > 1 else { return current }
        var copy = current
        copy.id = UUID()
        copy.name = "\(sections[i].label) (My Version)"
        arrangements.append(copy)
        sections[i].arrangementId = copy.id
        return copy
    }
}
