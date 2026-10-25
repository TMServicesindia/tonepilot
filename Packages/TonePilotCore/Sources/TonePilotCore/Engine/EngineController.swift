import Foundation

public enum InstrumentLoadError: Error, Equatable, LocalizedError {
    case soundFontMissing(String)
    case noSource(String)
    case sampleUnreadable(String)

    public var errorDescription: String? {
        switch self {
        case .soundFontMissing(let f): return "\(f) is not installed (Settings › SoundFonts)."
        case .noSource(let n): return "\(n) has no sound source."
        case .sampleUnreadable(let f): return "Sample \(f) could not be read."
        }
    }
}

/// Loads and caches playable instruments. Main-thread (or one serial queue) only.
///
/// Instruments that leave the active arrangement are *retired*, not freed: a held or
/// releasing voice may still read their samples. After a grace period the cache asks the
/// engine to stop any voice still using them, then frees them on a later maintenance pass.
public final class InstrumentCache {
    public let soundFontDirectory: URL
    public let sampleDirectory: URL
    /// Decodes a user sample file to mono floats. Default handles WAV; the iOS host plugs in
    /// AVAudioFile so MP3/M4A/AIFF samples work too.
    public var sampleDecoder: (URL) throws -> (frames: [Float], sampleRate: Double) = { try WAVDecoder.decodeMono(url: $0) }
    public var gracePeriod: TimeInterval = 20

    private var banks: [String: SoundFontBank] = [:]
    private var instruments: [String: LoadedInstrument] = [:]
    private var lastUsed: [String: Date] = [:]
    private var pendingKill: [(LoadedInstrument, Date)] = []

    public init(soundFontDirectory: URL, sampleDirectory: URL) {
        self.soundFontDirectory = soundFontDirectory
        self.sampleDirectory = sampleDirectory
    }

    public func bank(named file: String) throws -> SoundFontBank {
        if let b = banks[file] { return b }
        let url = soundFontDirectory.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: url.path) else { throw InstrumentLoadError.soundFontMissing(file) }
        let b = try SoundFontBank(url: url)
        banks[file] = b
        return b
    }

    public func register(bank: SoundFontBank, as file: String) { banks[file] = bank }

    static func key(for patch: InstrumentPatch) -> String {
        var h = Hasher()
        h.combine(patch.soundFont)
        h.combine(patch.sampleZones)
        h.combine(patch.synth)
        h.combine(patch.envelope)
        return "\(patch.id.uuidString)-\(h.finalize())"
    }

    public func instrument(for patch: InstrumentPatch) throws -> LoadedInstrument {
        let key = Self.key(for: patch)
        lastUsed[key] = Date()
        if let i = instruments[key] { return i }
        let loaded: LoadedInstrument
        if let synth = patch.synth, patch.sourceType == .synthesized {
            loaded = LoadedInstrument(name: patch.name, synth: synth)
        } else if !patch.sampleZones.isEmpty {
            let samples = try patch.sampleZones.map { zone -> LoadedInstrument.UserSample in
                do {
                    let d = try sampleDecoder(sampleDirectory.appendingPathComponent(zone.fileName))
                    return LoadedInstrument.UserSample(frames: d.frames, sampleRate: d.sampleRate, zone: zone)
                } catch { throw InstrumentLoadError.sampleUnreadable(zone.fileName) }
            }
            loaded = LoadedInstrument(name: patch.name, userSamples: samples, envelope: patch.envelope)
        } else if let ref = patch.soundFont {
            let b = try bank(named: ref.fileName)
            // Apple's melodic bank MSB 0x79 maps to SF2 bank 0; 0x78 (percussion) to bank 128.
            let bankNumber = ref.bankMSB == SoundFontReference.percussionBankMSB ? 128 : (ref.bankMSB == SoundFontReference.melodicBankMSB ? Int(ref.bankLSB) : Int(ref.bankMSB))
            loaded = try LoadedInstrument(bank: b, bankNumber: bankNumber, program: Int(ref.program), name: patch.name)
        } else {
            throw InstrumentLoadError.noSource(patch.name)
        }
        instruments[key] = loaded
        return loaded
    }

    /// Loads instruments for upcoming sections ahead of time so switching never waits on disk.
    @discardableResult
    public func preload(_ patches: [InstrumentPatch]) -> [String] {
        patches.compactMap { p in
            do { _ = try instrument(for: p); return nil } catch { return "\(p.name): \(error.localizedDescription)" }
        }
    }

    /// Call every few seconds from the main thread with the instruments currently in use.
    /// Returns commands to send to the engine before memory is released.
    public func maintenance(inUse: Set<ObjectIdentifier>, now: Date = Date()) -> [EngineCommand] {
        // Free what was killed on a previous pass (the engine has rendered since).
        pendingKill.removeAll { now.timeIntervalSince($0.1) > 0.5 }
        var commands: [EngineCommand] = []
        for (key, inst) in instruments where !inUse.contains(ObjectIdentifier(inst)) {
            guard now.timeIntervalSince(lastUsed[key] ?? .distantPast) > gracePeriod else { continue }
            if let p = inst.regions.baseAddress { commands.append(.killRegions(UnsafePointer(p))) }
            pendingKill.append((inst, now))
            instruments[key] = nil
            lastUsed[key] = nil
        }
        return commands
    }

    public var loadedCount: Int { instruments.count }
}

