import Foundation

/// A downloadable real-instrument sound pack (phase 1 of the sound-engine plan): multisampled
/// recordings from openly licensed (CC0) libraries, built in CI by `Native/tools/sounds/build_packs.py`
/// and published on the `sounds-v1` release. The app downloads a pack, unpacks it under the sample
/// directory (`packs/<id>/`) and adds its tones to the library; the tones then play through the same
/// `ToneEngine` multisample path as user samples, and join the nearest-sound search through the
/// embeddings the pack carries (computed in CI with the app's exact pipeline).
public struct SoundPack: Codable, Hashable, Sendable {
    public struct Source: Codable, Hashable, Sendable {
        public var library: String
        public var license: String
        public var commit: String
        /// Every original file used (provenance).
        public var files: [String]
    }

    public struct Tone: Codable, Hashable, Sendable {
        public var id: UUID
        public var name: String
        public var family: String
        public var envelope: Envelope
        public var zones: [SampleZone]
        /// Preset playing style (vibrato, glide, mono) and filter, e.g. "Arabic-style Strings"; nil = plain.
        public var expression: ExpressionSettings?
        public var filter: FilterSettings?
    }

    public struct File: Codable, Hashable, Sendable {
        public var sha256: String
        public var bytes: Int
        public var frames: Int
    }

    /// Search embeddings for the pack's tones (same format as the bundled tone tables).
    public struct Embeddings: Codable, Hashable, Sendable {
        public var harmonic: [PerceptualToneSearch.ToneTable.Entry]
        public var plain: [PerceptualToneSearch.ToneTable.Entry]
    }

    public var format: Int
    public var id: String
    public var version: Int
    public var name: String
    public var family: String
    public var sampleRate: Double
    public var source: Source
    public var tones: [Tone]
    public var files: [String: File]
    public var embeddings: Embeddings?

    public static let supportedFormat = 1

    public static func decode(_ data: Data) throws -> SoundPack {
        let pack = try JSONDecoder().decode(SoundPack.self, from: data)
        guard pack.format == supportedFormat else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "pack format \(pack.format)")) }
        return pack
    }

    /// Problems that would make the pack unplayable (empty list = fine).
    public func problems() -> [String] {
        var out: [String] = []
        if tones.isEmpty { out.append("no tones") }
        for t in tones {
            if t.zones.isEmpty { out.append("\(t.name): no zones") }
            for z in t.zones {
                let file = (z.fileName as NSString).lastPathComponent
                if files[file] == nil { out.append("\(t.name): zone file \(file) not listed") }
                if !z.fileName.hasPrefix("packs/\(id)/") { out.append("\(t.name): \(z.fileName) outside the pack folder") }
                if let s = z.loopStart, let e = z.loopEnd, e <= s { out.append("\(t.name): empty loop in \(file)") }
            }
            // Every key of the 61-key keyboard (C2–C7) must play something at a normal velocity.
            for key in 36...96 where !t.zones.contains(where: { $0.keyRange.contains(UInt8(key)) && $0.velocityRange.contains(100) }) {
                out.append("\(t.name): key \(key) not covered"); break
            }
        }
        return out
    }

    /// The pack's tones as library patches (licensed samples, CC0).
    public var patches: [InstrumentPatch] {
        tones.map { t in
            InstrumentPatch(id: t.id, name: t.name, family: InstrumentFamily(rawValue: t.family) ?? .other, sourceType: .licensedSample,
                            sampleZones: t.zones, envelope: t.envelope, filter: t.filter ?? FilterSettings(),
                            license: LicenseInfo(name: source.license, url: source.library, redistributable: true,
                                                 notes: "Sound pack \(id) v\(version)"),
                            expression: t.expression, tags: ["sound-pack", id])
        }
    }
}

extension PerceptualToneSearch.ToneTable {
    /// This table plus extra entries (e.g. an installed sound pack's tones); entries whose size
    /// doesn't match are ignored.
    public func adding(_ extra: [Entry]) -> PerceptualToneSearch.ToneTable {
        let ok = extra.filter { $0.embedding.count == embeddingDim }
        return .init(version: version, model: model, embeddingDim: embeddingDim, entries: entries + ok)
    }
}
