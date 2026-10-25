import Foundation

public enum SoundFontError: Error, Equatable {
    case notRIFF
    case notSoundFont
    case missingChunk(String)
    case malformed(String)
    case presetNotFound(bank: Int, program: Int)
}

/// One playable key/velocity zone, fully resolved from SF2 preset + instrument generators.
/// Plain-old-data so the render thread can read it without reference counting.
public struct Region: Sendable {
    public var keyLow: UInt8 = 0
    public var keyHigh: UInt8 = 127
    public var velLow: UInt8 = 0
    public var velHigh: UInt8 = 127
    /// Absolute frame indices into the instrument's sample pool.
    public var start: Int = 0
    public var end: Int = 0
    public var loopStart: Int = 0
    public var loopEnd: Int = 0
    /// 0 = no loop, 1 = loop continuously, 3 = loop while held then play to the end.
    public var loopMode: UInt8 = 0
    public var sampleRate: Double = 44_100
    public var rootKey: Int = 60
    /// Tuning offset in cents (coarse*100 + fine + sample pitch correction).
    public var tuneCents: Double = 0
    /// Cents per key (100 = normal keyboard tracking).
    public var scaleTuning: Double = 100
    /// Linear gain from initialAttenuation.
    public var gain: Float = 1
    /// -1...1
    public var pan: Float = 0
    /// Envelope in seconds / sustain as linear level.
    public var envDelay: Float = 0
    public var envAttack: Float = 0.001
    public var envHold: Float = 0
    public var envDecay: Float = 0.001
    public var envSustain: Float = 1
    public var envRelease: Float = 0.001
    /// Hz; >= 19 000 means "filter open".
    public var filterCutoff: Float = 20_000
    /// Q-ish resonance from initialFilterQ (dB).
    public var filterResonanceDB: Float = 0

    public init() {}

    @inline(__always) public func matches(note: UInt8, velocity: UInt8) -> Bool {
        note >= keyLow && note <= keyHigh && velocity >= velLow && velocity <= velHigh
    }
}

public struct SoundFontPresetInfo: Hashable, Sendable {
    public let name: String
    public let bank: Int
    public let program: Int
}

/// Parsed SF2 bank. Sample data stays as 16-bit PCM (half the memory of Float) and is
/// shared by every preset loaded from this bank.
public final class SoundFontBank: @unchecked Sendable {
    public let name: String
    public let presets: [SoundFontPresetInfo]
    /// Owned sample pool (16-bit PCM, mono frames). Freed in deinit.
    public let samples: UnsafeMutableBufferPointer<Int16>

    private struct PresetHeader { let name: String; let program: Int; let bank: Int; let bagIndex: Int }
    private struct Bag { let gen: Int }
    private struct Gen { let oper: UInt16; let amount: Int16; var lo: UInt8 { UInt8(truncatingIfNeeded: UInt16(bitPattern: amount)) }; var hi: UInt8 { UInt8(truncatingIfNeeded: UInt16(bitPattern: amount) >> 8) } }
    private struct InstHeader { let name: String; let bagIndex: Int }
    private struct SampleHeader { let name: String; let start: Int; let end: Int; let loopStart: Int; let loopEnd: Int; let rate: Int; let pitch: Int; let correction: Int; let type: Int }

    private let phdr: [PresetHeader]
    private let pbag: [Bag]
    private let pgen: [Gen]
    private let inst: [InstHeader]
    private let ibag: [Bag]
    private let igen: [Gen]
    private let shdr: [SampleHeader]

    deinit { samples.deallocate() }