/// Bridges the app's layer-based world (UUIDs, `SoundCommand`s from `NoteRouter`) to the
/// engine's handle/slot world. `perform` is safe to call from the MIDI thread.
public final class ToneEngineController: @unchecked Sendable {
    public let engine: ToneEngine
    private let lock = NSLock()
    private var handleByLayer: [UUID: UInt32] = [:]
    private var nextHandle: UInt32 = 1
    // Main-thread state
    private var slotByLayer: [UUID: Int] = [:]
    private var instrumentBySlot: [Int: LoadedInstrument] = [:]

    public init(engine: ToneEngine) {
        self.engine = engine
    }

    /// Stable engine handle for a layer id (thread-safe).
    public func handle(for layerId: UUID) -> UInt32 {
        lock.lock(); defer { lock.unlock() }
        if let h = handleByLayer[layerId] { return h }
        let h = nextHandle
        nextHandle &+= 1
        if nextHandle == 0 { nextHandle = 1 }
        handleByLayer[layerId] = h
        return h
    }

    /// MIDI thread: forward router output to the engine.
    public func perform(_ commands: [SoundCommand]) {
        for c in commands {
            switch c {
            case let .start(id, note, vel): engine.send(.noteOn(handle: handle(for: id), note: note, velocity: vel))
            case let .stop(id, note): engine.send(.noteOff(handle: handle(for: id), note: note))
            case let .sustain(id, on): engine.send(.sustain(handle: handle(for: id), on: on))
            case let .controller(id, cc, value): engine.send(.controller(handle: handle(for: id), cc: cc, value: value))
            case let .pitchBend(id, value): engine.send(.pitchBend(handle: handle(for: id), value: value))
            case .allNotesOff: engine.send(.allNotesOff)
            }
        }
    }

    /// Main thread: makes `arrangement` the live tone. Layers that stay keep their slot (so
    /// held notes and EQ state continue); removed layers' voices release naturally.
    /// Returns human-readable load failures.
    @discardableResult
    public func apply(_ arrangement: Arrangement?, patches: [UUID: InstrumentPatch], cache: InstrumentCache) -> [String] {
        let layers = Array((arrangement?.audibleLayers ?? []).prefix(ToneEngine.liveSlotCount))
        let headroom = arrangement.map { a in layers.map { GainStaging.effectiveGain(layer: $0, in: a) / max(a.masterGain, 0.001) } } ?? []
        var failures: [String] = []
        let keep = Set(layers.map(\.id))

        for (id, slot) in slotByLayer where !keep.contains(id) {
            engine.send(.clearSlot(index: slot))
            slotByLayer[id] = nil
            instrumentBySlot[slot] = nil
        }
        var freeSlots = (0..<ToneEngine.liveSlotCount).filter { s in !slotByLayer.values.contains(s) }

        for (i, layer) in layers.enumerated() {
            guard let patch = patches[layer.patchId] else { failures.append("Missing patch for a layer"); continue }
            let inst: LoadedInstrument
            do { inst = try cache.instrument(for: patch) } catch {
                failures.append("\(patch.name): \(error.localizedDescription)")
                continue
            }
            let slot: Int
            if let s = slotByLayer[layer.id] { slot = s } else if !freeSlots.isEmpty { slot = freeSlots.removeFirst() } else { continue }
            slotByLayer[layer.id] = slot
            instrumentBySlot[slot] = inst
            let config = EngineLayerConfig.make(layer: layer, patch: patch, instrument: inst,
                                                handle: handle(for: layer.id), headroomGain: headroom[i])
            engine.send(.setSlot(index: slot, config: config))
        }
        sendMaster(arrangement)
        return failures
    }

