import Foundation
import TonePilotCore

/// The platform-neutral half of the app, used by the Android app through a small C API
/// (`CAPI.swift`). It mirrors what the iOS `AppModel` does — library, tones, one-click analysis,
/// section switching, accompaniment — but exchanges plain JSON so the UI can be written in
/// Kotlin. Audio output, MIDI input and file decoding stay on the platform side.
///
/// Threading: `render` runs on the audio callback thread and only touches `ToneEngine`
/// (lock-free). MIDI arrives on a MIDI thread. Everything else is called from the UI thread or a
/// worker thread (analysis). `stateLock` guards the library and app state; `engineLock` guards the
/// router and engine controller so MIDI never races a tone change.
public final class AppCore: @unchecked Sendable {
    public let store: LibraryStore
    public let engine: ToneEngine
    let controller: ToneEngineController
    let cache: InstrumentCache
    let router = NoteRouter()
    private let stateLock = NSLock()
    private let engineLock = NSLock()
    private var parser = MIDIByteParser()

    private(set) var library = Library()
    private var activeArrangement: Arrangement?
    private var activeSongId: UUID?
    private var activeSectionId: UUID?
    private var pendingSuggestion: UUID?
    private var scheduler: SectionScheduler?
    private var performingSongId: UUID?
    private var lastPreloadedSection: UUID?
    private var songPosition: Double?
    private var backingPlaying = false
    private var practiceRate = 1.0
    private var analysisProgress: [UUID: Double] = [:]
    private var analysisStage: [UUID: String] = [:]
    private var analysisNotice: [UUID: String] = [:]
    private var cancelled: Set<UUID> = []
    private var patchErrors: [String] = []
    private var lastError: String?
    private var soundFontReady = false
    private var midiLog: [String] = []
    private var midiEventCount = 0
    private var prefs: [String: String] = [:]
    private var pcm: [String: (samples: [Float], rate: Double)] = [:]
    private var listen: ListenSession?
    private let saveQueue = DispatchQueue(label: "tonepilot.save")
    private var saveGeneration = 0

    private var prefsURL: URL { store.rootDirectory.appendingPathComponent("prefs.json") }

    public init(rootDirectory: URL, sampleRate: Double, maxFrames: Int = 4096) throws {
        store = try LibraryStore(rootDirectory: rootDirectory)
        engine = ToneEngine(sampleRate: sampleRate >= 22_050 ? sampleRate : 48_000, maxFrames: maxFrames)
        controller = ToneEngineController(engine: engine)
        cache = InstrumentCache(soundFontDirectory: store.soundFontDirectory, sampleDirectory: store.sampleDirectory)
        do { library = try store.load() } catch {
            lastError = "Library could not be loaded (\(error)). A new library was started; the old file was kept."
        }
        library.mergeFactoryPatches(FactoryPatches.all)
        if let data = try? Data(contentsOf: prefsURL),
           let p = try? JSONSerialization.jsonObject(with: data) as? [String: String] { prefs = p }
        let saved = prefs["lastToneId"].flatMap(UUID.init(uuidString:)).flatMap { tone(id: $0) }
        activeArrangement = saved ?? library.patch(id: FactoryPatches.id(forProgram: 0)).map(Arrangement.single)
        applyActiveArrangement()
        loadDefaultSoundFontInBackground()
    }

    // MARK: Audio & MIDI (hot paths)

    /// Audio thread. Renders `frames` stereo frames (any count; split into engine-sized blocks).
    public func render(frames: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        var done = 0
        while done < frames {
            let n = min(frames - done, engine.maxFrames)
            engine.render(frames: n, left: left + done, right: right + done)
            done += n
        }
    }

    /// MIDI thread. Raw MIDI 1.0 bytes from the keyboard.
    public func midi(_ bytes: [UInt8]) {
        engineLock.lock()
        let events = parser.parse(bytes)
        for e in events { controller.perform(router.handle(e)) }
        engineLock.unlock()
        guard !events.isEmpty else { return }
        stateLock.lock()
        midiEventCount += events.count
        midiLog.append(contentsOf: events.map(\.debugDescription))
        if midiLog.count > 40 { midiLog.removeFirst(midiLog.count - 40) }
        stateLock.unlock()
    }

    public func panic() {
        engineLock.lock()
        controller.perform(router.panic())
        engineLock.unlock()
    }

    func audition(note: UInt8, on: Bool) {
        let e: MIDIEvent = on ? .noteOn(channel: 1, note: note, velocity: 96) : .noteOff(channel: 1, note: note, velocity: 0)
        engineLock.lock()
        controller.perform(router.handle(e))
        engineLock.unlock()
    }

    // MARK: Sound fonts