    public convenience init(url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .mappedIfSafe), name: url.deletingPathExtension().lastPathComponent)
    }

    public init(data: Data, name: String = "SoundFont") throws {
        self.name = name
        let r = ByteReader(data)
        guard data.count >= 12, r.fourCC(0) == "RIFF" else { throw SoundFontError.notRIFF }
        guard r.fourCC(8) == "sfbk" else { throw SoundFontError.notSoundFont }

        var smpl: (Int, Int)?
        var pdta: [String: (Int, Int)] = [:]
        var offset = 12
        while offset + 8 <= data.count {
            let id = r.fourCC(offset)
            let size = Int(r.u32(offset + 4))
            let body = offset + 8
            guard body + size <= data.count else { break }
            if id == "LIST" {
                let type = r.fourCC(body)
                var sub = body + 4
                while sub + 8 <= body + size {
                    let sid = r.fourCC(sub)
                    let ssize = Int(r.u32(sub + 4))
                    if type == "sdta", sid == "smpl" { smpl = (sub + 8, ssize) }
                    if type == "pdta" { pdta[sid] = (sub + 8, ssize) }
                    sub += 8 + ssize + (ssize & 1)
                }
            }
            offset = body + size + (size & 1)
        }
        guard let smpl else { throw SoundFontError.missingChunk("smpl") }
        for key in ["phdr", "pbag", "pgen", "inst", "ibag", "igen", "shdr"] where pdta[key] == nil {
            throw SoundFontError.missingChunk(key)
        }

        func records<T>(_ key: String, _ size: Int, _ make: (Int) -> T) -> [T] {
            let (start, length) = pdta[key]!
            return (0..<(length / size)).map { make(start + $0 * size) }
        }
        phdr = records("phdr", 38) { PresetHeader(name: r.string($0, 20), program: Int(r.u16($0 + 20)), bank: Int(r.u16($0 + 22)), bagIndex: Int(r.u16($0 + 24))) }
        pbag = records("pbag", 4) { Bag(gen: Int(r.u16($0))) }
        pgen = records("pgen", 4) { Gen(oper: r.u16($0), amount: Int16(bitPattern: r.u16($0 + 2))) }
        inst = records("inst", 22) { InstHeader(name: r.string($0, 20), bagIndex: Int(r.u16($0 + 20))) }
        ibag = records("ibag", 4) { Bag(gen: Int(r.u16($0))) }
        igen = records("igen", 4) { Gen(oper: r.u16($0), amount: Int16(bitPattern: r.u16($0 + 2))) }
        shdr = records("shdr", 46) {
            SampleHeader(name: r.string($0, 20), start: Int(r.u32($0 + 20)), end: Int(r.u32($0 + 24)),
                         loopStart: Int(r.u32($0 + 28)), loopEnd: Int(r.u32($0 + 32)), rate: Int(r.u32($0 + 36)),
                         pitch: Int(data[data.startIndex + $0 + 40]), correction: Int(Int8(bitPattern: data[data.startIndex + $0 + 41])),
                         type: Int(r.u16($0 + 44)))
        }
        guard phdr.count >= 2, inst.count >= 2, shdr.count >= 2 else { throw SoundFontError.malformed("empty bank") }

        let frameCount = smpl.1 / 2
        let pool = UnsafeMutableBufferPointer<Int16>.allocate(capacity: max(1, frameCount))
        pool.initialize(repeating: 0)
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: smpl.0)
            for i in 0..<frameCount {
                pool[i] = Int16(littleEndian: base.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))
            }
        }
        samples = pool
        // Last record of phdr/inst/shdr is the terminal "EOP"/"EOI"/"EOS" sentinel.
        presets = phdr.dropLast().map { SoundFontPresetInfo(name: $0.name, bank: $0.bank, program: $0.program) }
            .sorted { ($0.bank, $0.program) < ($1.bank, $1.program) }
    }

    public func hasPreset(bank: Int, program: Int) -> Bool { presets.contains { $0.bank == bank && $0.program == program } }

    /// Resolves every region of a preset. SF2 rules: instrument global zone gives defaults,
    /// local zones override; preset generators *add* to instrument values; ranges intersect.
    public func regions(bank: Int, program: Int) throws -> [Region] {
        guard let pIndex = phdr.indices.dropLast().first(where: { phdr[$0].bank == bank && phdr[$0].program == program }) else {
            throw SoundFontError.presetNotFound(bank: bank, program: program)
        }
        var result: [Region] = []
        let pBags = phdr[pIndex].bagIndex..<phdr[pIndex + 1].bagIndex
        var presetGlobal: [UInt16: Gen] = [:]
        for (n, b) in pBags.enumerated() where b + 1 < pbag.count {
            let gens = Dictionary(pgen[pbag[b].gen..<pbag[b + 1].gen].map { ($0.oper, $0) }, uniquingKeysWith: { $1 })
            guard let instGen = gens[41] else {
                if n == 0 { presetGlobal = gens } // global preset zone
                continue
            }
            let pz = presetGlobal.merging(gens) { $1 }
            let iIndex = Int(UInt16(bitPattern: instGen.amount))
            guard iIndex + 1 < inst.count else { continue }
            var instGlobal: [UInt16: Gen] = [:]
            for (m, ib) in (inst[iIndex].bagIndex..<inst[iIndex + 1].bagIndex).enumerated() where ib + 1 < ibag.count {
                let igens = Dictionary(igen[ibag[ib].gen..<ibag[ib + 1].gen].map { ($0.oper, $0) }, uniquingKeysWith: { $1 })
                guard let sampleGen = igens[53] else {
                    if m == 0 { instGlobal = igens }
                    continue
                }
                let iz = instGlobal.merging(igens) { $1 }
                let sIndex = Int(UInt16(bitPattern: sampleGen.amount))
                guard sIndex < shdr.count - 1 else { continue }
                if let region = makeRegion(instrument: iz, preset: pz, sample: shdr[sIndex]) { result.append(region) }
            }
        }
        return result
    }

    private func makeRegion(instrument iz: [UInt16: Gen], preset pz: [UInt16: Gen], sample s: SampleHeader) -> Region? {
        func iv(_ op: UInt16, _ def: Int) -> Int { iz[op].map { Int($0.amount) } ?? def }
        func pv(_ op: UInt16) -> Int { pz[op].map { Int($0.amount) } ?? 0 }
        func sum(_ op: UInt16, _ def: Int) -> Int { iv(op, def) + pv(op) }
        func range(_ op: UInt16) -> (UInt8, UInt8) {
            let i = iz[op].map { ($0.lo, $0.hi) } ?? (0, 127)
            let p = pz[op].map { ($0.lo, $0.hi) } ?? (0, 127)
            return (max(i.0, p.0), min(i.1, p.1))
        }
        func seconds(_ timecents: Int) -> Float { timecents <= -12_000 ? 0.001 : Float(pow(2, Double(timecents) / 1200)) }

        var r = Region()
        (r.keyLow, r.keyHigh) = range(43)
        (r.velLow, r.velHigh) = range(44)
        guard r.keyLow <= r.keyHigh, r.velLow <= r.velHigh else { return nil }

        // Address offsets are instrument-level only (presets may not change them).
        r.start = s.start + iv(0, 0) + iv(4, 0) * 32_768
        r.end = s.end + iv(1, 0) + iv(12, 0) * 32_768
        r.loopStart = s.loopStart + iv(2, 0) + iv(45, 0) * 32_768
        r.loopEnd = s.loopEnd + iv(3, 0) + iv(50, 0) * 32_768
        let poolCount = samples.count
        r.start = max(0, min(r.start, poolCount - 1))
        r.end = max(r.start + 1, min(r.end, poolCount))
        r.loopStart = max(r.start, min(r.loopStart, r.end - 1))
        r.loopEnd = max(r.loopStart + 1, min(r.loopEnd, r.end))
        r.loopMode = UInt8(iv(54, 0) & 3)
        if r.loopMode == 2 { r.loopMode = 0 }
        r.sampleRate = Double(max(1, s.rate))

        let overrideRoot = iv(58, -1)
        r.rootKey = overrideRoot >= 0 ? overrideRoot : (s.pitch <= 127 ? s.pitch : 60)
        r.tuneCents = Double(sum(51, 0) * 100 + sum(52, 0) + s.correction)
        r.scaleTuning = Double(sum(56, 100))
        // initialAttenuation is in centibels; GM banks are usually mixed with a 0.4 factor (FluidSynth convention).
        let attenuation = Double(max(0, sum(48, 0))) * 0.4
        r.gain = Float(pow(10, -attenuation / 200))
        r.pan = Float(max(-500, min(500, sum(17, 0)))) / 500

        r.envDelay = sum(33, -12_000) <= -12_000 ? 0 : seconds(sum(33, -12_000))
        r.envAttack = seconds(sum(34, -12_000))
        r.envHold = sum(35, -12_000) <= -12_000 ? 0 : seconds(sum(35, -12_000))
        r.envDecay = seconds(sum(36, -12_000))
        let sustainCB = Double(max(0, min(1440, sum(37, 0))))
        r.envSustain = Float(pow(10, -sustainCB / 200))
        r.envRelease = max(0.005, seconds(sum(38, -12_000)))

        let fcCents = Double(sum(8, 13_500))
        r.filterCutoff = Float(8.176 * pow(2, fcCents / 1200))
        r.filterResonanceDB = Float(max(0, sum(9, 0))) / 10
        return r
    }
}

/// Little-endian reader over Data with absolute offsets.
struct ByteReader {
    let data: Data
    init(_ data: Data) { self.data = data }

    @inline(__always) func u8(_ o: Int) -> UInt8 { data[data.startIndex + o] }
    func u16(_ o: Int) -> UInt16 { UInt16(u8(o)) | UInt16(u8(o + 1)) << 8 }
    func u32(_ o: Int) -> UInt32 { UInt32(u16(o)) | UInt32(u16(o + 2)) << 16 }
    func fourCC(_ o: Int) -> String { String(bytes: (0..<4).map { u8(o + $0) }, encoding: .ascii) ?? "" }
    func string(_ o: Int, _ length: Int) -> String {
        let bytes = (0..<length).map { u8(o + $0) }.prefix { $0 != 0 }
        return String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespaces)
    }
}