    private var lastAccompanimentGain: Float = 0.8
    private var lastLiveGain: Float = 1

    private func sendMaster(_ arrangement: Arrangement?) {
        var m = EngineMasterConfig(gain: arrangement?.masterGain ?? 0.8, effects: arrangement?.masterEffects ?? MasterEffects(),
                                   accompanimentGain: Double(lastAccompanimentGain))
        m.liveGain = lastLiveGain
        engine.send(.setMaster(m))
    }

    /// Song Studio mixer: level of your live keyboard tone and of all generated backing parts.
    public func setMixLevels(live: Double, accompaniment: Double, arrangement: Arrangement?) {
        lastLiveGain = Float(max(0, min(1.5, live)))
        lastAccompanimentGain = Float(max(0, min(1.5, accompaniment)))
        sendMaster(arrangement)
    }

    /// Configures an accompaniment slot (bass, drums, melody guide, metronome) or clears it with nil.
    @discardableResult
    public func setAccompaniment(_ slot: ToneEngine.AccompanimentSlot, patch: InstrumentPatch?, volume: Double,
                                 cache: InstrumentCache) -> String? {
        let id = Self.accompanimentLayerId(slot)
        guard let patch else {
            engine.send(.releaseHandle(handle(for: id)))
            engine.send(.clearSlot(index: slot.rawValue))
            instrumentBySlot[slot.rawValue] = nil
            return nil
        }
        do {
            let inst = try cache.instrument(for: patch)
            instrumentBySlot[slot.rawValue] = inst
            var c = EngineLayerConfig.make(layer: Layer(id: id, patchId: patch.id, volume: volume), patch: patch,
                                           instrument: inst, handle: handle(for: id), headroomGain: volume)
            c.isAccompaniment = true
            c.mono = false
            if slot == .melodyGuide { c.bendRange = Float(AccompanimentGenerator.guideBendRange) }
            engine.send(.setSlot(index: slot.rawValue, config: c))
            return nil
        } catch {
            return "\(patch.name): \(error.localizedDescription)"
        }
    }

    public func setAccompanimentLevel(_ level: Double, arrangement: Arrangement?) {
        lastAccompanimentGain = Float(level)
        sendMaster(arrangement)
    }

    /// Fixed layer ids for accompaniment tracks, so sequencer events can address them.
    public static func accompanimentLayerId(_ slot: ToneEngine.AccompanimentSlot) -> UUID {
        UUID(uuidString: String(format: "ACC0AAAA-0000-4000-8000-%012X", slot.rawValue))!
    }

    public func accompanimentHandle(_ slot: ToneEngine.AccompanimentSlot) -> UInt32 { handle(for: Self.accompanimentLayerId(slot)) }

    /// Instruments currently referenced by slots (for `InstrumentCache.maintenance`).
    public var instrumentsInUse: Set<ObjectIdentifier> { Set(instrumentBySlot.values.map(ObjectIdentifier.init)) }

    // MARK: Sequencer

    private var sequenceBuffers: [(Int, UnsafeMutableBufferPointer<SequencerEvent>)] = []
    private var sequenceGeneration = 0

    /// Installs a new event list (sorted by frame). Old buffers are freed once the engine moved on.
    public func setSequence(_ events: [SequencerEvent]) {
        sequenceGeneration += 1
        // At equal frames: note-offs, then note-ons, then pitch bends.
        func rank(_ e: SequencerEvent) -> Int { e.bend != nil ? 2 : (e.velocity == 0 ? 0 : 1) }
        let sorted = events.sorted { ($0.frame, rank($0)) < ($1.frame, rank($1)) }
        let buf = UnsafeMutableBufferPointer<SequencerEvent>.allocate(capacity: max(1, sorted.count))
        _ = buf.initialize(from: sorted)
        sequenceBuffers.append((sequenceGeneration, buf))
        engine.send(.setSequence(events: UnsafePointer(buf.baseAddress), count: sorted.count, generation: sequenceGeneration))
        collectSequenceBuffers()
    }