    private func loadDefaultSoundFontInBackground() {
        let url = store.soundFontDirectory.appendingPathComponent(FactoryPatches.defaultSoundFontFile)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let bank = try SoundFontBank(url: url)
                self.stateLock.lock()
                self.cache.register(bank: bank, as: FactoryPatches.defaultSoundFontFile)
                self.soundFontReady = true
                self.stateLock.unlock()
                self.applyActiveArrangement()
            } catch {
                self.stateLock.lock()
                self.lastError = "The instrument sounds couldn't be loaded: \(error)"
                self.stateLock.unlock()
            }
        }
    }

    /// Call after copying a new .sf2 into `store.soundFontDirectory`.
    func reloadSoundFonts() { loadDefaultSoundFontInBackground() }

    // MARK: Tones

    func tone(id: UUID) -> Arrangement? {
        if let a = library.globalArrangements.first(where: { $0.id == id }) { return a }
        for song in library.songs { if let a = song.arrangements.first(where: { $0.id == id }) { return a } }
        return library.patches.map(Arrangement.single).first { $0.id == id }
    }

    private func applyActiveArrangement() {
        stateLock.lock()
        let arrangement = activeArrangement
        let patches = Dictionary(library.patches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        stateLock.unlock()
        engineLock.lock()
        controller.perform(router.setArrangement(arrangement))
        let errors = controller.apply(arrangement, patches: patches, cache: cache)
        engineLock.unlock()
        stateLock.lock()
        patchErrors = errors
        stateLock.unlock()
    }

    /// Caller holds no lock.
    private func activate(_ arrangement: Arrangement?, songId: UUID? = nil, sectionId: UUID? = nil) {
        stateLock.lock()
        if let id = arrangement?.id { prefs["lastToneId"] = id.uuidString; savePrefs() }
        activeArrangement = arrangement
        if let songId { activeSongId = songId }
        activeSectionId = sectionId
        if let sectionId { scheduler?.didSelect(sectionId) }
        if pendingSuggestion == sectionId { pendingSuggestion = nil }
        let song = activeSongId.flatMap { library.song(id: $0) }
        stateLock.unlock()
        applyActiveArrangement()
        if let song, song.accompaniment?.melodyGuide == true { configureAccompaniment(for: song) }
    }

    private func activateSection(_ sectionId: UUID, songId: UUID? = nil) {
        stateLock.lock()
        let song = (songId ?? activeSongId).flatMap { library.song(id: $0) }
        stateLock.unlock()
        guard let song, let section = song.sections.first(where: { $0.id == sectionId }) else { return }
        activate(song.arrangement(for: section), songId: song.id, sectionId: sectionId)
    }

    private func savePrefs() {
        if let data = try? JSONSerialization.data(withJSONObject: prefs) { try? data.write(to: prefsURL, options: .atomic) }
    }

    // MARK: Library

    /// Caller holds `stateLock`.
    private func save() {
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = library
        let store = self.store
        saveQueue.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let current = self.saveGeneration
            self.stateLock.unlock()
            guard current == generation else { return }
            do { try store.save(snapshot) } catch {
                self.stateLock.lock(); self.lastError = "Saving failed: \(error)"; self.stateLock.unlock()
            }
        }
    }

    /// Writes any pending change now (app going to the background).
    func flush() {
        stateLock.lock()
        let snapshot = library
        saveGeneration += 1
        stateLock.unlock()
        try? store.save(snapshot)
    }

    private func update(_ song: Song) {
        stateLock.lock()
        library.upsert(song)
        save()
        stateLock.unlock()
    }

    func song(_ id: UUID?) -> Song? {
        stateLock.lock(); defer { stateLock.unlock() }
        return id.flatMap { library.song(id: $0) }
    }

    func audioURL(for song: Song) -> URL? {
        guard song.sourceType == .importedFile, let name = song.sourceReference else { return nil }
        return store.audioDirectory.appendingPathComponent(name)
    }

    /// The platform has already copied the file into `store.audioDirectory` as `fileName`.
    func addImportedSong(fileName: String, originalName: String, duration: Double?) -> Song {
        let url = store.audioDirectory.appendingPathComponent(fileName)
        let tags = AudioFileTags.read(url: url)
        var song = Song(title: tags.displayTitle(filename: originalName), artist: tags.artist,
                        sourceType: .importedFile, sourceReference: fileName, userConfirmedRights: true, duration: duration)
        song.album = tags.album
        song.arrangements = [.starterFilmStack(name: "Main tone")]
        update(song)
        return song
    }

    func deleteSong(_ id: UUID) {
        guard let song = song(id) else { return }
        if song.sourceType == .importedFile, let file = song.sourceReference { try? store.deleteAudio(named: file) }
        try? store.deleteStems(for: id)
        stateLock.lock()
        cancelled.insert(id)
        library.deleteSong(id: id)
        let wasActive = activeSongId == id
        if wasActive { activeSongId = nil; scheduler = nil; performingSongId = nil }
        save()
        stateLock.unlock()
    }

    // MARK: Analysis

    func pcmBegin(key: String, sampleRate: Double) {
        stateLock.lock(); pcm[key] = ([], sampleRate); stateLock.unlock()
    }

    func pcmAppend(key: String, _ chunk: UnsafeBufferPointer<Float>) {
        stateLock.lock()
        pcm[key]?.samples.append(contentsOf: chunk)
        stateLock.unlock()
    }

    private func takePCM(_ key: String) -> TonePilotCore.AudioBuffer? {
        stateLock.lock()
        let entry = pcm.removeValue(forKey: key)
        stateLock.unlock()
        guard let entry, !entry.samples.isEmpty else { return nil }
        let target = AnalysisConfig().sampleRate
        return TonePilotCore.AudioBuffer(samples: Resampler.resample(entry.samples, from: entry.rate, to: target), sampleRate: target)
    }

    func markAnalysisStarted(_ songId: UUID, stage: String) {
        guard var song = song(songId) else { return }
        song.analysisStatus = .running
        song.analysisError = nil
        update(song)
        stateLock.lock()
        cancelled.remove(songId)
        analysisProgress[songId] = 0
        analysisStage[songId] = stage
        analysisNotice[songId] = nil
        stateLock.unlock()
    }

    func setStage(_ songId: UUID, _ stage: String, progress: Double) {
        stateLock.lock(); analysisStage[songId] = stage; analysisProgress[songId] = progress; stateLock.unlock()
    }

    func failAnalysis(_ songId: UUID, message: String) {
        guard var song = song(songId) else { return }
        song.analysisStatus = .failed
        song.analysisError = message
        stateLock.lock()
        analysisProgress[songId] = nil
        analysisStage[songId] = nil
        stateLock.unlock()
        update(song)
    }

    func cancelAnalysis(_ songId: UUID) {
        stateLock.lock(); cancelled.insert(songId); stateLock.unlock()
    }

    /// Blocking: run on a worker thread. Uses the PCM collected under `pcmKey`.
    func analyze(songId: UUID, pcmKey: String, listened: Bool = false) {
        guard let audio = takePCM(pcmKey) else {
            failAnalysis(songId, message: "The audio couldn't be read. Check that it plays, then try again.")
            return
        }
        analyze(songId: songId, audio: audio, listened: listened)
    }

    func analyze(songId: UUID, audio: TonePilotCore.AudioBuffer, listened: Bool) {
        setStage(songId, "Analysing tempo, key, chords, melody and sections…", progress: 0.05)
        stateLock.lock()
        let patches = library.patches
        let current = library.song(id: songId)
        stateLock.unlock()
        guard var input = current else { return }
        if listened, input.switching == nil { input.switching = SwitchingSettings(mode: .assisted, reference: .timer) }
        do {
            let output = try SongPipeline.run(song: input, audio: audio, patches: patches) { [weak self] p in
                guard let self else { return false }
                self.stateLock.lock(); defer { self.stateLock.unlock() }
                if self.cancelled.contains(songId) { return false }
                self.analysisProgress[songId] = 0.05 + 0.95 * p
                return true
            }
            stateLock.lock()
            let stillExists = library.song(id: songId) != nil
            analysisProgress[songId] = nil
            analysisStage[songId] = nil
            if listened {
                analysisNotice[songId] = "Analysed from the microphone — accuracy depends on volume and room noise. Listen again to re-analyse."
            }
            stateLock.unlock()
            guard stillExists else { return }
            update(output.song)
            stateLock.lock()
            let restart = performingSongId == songId
            stateLock.unlock()
            if restart { startPerformance(songId: songId) }
        } catch {
            let wasCancelled = (error as? SongAnalysisError) == .cancelled
            guard var s = song(songId) else { return }
            s.analysisStatus = wasCancelled ? .notStarted : .failed
            s.analysisError = Self.describe(error)
            stateLock.lock()
            analysisProgress[songId] = nil
            analysisStage[songId] = nil
            stateLock.unlock()
            update(s)
        }
    }

    static func describe(_ error: Error) -> String {
        switch error as? SongAnalysisError {
        case .tooShort: return "The audio is shorter than 8 seconds."
        case .silent: return "The audio appears to be silent."
        case .cancelled: return "Analysis was cancelled."
        case nil: return (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    // MARK: Listen Mode (microphone; audio kept in memory only)

    func listenBegin() {
        stateLock.lock(); listen = ListenSession(); stateLock.unlock()
    }

    /// Mono microphone samples at `sampleRate`; resampled to the analysis rate as they arrive.
    func listenAppend(_ chunk: UnsafeBufferPointer<Float>, sampleRate: Double) {
        let samples = Resampler.resample(Array(chunk), from: sampleRate, to: AnalysisConfig().sampleRate)
        stateLock.lock()
        listen?.append(samples)
        stateLock.unlock()
    }

    func listenStatus() -> [String: Any] {
        stateLock.lock(); defer { stateLock.unlock() }
        guard let l = listen else { return ["active": false] }
        return ["active": true, "elapsed": l.elapsed, "level": Double(l.currentLevel),
                "shouldStop": l.shouldAutoStop || l.isFull, "tooQuiet": l.isTooQuiet]
    }

    /// Stops listening and analyses what was heard (blocking). Returns the new song id.
    func listenFinish(title: String, link: String?) -> UUID? {
        stateLock.lock()
        let session = listen
        listen = nil
        stateLock.unlock()
        guard var session else { return nil }
        let audio = session.finish()
        var song = Song(title: title.isEmpty ? "Listened song" : title, sourceType: .listened, sourceReference: link,
                        userConfirmedRights: true, duration: audio.duration)
        song.arrangements = [.starterFilmStack(name: "Main tone")]
        song.switching = SwitchingSettings(mode: .assisted, reference: .timer)
        update(song)
        markAnalysisStarted(song.id, stage: "Analysing what TonePilot heard…")
        analyze(songId: song.id, audio: audio, listened: true)
        return song.id
    }

    func listenCancel() { stateLock.lock(); listen = nil; stateLock.unlock() }

    // MARK: Performance

    func startPerformance(songId: UUID) {
        guard let song = song(songId) else { return }
        stateLock.lock()
        activeSongId = songId
        performingSongId = songId
        scheduler = SectionScheduler(sections: song.sections, settings: song.switching ?? SwitchingSettings())
        lastPreloadedSection = nil
        stateLock.unlock()
        configureAccompaniment(for: song)
        if let first = song.orderedSections.first {
            activate(song.arrangement(for: first), songId: songId, sectionId: first.id)
        } else {
            activate(song.arrangements.first, songId: songId)
        }
    }

    func ensurePerformance(songId: UUID) {
        stateLock.lock()
        let running = performingSongId == songId
        stateLock.unlock()
        if !running { startPerformance(songId: songId) }
    }

    /// Called ~20×/s by the platform with the backing track position (nil when it isn't playing).
    func tick(backingTime: Double?, rate: Double) {
        stateLock.lock()
        let song = activeSongId.flatMap { library.song(id: $0) }
        backingPlaying = backingTime != nil
        practiceRate = rate
        stateLock.unlock()
        guard let song else { return }
        let reference = song.switching?.reference ?? .backingTrack
        var time: Double?
        switch reference {
        case .backingTrack:
            time = backingTime
            engineLock.lock()
            if let t = backingTime, rate == 1 {
                if !engine.isTransportPlaying || abs(engine.transportSeconds - t) > 0.06 { controller.setTransport(playing: true, seconds: t) }
            } else if engine.isTransportPlaying {
                controller.setTransport(playing: false, seconds: backingTime ?? 0)
            }
            engineLock.unlock()
        case .timer:
            if engine.isTransportPlaying { time = engine.transportSeconds }
        case .none:
            time = nil
        }
        stateLock.lock()
        songPosition = time
        guard let time, var s = scheduler else { stateLock.unlock(); return }
        let action = s.update(time: time)
        scheduler = s
        var preload: [InstrumentPatch] = []
        if let next = s.upcoming(after: time), next.id != lastPreloadedSection, let arr = song.arrangement(for: next) {
            lastPreloadedSection = next.id
            preload = arr.layers.compactMap { library.patch(id: $0.patchId) }
        }
        var switchTo: UUID?
        switch action {
        case .switchTo(let id)?: switchTo = id
        case .suggest(let id)?: if id != activeSectionId { pendingSuggestion = id }
        case nil: break
        }
        stateLock.unlock()
        if let switchTo { activateSection(switchTo) }
        if !preload.isEmpty {
            engineLock.lock(); _ = cache.preload(preload); engineLock.unlock()
        }
    }

    func confirmSuggestion() {
        stateLock.lock()
        let id = scheduler?.confirmSuggestion() ?? pendingSuggestion
        pendingSuggestion = nil
        stateLock.unlock()
        if let id { activateSection(id) }
    }

    func startTimerClock() {
        engineLock.lock(); controller.setTransport(playing: true, seconds: 0); engineLock.unlock()
    }

    func stopTimerClock() {
        engineLock.lock(); controller.setTransport(playing: false, seconds: 0); engineLock.unlock()
        stateLock.lock(); songPosition = nil; stateLock.unlock()
    }

    func configureAccompaniment(for song: Song) {
        let s = song.accompaniment ?? AccompanimentSettings()
        stateLock.lock()
        let lib = library
        let lead = activeArrangement?.layers.first { [.lead, .vocalMelody, .motif].contains($0.role) }?.patchId
        let arrangement = activeArrangement
        stateLock.unlock()
        func patch(_ id: UUID) -> InstrumentPatch? { lib.patch(id: id) }
        engineLock.lock()
        let c = controller
        var errors = [c.setAccompaniment(.bass, patch: s.bass ? patch(FactoryPatches.id(forProgram: 33)) : nil, volume: s.bassLevel, cache: cache),
                      c.setAccompaniment(.drums, patch: s.drums ? patch(FactoryPatches.drumKitId) : nil, volume: s.drumLevel, cache: cache),
                      c.setAccompaniment(.metronome, patch: s.metronome ? patch(FactoryPatches.clickId) : nil, volume: s.metronomeLevel, cache: cache)]
            .compactMap { $0 }
        let guideId = s.guidePatchId ?? lead ?? FactoryPatches.bansuriId
        if let e = c.setAccompaniment(.melodyGuide, patch: s.melodyGuide ? patch(guideId) : nil, volume: s.guideLevel, cache: cache) { errors.append(e) }
        let handles = AccompanimentGenerator.Handles(bass: c.accompanimentHandle(.bass), drums: c.accompanimentHandle(.drums),
                                                     guide: c.accompanimentHandle(.melodyGuide), metronome: c.accompanimentHandle(.metronome))
        let events = AccompanimentGenerator.events(beats: song.beatTimes, beatsPerBar: song.timeSignature?.value ?? 4,
                                                   chordGuide: song.chordGuide ?? [], melody: song.melody?.notes ?? [],
                                                   settings: s, handles: handles, sampleRate: engine.sampleRate,
                                                   transpose: song.performanceTranspose ?? 0)
        c.setSequence(events)
        c.setAccompanimentLevel(1, arrangement: arrangement)
        engineLock.unlock()
        if !errors.isEmpty { stateLock.lock(); patchErrors = errors; stateLock.unlock() }
    }

    /// Periodic housekeeping (every few seconds): frees unused instruments and sequence buffers.
    func maintenance() {
        engineLock.lock()
        for c in cache.maintenance(inUse: controller.instrumentsInUse) { engine.send(c) }
        controller.collectSequenceBuffers()
        engineLock.unlock()
    }

    // MARK: Edits

    func updateSong(_ id: UUID, _ change: (inout Song) -> Void) {
        guard var s = song(id) else { return }
        change(&s)
        update(s)
        stateLock.lock()
        let active = activeSongId == id
        if active, let sw = s.switching { scheduler?.settings = sw; if sw.effectiveMode != .assisted { pendingSuggestion = nil } }
        stateLock.unlock()
        if active { configureAccompaniment(for: s) }
    }

    func regenerateSection(songId: UUID, sectionId: UUID) {
        guard let song = song(songId) else { return }
        stateLock.lock(); let patches = library.patches; stateLock.unlock()
        let out = AutoArranger.arrange(song, patches: patches, onlySection: sectionId)
        update(out.song)
        if self.activeSectionIdValue == sectionId { activateSection(sectionId) }
    }

    func restoreAIOriginal(songId: UUID, sectionId: UUID) {
        updateSong(songId) { $0.restoreAIOriginal(for: sectionId) }
        if activeSectionIdValue == sectionId { activateSection(sectionId) }
    }

    private var activeSectionIdValue: UUID? { stateLock.lock(); defer { stateLock.unlock() }; return activeSectionId }

    /// Saves any tone as one of the user's own tones.
    func saveToMyTones(toneId: UUID, name: String?) -> Arrangement? {
        stateLock.lock(); defer { stateLock.unlock() }
        guard let t = tone(id: toneId) else { return nil }
        let copy = t.savedAsMyTone(name: name ?? t.name)
        library.globalArrangements.append(copy)
        save()
        return copy
    }

    /// Changes one layer of the tone that's playing. AI Originals and single instruments are
    /// copied first (into My Version / My Tones) so originals stay unchanged.
    func editActiveLayer(index: Int, volume: Double?, octave: Int?, muted: Bool?) {
        stateLock.lock()
        guard var a = activeArrangement, a.layers.indices.contains(index) else { stateLock.unlock(); return }
        let songId = activeSongId
        let inSong = songId.flatMap { library.song(id: $0) }?.arrangements.contains { $0.id == a.id } ?? false
        let isGlobal = library.globalArrangements.contains { $0.id == a.id }
        if a.origin == .aiOriginal || (!inSong && !isGlobal) {
            a = a.savedAsMyTone(name: a.name + " (edited)")
        }
        if let volume { a.layers[index].volume = max(0, min(1, volume)) }
        if let octave { a.layers[index].octave = max(-3, min(3, octave)) }
        if let muted { a.layers[index].muted = muted }
        a.updatedAt = Date()
        if inSong, a.origin != .aiOriginal, var song = songId.flatMap({ library.song(id: $0) }),
           let i = song.arrangements.firstIndex(where: { $0.id == a.id }) {
            song.arrangements[i] = a
            library.upsert(song)
        } else if let i = library.globalArrangements.firstIndex(where: { $0.id == a.id }) {
            library.globalArrangements[i] = a
        } else {
            library.globalArrangements.append(a)
        }
        activeArrangement = a
        prefs["lastToneId"] = a.id.uuidString
        savePrefs()
        save()
        stateLock.unlock()
        applyActiveArrangement()
    }

    // MARK: JSON views for the UI

    func stateJSON() -> [String: Any] {
        stateLock.lock(); defer { stateLock.unlock() }
        let a = activeArrangement
        var analyses: [String: Any] = [:]
        for (id, p) in analysisProgress { analyses[id.uuidString] = ["progress": p, "stage": analysisStage[id] ?? ""] }
        var d: [String: Any] = [
            "toneId": a?.id.uuidString ?? "", "toneName": a?.name ?? "No tone selected",
            "layers": (a?.layers ?? []).enumerated().map { i, l in
                ["index": i, "name": library.patch(id: l.patchId)?.name ?? "Missing sound", "volume": l.volume,
                 "octave": l.octave, "muted": l.muted, "role": l.role?.displayName ?? ""] as [String: Any]
            },
            "songId": activeSongId?.uuidString ?? "", "sectionId": activeSectionId?.uuidString ?? "",
            "pendingSuggestion": pendingSuggestion?.uuidString ?? "",
            "voices": engine.activeVoiceCount, "peak": Double(engine.meterPeak), "clipped": engine.limiterEngaged,
            "sampleRate": engine.sampleRate, "soundFontReady": soundFontReady,
            "analyses": analyses, "patchErrors": patchErrors, "error": lastError ?? "",
            "midiCount": midiEventCount, "midiLog": Array(midiLog.suffix(12).reversed()),
            "position": songPosition ?? -1, "transportPlaying": engine.isTransportPlaying,
        ]
        if let song = activeSongId.flatMap({ library.song(id: $0) }) {
            d["songTitle"] = song.title
            if let sec = song.sections.first(where: { $0.id == activeSectionId }) { d["sectionLabel"] = sec.label }
            if let p = pendingSuggestion, let sec = song.sections.first(where: { $0.id == p }) { d["pendingLabel"] = sec.label }
            let sw = song.switching ?? SwitchingSettings()
            d["switchMode"] = sw.mode.rawValue
            d["reference"] = sw.reference.rawValue
            d["hasAudio"] = audioURL(for: song) != nil
            d["accompaniment"] = Self.accompanimentJSON(song.accompaniment ?? AccompanimentSettings())
            d["transpose"] = song.performanceTranspose ?? 0
        }
        return d
    }

    static func accompanimentJSON(_ s: AccompanimentSettings) -> [String: Any] {
        ["bass": s.bass, "drums": s.drums, "metronome": s.metronome, "melodyGuide": s.melodyGuide,
         "backingTrack": s.backingTrack, "drumStyle": s.drumStyle.rawValue, "backingTrackLevel": s.backingTrackLevel]
    }

    func libraryJSON() -> [[String: Any]] {
        stateLock.lock(); defer { stateLock.unlock() }
        return library.songs.sorted { $0.createdAt > $1.createdAt }.map { s in
            var d: [String: Any] = ["id": s.id.uuidString, "title": s.title, "artist": s.artist ?? "",
                                    "status": s.analysisStatus.rawValue, "error": s.analysisError ?? "",
                                    "source": s.sourceType.rawValue, "favorite": s.isFavorite,
                                    "sections": s.sections.count, "duration": s.duration ?? 0]
            if let k = s.key { d["key"] = k.value.displayName }
            if let b = s.bpm { d["bpm"] = Int(b.value.rounded()) }
            if let p = analysisProgress[s.id] { d["progress"] = p; d["stage"] = analysisStage[s.id] ?? "" }
            return d
        }
    }

    func songJSON(_ id: UUID) -> [String: Any]? {
        stateLock.lock()
        guard let song = library.song(id: id) else { stateLock.unlock(); return nil }
        let lib = library
        let progress = analysisProgress[id], stage = analysisStage[id], notice = analysisNotice[id]
        let activeSection = activeSongId == id ? activeSectionId : nil
        stateLock.unlock()

        func estimate<T>(_ e: Estimate<T>?, _ text: (T) -> String) -> Any {
            guard let e else { return NSNull() }
            return ["text": text(e.value), "confidence": e.confidence, "user": e.provenance == .user] as [String: Any]
        }
        var d: [String: Any] = [
            "id": song.id.uuidString, "title": song.title,
            "subtitle": [song.artist, song.album ?? song.film, song.composer, song.language].compactMap { $0 }.joined(separator: " · "),
            "status": song.analysisStatus.rawValue, "error": song.analysisError ?? "", "source": song.sourceType.rawValue,
            "hasAudio": audioURL(for: song) != nil, "audioFile": song.sourceReference ?? "",
            "duration": song.duration ?? 0, "notice": notice ?? "",
            "bpm": estimate(song.bpm) { "\(Int($0.rounded())) BPM" },
            "bpmValue": song.bpm?.value ?? 0,
            "key": estimate(song.key) { $0.displayName },
            "meter": estimate(song.timeSignature) { $0 == 3 ? "3/4 or 6/8 (3-feel)" : "\($0)/4" },
            "meterValue": song.timeSignature?.value ?? 4,
            "melodySource": song.melody.map { $0.source == .vocalStem ? "Melody from vocals" : "Melody from mix" } ?? "",
            "limitations": SongAnalyzer.baseLimitations + ((song.stems ?? []).isEmpty ? [SongAnalyzer.noStemsLimitation] : []),
        ]
        if let progress { d["progress"] = progress; d["stage"] = stage ?? "" }
        var overview: [[String]] = []
        if let k = song.key {
            let scale = song.insights?.scaleNoteNames.joined(separator: " ") ?? ""
            overview.append(["Key", "\(k.value.displayName) · tonic \(NoteName.sharpNames[k.value.tonic])\(scale.isEmpty ? "" : " · notes used: \(scale)")"])
        }
        if let b = song.bpm { overview.append(["Tempo", "\(Int(b.value.rounded())) BPM"]) }
        if let t = song.timeSignature { overview.append(["Time", t.value == 3 ? "3/4 or 6/8 (3-feel)" : "\(t.value)/4"]) }
        if let feel = song.insights?.rhythmicFeel, !feel.isEmpty { overview.append(["Feel", feel]) }
        if let style = song.insights?.style, !style.isEmpty { overview.append(["Style", style.joined(separator: " · ")]) }
        if let m = song.insights?.rootMovement(from: 0, to: 30), !m.isEmpty { overview.append(["Bass (start)", m]) }
        d["overview"] = overview
        d["gaps"] = song.insights?.gaps ?? []
        d["sections"] = song.orderedSections.map { sec -> [String: Any] in
            let tone = song.arrangement(for: sec)
            return ["id": sec.id.uuidString, "label": sec.label, "type": sec.type.rawValue,
                    "start": sec.startTime, "end": sec.endTime, "climax": sec.isClimax == true,
                    "confidence": sec.confidence, "user": sec.provenance == .user,
                    "toneId": tone?.id.uuidString ?? "", "toneName": tone?.name ?? "",
                    "layers": tone?.layers.compactMap { lib.patch(id: $0.patchId)?.name }.joined(separator: " + ") ?? "",
                    "rationale": tone?.rationale ?? "",
                    "active": sec.id == activeSection,
                    "canRestore": tone?.origin == .myVersion]
        }
        return d
    }

    func sectionGuideJSON(songId: UUID, sectionId: UUID) -> [String: Any]? {
        stateLock.lock()
        let lib = library
        stateLock.unlock()
        guard let song = lib.song(id: songId), let section = song.sections.first(where: { $0.id == sectionId }) else { return nil }
        let ordered = song.orderedSections
        let index = ordered.firstIndex { $0.id == sectionId } ?? 0
        let g = KeyboardGuide.build(song: song, section: section, previous: index > 0 ? ordered[index - 1] : nil, library: lib)
        return [
            "label": section.label, "start": section.startTime, "end": section.endTime, "climax": section.isClimax == true,
            "changes": g.changes, "practiceSteps": g.practiceSteps, "toneAdvice": g.toneAdvice,
            "activity": (section.activity ?? []).map { ["role": $0.role.displayName, "level": $0.level, "evidence": $0.evidence] as [String: Any] },
            "leftHandPattern": g.leftHandPattern, "leftHandExample": g.leftHandExample, "chords": g.chords,
            "rootMovement": g.rootMovement, "melodyRange": g.melodyRange ?? "",
            "phrases": g.phrases.map { ["start": $0.start, "keys": $0.keys, "ornaments": $0.hasOrnaments] as [String: Any] },
            "voicings": g.voicings.map { ["chord": $0.chord, "notes": $0.notes, "inversion": $0.inversion] as [String: Any] },
            "instructions": g.instructions,
            "previousId": index > 0 ? ordered[index - 1].id.uuidString : "",
            "previousLabel": index > 0 ? ordered[index - 1].label : "",
            "nextId": index + 1 < ordered.count ? ordered[index + 1].id.uuidString : "",
            "nextLabel": index + 1 < ordered.count ? ordered[index + 1].label : "",
            "hasAudio": audioURL(for: song) != nil,
        ]
    }

    /// The live strip in Play: current chord as Root → Fifth → Root, next chord, next melody keys.
    func liveGuideJSON() -> [String: Any] {
        stateLock.lock()
        let song = activeSongId.flatMap { library.song(id: $0) }
        let t = songPosition
        let arrangement = activeArrangement
        stateLock.unlock()
        guard let song else { return ["available": false] }
        let transpose = song.performanceTranspose ?? 0
        let steps = song.chordGuide ?? []
        let time = t ?? 0
        func transposed(_ step: ChordGuideStep) -> ChordGuideStep {
            var s = step
            guard transpose != 0 else { return s }
            if let chord = ChordSymbol(step.chord) {
                s.chord = chord.transposed(transpose).name
                s.pattern = ChordGuide.pattern(root: chord.transposed(transpose).root)
            } else {
                s.pattern = step.pattern.map { $0 + transpose }
            }
            return s
        }
        var d: [String: Any] = ["available": true, "clock": t != nil]
        if let cur = ChordGuide.step(at: time, in: steps).map(transposed) {
            d["pattern"] = cur.patternText
            d["chord"] = cur.chord
            d["notes"] = cur.patternNoteNames
            d["drone"] = cur.isDrone
        }
        if let next = steps.first(where: { $0.time > time }).map(transposed) {
            d["nextChord"] = next.chord
            d["nextIn"] = max(0, next.time - time)
        }
        let offset = AutoArranger.guideOffset(for: arrangement) + transpose
        d["melody"] = (song.melody?.notes ?? []).filter { $0.end > time }.prefix(6).map {
            ["key": NoteName.name(for: $0.midi + offset), "ornament": $0.isOrnamented, "now": $0.start <= time] as [String: Any]
        }
        d["hasMelody"] = song.melody != nil
        d["tricky"] = song.melody?.difficultPhrases.contains { $0.contains(time) } ?? false
        return d
    }

    func toneListJSON(search: String) -> [String: Any] {
        stateLock.lock()
        let list = library.toneList(search: search)
        let active = activeArrangement?.id
        stateLock.unlock()
        func entry(_ e: Library.ToneList.Entry) -> [String: Any] {
            ["id": e.tone.id.uuidString, "name": e.tone.name, "subtitle": e.subtitle, "active": e.tone.id == active]
        }
        var groups: [[String: Any]] = []
        if !list.songTones.isEmpty { groups.append(["title": "Song tones (made by TonePilot)", "kind": "song", "entries": list.songTones.map(entry)]) }
        groups.append(["title": "My tones", "kind": "mine", "entries": list.myTones.map(entry)])
        for g in list.instruments { groups.append(["title": g.family.displayName, "kind": "instrument", "entries": g.entries.map(entry)]) }
        return ["groups": groups]
    }

    // MARK: Commands (JSON in, JSON out)

    /// One entry point for the UI: `{"cmd": "...", ...}` → JSON result.
    public func call(_ request: String) -> String {
        guard let data = request.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cmd = obj["cmd"] as? String else { return Self.json(["error": "bad request"]) }
        func id(_ key: String) -> UUID? { (obj[key] as? String).flatMap(UUID.init(uuidString:)) }
        func str(_ key: String) -> String? { obj[key] as? String }
        func num(_ key: String) -> Double? { (obj[key] as? NSNumber)?.doubleValue }
        func bool(_ key: String) -> Bool? { (obj[key] as? NSNumber)?.boolValue }
        let ok: [String: Any] = ["ok": true]

        switch cmd {
        case "state": return Self.json(stateJSON())
        case "library": return Self.json(["songs": libraryJSON()])
        case "song": return Self.json(id("id").flatMap(songJSON) ?? ["error": "Song not found"])
        case "sectionGuide":
            guard let s = id("songId"), let sec = id("sectionId") else { return Self.json(["error": "missing id"]) }
            return Self.json(sectionGuideJSON(songId: s, sectionId: sec) ?? ["error": "Section not found"])
        case "liveGuide": return Self.json(liveGuideJSON())
        case "tones": return Self.json(toneListJSON(search: str("search") ?? ""))
        case "activateTone":
            guard let t = id("id").flatMap({ tid in stateLock.lock(); defer { stateLock.unlock() }; return tone(id: tid) }) else { return Self.json(["error": "Tone not found"]) }
            activate(t, sectionId: nil)
            return Self.json(ok)
        case "activateSection":
            guard let sec = id("sectionId") else { return Self.json(["error": "missing id"]) }
            if let s = id("songId") { ensurePerformance(songId: s) }
            activateSection(sec, songId: id("songId"))
            return Self.json(ok)
        case "panic": panic(); return Self.json(ok)
        case "audition":
            audition(note: UInt8(max(0, min(127, num("note") ?? 60))), on: bool("on") ?? false)
            return Self.json(ok)
        case "saveToMyTones":
            guard let t = id("id"), let a = saveToMyTones(toneId: t, name: str("name")) else { return Self.json(["error": "Tone not found"]) }
            return Self.json(["ok": true, "name": a.name])
        case "editLayer":
            editActiveLayer(index: Int(num("index") ?? -1), volume: num("volume"), octave: num("octave").map { Int($0) }, muted: bool("muted"))
            return Self.json(ok)
        case "importSong":
            guard let file = str("fileName") else { return Self.json(["error": "missing file"]) }
            let s = addImportedSong(fileName: file, originalName: str("originalName") ?? file, duration: num("duration"))
            markAnalysisStarted(s.id, stage: "Decoding audio…")
            return Self.json(["id": s.id.uuidString])
        case "analysisStarted":
            if let s = id("id") { markAnalysisStarted(s, stage: str("stage") ?? "Decoding audio…") }
            return Self.json(ok)
        case "analysisFailed":
            if let s = id("id") { failAnalysis(s, message: str("message") ?? "The audio couldn't be read.") }
            return Self.json(ok)
        case "pcmBegin":
            pcmBegin(key: str("key") ?? "", sampleRate: num("sampleRate") ?? 44_100)
            return Self.json(ok)
        case "analyze":
            guard let s = id("id") else { return Self.json(["error": "missing id"]) }
            analyze(songId: s, pcmKey: str("key") ?? s.uuidString)
            return Self.json(ok)
        case "cancelAnalysis": if let s = id("id") { cancelAnalysis(s) }; return Self.json(ok)
        case "deleteSong": if let s = id("id") { deleteSong(s) }; return Self.json(ok)
        case "listenBegin": listenBegin(); return Self.json(ok)
        case "listenStatus": return Self.json(listenStatus())
        case "listenCancel": listenCancel(); return Self.json(ok)
        case "listenFinish":
            let sid = listenFinish(title: str("title") ?? "", link: str("link"))
            return Self.json(sid.map { ["id": $0.uuidString] } ?? ["error": "Nothing was recorded."])
        case "startPerformance":
            if let s = id("id") { startPerformance(songId: s) }
            return Self.json(ok)
        case "ensurePerformance":
            if let s = id("id") { ensurePerformance(songId: s) }
            return Self.json(ok)
        case "tick":
            let t = num("time") ?? -1
            tick(backingTime: t >= 0 ? t : nil, rate: num("rate") ?? 1)
            return Self.json(ok)
        case "confirmSuggestion": confirmSuggestion(); return Self.json(ok)
        case "startClock": startTimerClock(); return Self.json(ok)
        case "stopClock": stopTimerClock(); return Self.json(ok)
        case "setSwitching":
            guard let s = id("songId") else { return Self.json(["error": "missing id"]) }
            updateSong(s) { song in
                var sw = song.switching ?? SwitchingSettings()
                if let m = str("mode").flatMap(SwitchingSettings.Mode.init(rawValue:)) { sw.mode = m }
                if let r = str("reference").flatMap(SwitchingSettings.TimingReference.init(rawValue:)) { sw.reference = r }
                song.switching = sw
            }
            return Self.json(ok)
        case "setAccompaniment":
            guard let s = id("songId") else { return Self.json(["error": "missing id"]) }
            updateSong(s) { song in
                var a = song.accompaniment ?? AccompanimentSettings()
                if let v = bool("bass") { a.bass = v }
                if let v = bool("drums") { a.drums = v }
                if let v = bool("metronome") { a.metronome = v }
                if let v = bool("melodyGuide") { a.melodyGuide = v }
                if let v = bool("backingTrack") { a.backingTrack = v }
                if let v = str("drumStyle").flatMap(AccompanimentSettings.DrumStyle.init(rawValue:)) { a.drumStyle = v }
                song.accompaniment = a
            }
            return Self.json(ok)
        case "setTranspose":
            guard let s = id("songId") else { return Self.json(["error": "missing id"]) }
            updateSong(s) { $0.performanceTranspose = max(-12, min(12, Int(num("value") ?? 0))) }
            return Self.json(ok)
        case "setBPM":
            guard let s = id("songId"), let v = num("value"), v > 20, v < 400 else { return Self.json(["error": "bad tempo"]) }
            updateSong(s) { $0.bpm = .user((v * 10).rounded() / 10) }
            return Self.json(ok)
        case "setKey":
            guard let s = id("songId"), let tonic = num("tonic") else { return Self.json(["error": "bad key"]) }
            let k = MusicalKey(tonic: Int(tonic) % 12, mode: str("mode") == "minor" ? .minor : .major)
            updateSong(s) { $0.key = .user(k) }
            return Self.json(ok)
        case "setMeter":
            guard let s = id("songId"), let v = num("value") else { return Self.json(["error": "bad meter"]) }
            updateSong(s) { $0.timeSignature = .user(Int(v) == 3 ? 3 : 4) }
            return Self.json(ok)
        case "regenerateSection":
            if let s = id("songId"), let sec = id("sectionId") { regenerateSection(songId: s, sectionId: sec) }
            return Self.json(ok)
        case "restoreAIOriginal":
            if let s = id("songId"), let sec = id("sectionId") { restoreAIOriginal(songId: s, sectionId: sec) }
            return Self.json(ok)
        case "reloadSoundFonts": reloadSoundFonts(); return Self.json(ok)
        case "maintenance": maintenance(); return Self.json(ok)
        case "flush": flush(); return Self.json(ok)
        case "clearError": stateLock.lock(); lastError = nil; stateLock.unlock(); return Self.json(ok)
        case "paths":
            return Self.json(["root": store.rootDirectory.path, "audio": store.audioDirectory.path,
                              "soundFonts": store.soundFontDirectory.path])
        default:
            return Self.json(["error": "unknown command \(cmd)"])
        }
    }

    static func json(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let s = String(data: data, encoding: .utf8) else { return "{\"error\":\"encoding failed\"}" }
        return s
    }
}

/// Converts a mono signal to another sample rate: a 2-pole low-pass below the new Nyquist
/// (when downsampling) followed by linear interpolation. Good enough for analysis.
public enum Resampler {
    public static func resample(_ input: [Float], from source: Double, to target: Double) -> [Float] {
        guard source > 0, target > 0, !input.isEmpty else { return [] }
        if abs(source - target) < 0.5 { return input }
        var x = input
        if target < source {
            // Two cascaded one-pole/zero sections ≈ gentle anti-alias filter at 0.45 × target.
            let fc = 0.45 * target
            let k = Float(exp(-2 * Double.pi * fc / source))
            for _ in 0..<2 {
                var y: Float = 0
                for i in x.indices { y = (1 - k) * x[i] + k * y; x[i] = y }
            }
        }
        let ratio = source / target
        let count = Int(Double(x.count) / ratio)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let pos = Double(i) * ratio
            let j = Int(pos)
            let f = Float(pos - Double(j))
            let a = x[min(j, x.count - 1)], b = x[min(j + 1, x.count - 1)]
            out[i] = a + (b - a) * f
        }
        return out
    }
}