    /// Frees event buffers the engine no longer reads. Call from the main thread periodically.
    public func collectSequenceBuffers() {
        let inUse = engine.sequenceGenerationInUse
        sequenceBuffers.removeAll { gen, buf in
            if gen < inUse { buf.deallocate(); return true }
            return false
        }
    }

    /// Starts/stops/seeks the engine's song clock (seconds on the song timeline).
    public func setTransport(playing: Bool, seconds: Double) {
        engine.send(.transport(playing: playing, frame: Int64(max(0, seconds) * engine.sampleRate)))
    }

    deinit { sequenceBuffers.forEach { $0.1.deallocate() } }
}

/// Minimal PCM/float WAV reader for user samples (16/24/32-bit int, 32-bit float; mixes to mono).
public enum WAVDecoder {
    public enum Failure: Error { case notWAV, unsupported(String) }

    public static func decodeMono(url: URL) throws -> (frames: [Float], sampleRate: Double) {
        try decodeMono(data: Data(contentsOf: url))
    }

    public static func decodeMono(data: Data) throws -> (frames: [Float], sampleRate: Double) {
        let r = ByteReader(data)
        guard data.count > 44, r.fourCC(0) == "RIFF", r.fourCC(8) == "WAVE" else { throw Failure.notWAV }
        var offset = 12
        var format = 0, channels = 0, rate = 0, bits = 0
        var dataRange: (Int, Int)?
        while offset + 8 <= data.count {
            let id = r.fourCC(offset)
            let size = Int(r.u32(offset + 4))
            if id == "fmt " {
                format = Int(r.u16(offset + 8)); channels = Int(r.u16(offset + 10))
                rate = Int(r.u32(offset + 12)); bits = Int(r.u16(offset + 22))
                if format == 0xFFFE, size >= 26 { format = Int(r.u16(offset + 32)) } // WAVE_FORMAT_EXTENSIBLE
            } else if id == "data" {
                dataRange = (offset + 8, min(size, data.count - offset - 8))
            }
            offset += 8 + size + (size & 1)
        }
        guard let (start, length) = dataRange, channels > 0, rate > 0 else { throw Failure.notWAV }
        let bytesPer = bits / 8
        guard [1, 3].contains(format), [16, 24, 32].contains(bits) else { throw Failure.unsupported("format \(format) / \(bits)-bit") }
        let frameCount = length / (bytesPer * channels)
        var out = [Float](repeating: 0, count: frameCount)
        data.withUnsafeBytes { raw in
            let base = raw.baseAddress!.advanced(by: start)
            for f in 0..<frameCount {
                var sum: Float = 0
                for c in 0..<channels {
                    let o = (f * channels + c) * bytesPer
                    switch (format, bits) {
                    case (1, 16): sum += Float(Int16(littleEndian: base.loadUnaligned(fromByteOffset: o, as: Int16.self))) / 32_768
                    case (1, 24):
                        let b0 = Int32(base.load(fromByteOffset: o, as: UInt8.self))
                        let b1 = Int32(base.load(fromByteOffset: o + 1, as: UInt8.self))
                        let b2 = Int32(Int8(bitPattern: base.load(fromByteOffset: o + 2, as: UInt8.self)))
                        sum += Float(b0 | b1 << 8 | b2 << 16) / 8_388_608
                    case (1, 32): sum += Float(Int32(littleEndian: base.loadUnaligned(fromByteOffset: o, as: Int32.self))) / 2_147_483_648
                    default: sum += base.loadUnaligned(fromByteOffset: o, as: Float.self)
                    }
                }
                out[f] = sum / Float(channels)
            }
        }
        return (out, Double(rate))
    }

    /// 16-bit mono WAV writer (tests and exporting trimmed samples).
    public static func encode16(_ frames: [Float], sampleRate: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + frames.count * 2)); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(UInt32(frames.count * 2))
        for f in frames { u16(UInt16(bitPattern: Int16(max(-1, min(1, f)) * 32_767))) }
        return d
    }
}
