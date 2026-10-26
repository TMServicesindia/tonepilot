import AVFoundation
import os
import QuartzCore
import SwiftUI
import TonePilotCore

/// Bottom tabs. Playing, mixing and song-specific tone editing all live in the Song Studio.
enum AppTab: Hashable {
    case library, analyse, studio, settings
}

enum EngineKind: String, CaseIterable, Identifiable {
    /// TonePilot's own engine: full layer controls, accompaniment, melody guide.
    case tonePilot
    /// Apple's AVAudioUnitSampler — fallback with fewer controls.
    case appleSampler
    var id: String { rawValue }
    var displayName: String { self == .tonePilot ? "TonePilot engine (recommended)" : "Apple sampler (legacy)" }
}

/// Lets the CoreMIDI thread reach the current output while the main thread may swap engines.
final class OutputBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: ToneOutput
    init(_ v: ToneOutput) { _value = v }
    var value: ToneOutput {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

/// App-wide state. Owns the library, the sound engine, MIDI input and the note router,
/// and is the only place that mutates the library (then saves it, debounced).
@MainActor
final class AppModel: ObservableObject {
    @Published var library = Library()
    @Published var activeSongId: UUID?
    /// Root tab selection (see `AppTab`).
    @Published var selectedTab = AppTab.library
    // Song Studio
    /// Where playback resumes when you press Play (seconds).
    @Published var cursor: Double = 0
    /// The section being looped for practice, if any.
    @Published var loopSectionId: UUID?
    /// Practice speed (1 = normal; pitch is kept).
    @Published var studioRate: Float = 1
    /// Waveform peaks per song (computed once per session).
    @Published var waveforms: [UUID: [Float]] = [:]
    /// A tone being auditioned from the tone picker (not yet assigned to a section).
    @Published var previewingToneId: UUID?
    /// Song Arpeggio preview running on the engine's own pattern clock (independent of the song).
    @Published var arpeggioPreview: ArpeggioPreview?
    /// Song Arpeggio live fill-in: the chord TonePilot heard in your last bar.
    @Published var arpeggioLiveChord: String?
    /// Section whose pattern live fill-in uses while the song is paused.
    @Published var arpeggioSectionId: UUID?
    var arpeggioFollower: ArpeggioFollower?
    var arpeggioFollowerSection: UUID?
    /// Read on the MIDI thread: forward chord-hand notes to live fill-in.
    let arpeggioLiveFlag = OSAllocatedUnfairLock(initialState: false)
    // Stem separation (on this iPhone)
    @Published var separationProgress: [UUID: Double] = [:]
    @Published var separationError: [UUID: String] = [:]
    /// Splitting the Music part into Lead instruments and Backing (0...1 while running).
    @Published var musicSplitProgress: [UUID: Double] = [:]
    var separationStart: [UUID: Date] = [:]
    let separationCancels = CancelFlags()
    /// Section under the playhead last time the section-gated parts were applied.
    var lastGateSection: UUID?
    /// What each accompaniment slot was last set to (skip redundant engine updates).
    var accompanimentSlotState: [String: String] = [:]
    /// Separate parts automatically after the first analysis of an imported song.
    @Published var autoSeparate: Bool = UserDefaults.standard.object(forKey: "autoSeparate") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoSeparate, forKey: "autoSeparate") }
    }
    @Published var activeArrangement: Arrangement?
    @Published var activeSectionId: UUID?
    /// High-frequency values (position, meter) for the few views that show them.
    let live = LiveState()
    @Published var engineError: String?
    @Published var patchLoadErrors: [String] = []
    @Published var analysisProgress: [UUID: Double] = [:]
    @Published var analysisStage: [UUID: String] = [:]
    @Published var analysisNotice: [UUID: String] = [:]
    @Published var isSectionPlaying = false
    /// Song position from the active timing reference (backing track or timer), for the UI.
    var songPosition: Double? {
        didSet { live.setPosition(songPosition) }
    }
    /// Assisted switching: the section waiting for confirmation.
    @Published var pendingSuggestion: UUID?
    @Published var velocityCurve: VelocityCurve = .linear {
        didSet { router.velocityCurve = velocityCurve }
    }
    @Published private(set) var engineKind: EngineKind
    @Published var serverSettings: AnalysisServerSettings {
        didSet { if let d = try? JSONEncoder().encode(serverSettings) { UserDefaults.standard.set(d, forKey: "serverSettings") } }
    }

    let store: LibraryStore
    let midi = MIDIInputManager()
    let router = NoteRouter()
    let cache: InstrumentCache
    private let outputBox: OutputBox
    private(set) var sectionPlayer: SectionPlayer
    private var scheduler: SectionScheduler?
    private var performanceTimer: Timer?
    private var maintenanceTimer: Timer?
    private var lastPreloadedSection: UUID?
    private var performingSongId: UUID?
    private var saveTask: Task<Void, Never>?
    private var analysisTasks: [UUID: Task<Void, Never>] = [:]

    var output: ToneOutput { outputBox.value }
    var host: ToneEngineHost? { output as? ToneEngineHost }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("TonePilot", isDirectory: true)
        // Directory creation only fails if the disk is full or sandbox is broken; surface it but continue.
        let store = (try? LibraryStore(rootDirectory: root)) ?? (try! LibraryStore(rootDirectory: FileManager.default.temporaryDirectory))
        self.store = store
        cache = InstrumentCache(soundFontDirectory: store.soundFontDirectory, sampleDirectory: store.sampleDirectory)
        cache.sampleDecoder = { try AudioFileDecoder.decodeMonoNative(url: $0) }
        let kind = EngineKind(rawValue: UserDefaults.standard.string(forKey: "engineKind") ?? "") ?? .tonePilot
        engineKind = kind
        let out: ToneOutput = kind == .tonePilot ? ToneEngineHost() : SoundEngine(soundFontDirectory: store.soundFontDirectory)
        outputBox = OutputBox(out)
        sectionPlayer = SectionPlayer(player: out.songPlayerNode, engine: out.avEngine)
        serverSettings = (UserDefaults.standard.data(forKey: "serverSettings")).flatMap { try? JSONDecoder().decode(AnalysisServerSettings.self, from: $0) } ?? AnalysisServerSettings()

        do {
            library = try store.load()
        } catch {
            engineError = "Library could not be loaded (\(error)). A new library was started; the old file was kept."
        }
        library.mergeFactoryPatches(FactoryPatches.all)
        wireMeter()
        restoreLastTone()
        // Audio, MIDI and the sound bank start right after the first frame is on screen, so the
        // app opens immediately (they take a few hundred ms, and the first launch copies 30 MB).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.observeAudioSession()
            self.startEngine()
            self.wireMIDI()
            self.installBundledSoundFontsThenPreload()
        }
        maintenanceTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.maintenance() }
        }
    }

    // MARK: Setup

    /// Copies the bundled sound banks into the library (first launch only) off the main thread,
    /// then preloads the default bank.
    private func installBundledSoundFontsThenPreload() {
        let bundled = Bundle.main.urls(forResourcesWithExtension: "sf2", subdirectory: "SoundFonts") ?? []
        let directory = store.soundFontDirectory
        Task.detached(priority: .userInitiated) { [weak self] in
            for url in bundled {
                let dest = directory.appendingPathComponent(url.lastPathComponent)
                if !FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.copyItem(at: url, to: dest) }
            }
            await MainActor.run { self?.preloadDefaultSoundFont() }
        }
    }

    /// Parses the 30 MB General MIDI bank off the main thread so the first tone loads instantly.
    private func preloadDefaultSoundFont() {
        let url = store.soundFontDirectory.appendingPathComponent(FactoryPatches.defaultSoundFontFile)
        guard engineKind == .tonePilot, FileManager.default.fileExists(atPath: url.path) else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let bank = try? SoundFontBank(url: url) else { return }
            await MainActor.run {
                self?.cache.register(bank: bank, as: FactoryPatches.defaultSoundFontFile)
                self?.applyActiveArrangement()
            }
        }
    }

    var installedSoundFonts: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: store.soundFontDirectory.path))?
            .filter { ["sf2", "dls"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted() ?? []
    }

    var defaultSoundFontInstalled: Bool { installedSoundFonts.contains(FactoryPatches.defaultSoundFontFile) }

    private func wireMIDI() {
        let router = self.router
        let box = outputBox
        let liveFlag = arpeggioLiveFlag
        midi.onEvents = { [weak self] events in
            // CoreMIDI thread: route and play immediately, nothing else.
            let out = box.value
            for e in events { out.perform(router.handle(e)) }
            // Song Arpeggio live fill-in: hand note-ons (with their arrival time) to the main thread.
            guard liveFlag.withLock({ $0 }) else { return }
            let now = CACurrentMediaTime()
            for case let .noteOn(_, note, velocity) in events where velocity > 0 {
                DispatchQueue.main.async { self?.arpeggioNote(Int(note), at: now) }
            }
        }
        midi.onSourcesChanged = { [weak self] removed in
            // A cable pulled mid-note never sends note-off: release everything.
            if removed { self?.panic() }
        }
        midi.start()
    }

    private func wireMeter() {
        output.onMeter = { [weak self] peak, clipped in
            self?.live.setPeak(peak, clipped: clipped)
        }
    }

    private func startEngine() {
        do {
            try output.start()
            engineError = nil
            applyActiveArrangement()
        } catch {
            engineError = "Audio engine failed to start: \(error.localizedDescription)"
        }
    }

    /// Switches sound engine live (stops held notes first).
    func setEngine(_ kind: EngineKind) {
        guard kind != engineKind else { return }
        accompanimentSlotState = [:]
        panic()
        sectionPlayer.stop()
        output.stop()
        let new: ToneOutput = kind == .tonePilot ? ToneEngineHost() : SoundEngine(soundFontDirectory: store.soundFontDirectory)
        outputBox.value = new
        sectionPlayer = SectionPlayer(player: new.songPlayerNode, engine: new.avEngine)
        engineKind = kind
        UserDefaults.standard.set(kind.rawValue, forKey: "engineKind")
        wireMeter()
        observeEngineConfiguration()
        startEngine()
        if let song = song(activeSongId) { configureAccompaniment(for: song) }
    }

    private var configObserver: NSObjectProtocol?

    private func observeEngineConfiguration() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: output.avEngine, queue: .main) { [weak self] _ in
            // A route or sample-rate change stops the engine; restart it.
            Task { @MainActor in self?.startEngine() }
        }
    }

    private func observeAudioSession() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                if type == .began { self?.panic(); self?.stopBackingTrack() } else { self?.startEngine() }
            }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        observeEngineConfiguration()
    }

    private func maintenance() {
        guard let host else { return }
        for c in cache.maintenance(inUse: host.controller.instrumentsInUse) { host.core.send(c) }
        host.controller.collectSequenceBuffers()
    }

    // MARK: Performance

    func panic() {
        output.perform(router.panic())
    }

    func resetClip() { live.clipped = false }

    /// Finds any tone by id: song tones, My Tones, or a single-instrument tone.
    func tone(id: UUID) -> Arrangement? {
        if let a = library.globalArrangements.first(where: { $0.id == id }) { return a }
        for song in library.songs { if let a = song.arrangements.first(where: { $0.id == id }) { return a } }
        return library.patches.map(Arrangement.single).first { $0.id == id }
    }

    /// The keyboard is never silent on launch: last-used tone, else Grand Piano.
    private func restoreLastTone() {
        let saved = UserDefaults.standard.string(forKey: "lastToneId").flatMap(UUID.init(uuidString:)).flatMap { tone(id: $0) }
        let piano = library.patch(id: FactoryPatches.id(forProgram: 0)).map(Arrangement.single)
        activeArrangement = saved ?? piano
    }

    /// Makes `arrangement` the sound you hear when playing the Casio.
    func activate(_ arrangement: Arrangement?, songId: UUID? = nil, sectionId: UUID? = nil) {
        if let id = arrangement?.id { UserDefaults.standard.set(id.uuidString, forKey: "lastToneId") }
        activeArrangement = arrangement
        if let songId { activeSongId = songId }
        activeSectionId = sectionId
        if let sectionId { scheduler?.didSelect(sectionId) }
        if pendingSuggestion == sectionId { pendingSuggestion = nil }
        applyActiveArrangement()
        // Song Arpeggio fills in your tone: follow tone changes.
        if arpeggioFollower != nil { refreshArpeggioLive() }
        // The AI melody plays with the section's lead sound unless another one was chosen.
        if let song = song(activeSongId), song.accompaniment?.melodyGuide == true, song.accompaniment?.guidePatchId == nil {
            applyMix(song)
        }
    }

    func activateSection(_ sectionId: UUID) {
        guard let song = song(activeSongId), let section = song.sections.first(where: { $0.id == sectionId }) else { return }
        activate(song.arrangement(for: section), songId: song.id, sectionId: sectionId)
    }

    func applyActiveArrangement() {
        let patches = Dictionary(library.patches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        output.perform(router.setArrangement(activeArrangement))
        if let host {
            patchLoadErrors = host.controller.apply(activeArrangement, patches: patches, cache: cache)
        } else if let legacy = output as? SoundEngine {
            legacy.apply(activeArrangement, patches: patches) { [weak self] failures in self?.patchLoadErrors = failures }
        }
    }

    /// Plays a note from the on-screen audition strip through the exact same path as the Casio.
    func audition(note: UInt8, on: Bool) {
        let event: MIDIEvent = on ? .noteOn(channel: 1, note: note, velocity: 96) : .noteOff(channel: 1, note: note, velocity: 0)
        output.perform(router.handle(event))
    }

    /// Opens a song for playing: first section's tone, scheduler and accompaniment ready.
    func startPerformance(songId: UUID) {
        guard let song = song(songId) else { return }
        activeSongId = songId
        performingSongId = songId
        scheduler = SectionScheduler(sections: song.sections, settings: song.switching ?? SwitchingSettings())
        lastPreloadedSection = nil
        configureAccompaniment(for: song)
        if isUsingMainTone(song), !song.sections.isEmpty {
            // The song's saved choice: one main tone for the whole song.
            useMainTone(songId)
        } else if let first = song.orderedSections.first {
            activate(song.arrangement(for: first), songId: songId, sectionId: first.id)
        } else {
            activate(song.arrangements.first, songId: songId)
        }
        try? loadSongAudio(song)
        performanceTimer?.invalidate()
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// Starts a performance session for the song unless it is already running (keeps the current section).
    func ensurePerformance(songId: UUID) {
        if performingSongId != songId || performanceTimer == nil { startPerformance(songId: songId) }
    }

    func updateSwitching(_ settings: SwitchingSettings) {
        guard var song = song(activeSongId) else { return }
        song.switching = settings
        update(song)
        scheduler?.settings = settings
        if settings.effectiveMode != .assisted { pendingSuggestion = nil }
    }

    func confirmSuggestion() {
        guard let id = scheduler?.confirmSuggestion() ?? pendingSuggestion else { return }
        pendingSuggestion = nil
        activateSection(id)
    }

    /// Plays the imported song from `time` as backing/clock. The engine's sequencer follows it.
    func playBackingTrack(from time: Double, to end: Double? = nil, loop: Bool = false, rate: Float = 1) {
        guard let song = song(activeSongId), audioURL(for: song) != nil else { return }
        do { try loadSongAudio(song) } catch { engineError = "Playback failed: \(error.localizedDescription)"; return }
        // Audio tracks that are switched off keep running silently as the timing reference.
        applyAudioLevels(song)
        sectionPlayer.rate = rate
        sectionPlayer.play(from: time, to: end, loop: loop)
        isSectionPlaying = true
        if sectionPlayer.rate == 1 { host?.controller.setTransport(playing: true, seconds: time) }
    }

    func stopBackingTrack() {
        sectionPlayer.stop()
        isSectionPlaying = false
        if song(activeSongId)?.switching?.reference != .timer { host?.controller.setTransport(playing: false, seconds: songPosition ?? 0) }
    }

    /// Timer reference: starts the internal song clock (tap on the song's first beat).
    func startTimerClock(at seconds: Double = 0) {
        host?.controller.setTransport(playing: true, seconds: seconds)
    }

    func stopTimerClock() {
        host?.controller.setTransport(playing: false, seconds: 0)
        songPosition = nil
    }

    private func tick() {
        guard let song = song(activeSongId) else { return }
        let reference = song.switching?.reference ?? .backingTrack
        var time: Double?
        switch reference {
        case .backingTrack:
            time = sectionPlayer.currentTime
            if !sectionPlayer.isPlaying, isSectionPlaying { isSectionPlaying = false }
            // Keep the accompaniment clock locked to the backing track.
            if let t = time, let host, sectionPlayer.rate == 1, !host.core.isTransportPlaying || abs(host.core.transportSeconds - t) > 0.06 {
                host.controller.setTransport(playing: true, seconds: t)
            }
        case .timer:
            if let host, host.core.isTransportPlaying { time = host.core.transportSeconds }
        case .none:
            time = nil
        }
        songPosition = time
        // Parts that play only in chosen sections ("AI plays difficult parts" from the recording).
        if let t = time ?? (isSectionPlaying ? nil : cursor) {
            let current = song.orderedSections.last { $0.startTime <= t + 0.02 }?.id
            if current != lastGateSection { lastGateSection = current; applyAudioLevels(song) }
        }
        guard let time, var s = scheduler else { return }
        let action = s.update(time: time)
        scheduler = s
        switch action {
        case .switchTo(let id)?: activateSection(id)
        case .suggest(let id)?: if id != activeSectionId { pendingSuggestion = id }
        case nil: break
        }
        // Preload the next section's instruments well before its boundary.
        if let next = s.upcoming(after: time), next.id != lastPreloadedSection, let arr = song.arrangement(for: next) {
            lastPreloadedSection = next.id
            cache.preload(arr.layers.compactMap { library.patch(id: $0.patchId) })
        }
    }

    // MARK: Accompaniment & melody guide

    /// Configures the generated parts (bass, rhythm, background chords, AI melody, metronome)
    /// and their event list for `song`. Every part the song can play is sequenced once; switching
    /// a part on/off or changing its level only touches its engine slot, so the song never stops.
    func configureAccompaniment(for song: Song) {
        guard let host else { return }
        let s = song.accompaniment ?? AccompanimentSettings()
        let c = host.controller
        let handles = AccompanimentGenerator.Handles(bass: c.accompanimentHandle(.bass), drums: c.accompanimentHandle(.drums),
                                                     guide: c.accompanimentHandle(.melodyGuide), metronome: c.accompanimentHandle(.metronome),
                                                     chords: c.accompanimentHandle(.chords))
        // The Song Studio plays the recording's own parts; generated parts (rhythm, bass, chords,
        // melody) are only sequenced when a song has them switched on from before.
        let generated = SongStudio.generatedPartsOn(s)
        let events = generated ? AccompanimentGenerator.events(beats: song.beatTimes, beatsPerBar: song.timeSignature?.value ?? 4,
                                                   chordGuide: song.chordGuide ?? [], melody: song.melody?.notes ?? [],
                                                   settings: s, handles: handles,
                                                   sampleRate: host.core.sampleRate, transpose: song.performanceTranspose ?? 0,
                                                   guideRanges: SongStudio.guideRanges(song)) : []
        c.setSequence(events)
        applyMix(song)
    }

    /// Applies on/off, solo and levels to every track without re-sequencing.
    func applyMix(_ song: Song) {
        applyAudioLevels(song)
        guard let host else { return }
        let s = song.accompaniment ?? AccompanimentSettings()
        let c = host.controller
        func patch(_ id: UUID) -> InstrumentPatch? { library.patch(id: id) }
        func slot(_ slot: ToneEngine.AccompanimentSlot, _ track: String, _ patchId: UUID) -> String? {
            let level = SongStudio.effectiveLevel(track, s)
            // Unchanged slots are left alone (re-sending them costs main-thread time).
            let key = "\(slot.rawValue)"
            let state = level > 0 ? "\(patchId)@\(level)" : "off"
            guard accompanimentSlotState[key] != state else { return nil }
            accompanimentSlotState[key] = state
            return c.setAccompaniment(slot, patch: level > 0 ? patch(patchId) : nil, volume: level, cache: cache)
        }
        let leadId = activeArrangement?.layers.first { [.lead, .vocalMelody, .motif].contains($0.role) }?.patchId
        let chordPatch: UUID
        switch s.chordStyle ?? .pad {
        case .pad: chordPatch = FactoryPatches.warmAnalogPadId
        case .strings: chordPatch = FactoryPatches.id(forProgram: 49)
        case .piano: chordPatch = FactoryPatches.id(forProgram: 0)
        }
        let errors = [slot(.bass, SongStudio.bass, FactoryPatches.id(forProgram: 33)),
                      slot(.drums, SongStudio.drums, FactoryPatches.drumKitId),
                      slot(.metronome, SongStudio.metronome, FactoryPatches.clickId),
                      slot(.chords, SongStudio.chords, chordPatch),
                      slot(.melodyGuide, SongStudio.melody, s.guidePatchId ?? leadId ?? FactoryPatches.bansuriId)].compactMap { $0 }
        c.setMixLevels(live: SongStudio.effectiveLevel(SongStudio.keyboard, s), accompaniment: 1, arrangement: activeArrangement)
        if !errors.isEmpty { patchLoadErrors = errors }
    }

    /// The song's audio tracks: separated stems when they're on this iPhone, else the recording.
    func audioTracks(for song: Song) -> [(id: String, url: URL)] {
        guard let main = audioURL(for: song) else { return [] }
        let dir = store.stemDirectory(for: song.id)
        let present = (song.stems ?? []).filter { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0.fileName).path) }
        // Lead + Backing replace the Music part when it has been split (they add up to it).
        let playing = Set(SongStudio.playableStems(present.map(\.kind)))
        let stems = present.filter { playing.contains($0.kind) }.map { (id: SongStudio.stem($0.kind), url: dir.appendingPathComponent($0.fileName)) }
        return stems.isEmpty ? [(SongStudio.original, main)] : stems
    }

    func stemKinds(for song: Song) -> [StemInfo.Kind] {
        audioTracks(for: song).compactMap { t in StemInfo.Kind.allCases.first { SongStudio.stem($0) == t.id } }
    }

    func loadSongAudio(_ song: Song) throws {
        let files = audioTracks(for: song)
        if !files.isEmpty { try sectionPlayer.load(files) }
    }

    /// Sets each audio track's level; tracks that are off stay in sync at zero volume.
    func applyAudioLevels(_ song: Song, forceAudible: Bool = false) {
        let s = song.accompaniment ?? AccompanimentSettings()
        let t = songPosition ?? cursor
        let section = song.orderedSections.last { $0.startTime <= t + 0.02 }?.id
        for id in sectionPlayer.trackIds {
            var level = SongStudio.effectiveLevel(id, s, section: section)
            if forceAudible && level == 0 && s.soloTrack == nil { level = SongStudio.level(id, s) }
            sectionPlayer.setLevel(Float(level), for: id)
        }
    }

    func updateAccompaniment(_ settings: AccompanimentSettings) {
        guard var song = song(activeSongId) else { return }
        song.accompaniment = settings
        update(song)
        configureAccompaniment(for: song)
    }

    // MARK: Library mutations

    func save() {
        saveTask?.cancel()
        let snapshot = library
        let store = self.store
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do { try store.save(snapshot) } catch {
                await MainActor.run { self.engineError = "Saving failed: \(error.localizedDescription)" }
            }
        }
    }

    func song(_ id: UUID?) -> Song? { id.flatMap { library.song(id: $0) } }

    func update(_ song: Song) {
        library.upsert(song)
        save()
    }

    func updateArrangement(_ arrangement: Arrangement, inSong songId: UUID?) {
        // AI Originals are preserved unchanged; edits go to My Version.
        guard arrangement.origin != .aiOriginal else { return }
        var a = arrangement
        a.updatedAt = Date()
        if let songId, var song = library.song(id: songId) {
            if let i = song.arrangements.firstIndex(where: { $0.id == a.id }) { song.arrangements[i] = a } else { song.arrangements.append(a) }
            update(song)
        } else {
            if let i = library.globalArrangements.firstIndex(where: { $0.id == a.id }) { library.globalArrangements[i] = a }
            else { library.globalArrangements.append(a) }
            save()
        }
        if activeArrangement?.id == a.id { activate(a, sectionId: activeSectionId) }
    }

    func regenerateSection(songId: UUID, sectionId: UUID) {
        guard let song = song(songId) else { return }
        let out = AutoArranger.arrange(song, patches: library.patches, onlySection: sectionId)
        update(out.song)
        if activeSectionId == sectionId { activateSection(sectionId) }
    }

    func restoreAIOriginal(songId: UUID, sectionId: UUID) {
        guard var song = song(songId) else { return }
        song.restoreAIOriginal(for: sectionId)
        update(song)
        if activeSectionId == sectionId { activateSection(sectionId) }
    }

    /// Gives one section its own copy of a shared tone so edits don't change its repeats.
    func detachTone(songId: UUID, sectionId: UUID) -> Arrangement? {
        guard var song = song(songId) else { return nil }
        let a = song.detachArrangement(for: sectionId)
        update(song)
        return a
    }

    func deleteSong(_ id: UUID) {
        if let song = library.song(id: id), song.sourceType == .importedFile, let file = song.sourceReference {
            try? store.deleteAudio(named: file)
        }
        try? store.deleteStems(for: id)
        analysisTasks[id]?.cancel()
        library.deleteSong(id: id)
        if activeSongId == id { activeSongId = nil; activate(nil) }
        save()
    }

    func audioURL(for song: Song) -> URL? {
        guard song.sourceType == .importedFile, let name = song.sourceReference else { return nil }
        return store.audioDirectory.appendingPathComponent(name)
    }

    /// Last import that failed because the audio couldn't be read (shown with a Retry button).
    @Published var importError: String?

    /// One-step import: copy the file, check it decodes, take title/artist from its tags (or the
    /// filename), and start analysis immediately. The file itself is never modified.
    @discardableResult
    func importAndAnalyze(from url: URL) -> UUID? {
        importError = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name: String
        do { name = try store.importFile(from: url, into: store.audioDirectory) } catch {
            importError = "Couldn't copy “\(url.lastPathComponent)”: \(error.localizedDescription)"
            return nil
        }
        let stored = store.audioDirectory.appendingPathComponent(name)
        guard let duration = AudioFileDecoder.duration(of: stored), duration > 0 else {
            try? store.deleteAudio(named: name)
            importError = "“\(url.lastPathComponent)” couldn't be read as audio. Check that it plays, then try again."
            return nil
        }
        let tags = AudioFileTags.read(url: stored)
        var song = Song(title: tags.displayTitle(filename: url.lastPathComponent), artist: tags.artist,
                        sourceType: .importedFile, sourceReference: name, userConfirmedRights: true, duration: duration)
        song.album = tags.album
        song.arrangements = [.starterFilmStack(name: "Main tone")]
        update(song)
        analyze(songId: song.id, useServer: serverSettings.enabled)
        return song.id
    }

    // MARK: Practice

    /// Loops a section at a practice speed (0.5–1.0). Generated accompaniment pauses below 100%
    /// because it can't follow a slowed recording yet.
    func practice(songId: UUID, sectionId: UUID, rate: Float) {
        ensurePerformance(songId: songId)
        guard let song = song(songId), let section = song.sections.first(where: { $0.id == sectionId }) else { return }
        playBackingTrack(from: section.startTime, to: section.endTime, loop: true, rate: rate)
        // Practice always plays the recording so you can hear the part.
        applyAudioLevels(song, forceAudible: true)
        if rate != 1 { host?.controller.setTransport(playing: false, seconds: section.startTime) }
        activateSection(sectionId)
    }

    var practiceRate: Float { sectionPlayer.rate }

    func importSoundFont(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        _ = try store.importFile(from: url, into: store.soundFontDirectory)
        objectWillChange.send()
        preloadDefaultSoundFont()
        applyActiveArrangement()
    }

    // MARK: Melody & chord corrections

    func correctChord(songId: UUID, stepId: UUID, to symbol: String) {
        guard var song = song(songId), let i = song.chordGuide?.firstIndex(where: { $0.id == stepId }),
              let fixed = ChordGuide.correct(song.chordGuide![i], to: symbol) else { return }
        song.chordGuide![i] = fixed
        update(song)
        if activeSongId == songId { configureAccompaniment(for: song) }
    }

    func editMelodyNote(songId: UUID, noteId: UUID, semitones: Int? = nil, delete: Bool = false) {
        guard var song = song(songId), var melody = song.melody, let i = melody.notes.firstIndex(where: { $0.id == noteId }) else { return }
        if delete { melody.notes.remove(at: i) } else if let s = semitones {
            melody.notes[i].midi = max(0, min(127, melody.notes[i].midi + s))
            melody.notes[i].userEdited = true
        }
        // Mark the track as edited so re-analysis keeps it.
        if delete, let first = melody.notes.indices.first { melody.notes[first].userEdited = true }
        song.melody = melody
        update(song)
        if activeSongId == songId { configureAccompaniment(for: song) }
    }

    func shiftMelody(songId: UUID, by semitones: Int) {
        guard var song = song(songId), let melody = song.melody else { return }
        var t = melody.transposed(by: semitones)
        if !t.notes.isEmpty { t.notes[0].userEdited = true }
        song.melody = t
        update(song)
        if activeSongId == songId { configureAccompaniment(for: song) }
    }

    func setPerformanceTranspose(songId: UUID, _ semitones: Int) {
        guard var song = song(songId) else { return }
        song.performanceTranspose = max(-12, min(12, semitones))
        update(song)
        if activeSongId == songId { configureAccompaniment(for: song) }
    }

    // MARK: Presets, samples, backup

    func exportPresets(_ arrangements: [Arrangement], name: String) throws -> URL {
        let data = try PresetExchange.export(arrangements, from: library)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).tonepilot.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    func importPresets(from url: URL) throws -> [String] {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var lib = library
        let (_, missing) = try PresetExchange.importPresets(Data(contentsOf: url), into: &lib)
        library = lib
        save()
        return missing
    }

    func exportBackup() throws -> URL {
        try store.exportBackup(to: FileManager.default.temporaryDirectory)
    }

    struct SampleInput {
        var url: URL
        var rootNote: UInt8
        var keyRange: KeyRange
        var velocityRange: VelocityRange = .full
        var trimStart: Double = 0
        var trimEnd: Double?
        var loop: ClosedRange<Double>?
    }

    /// Creates a playable patch from authorised samples. Returns the patch and an honesty
    /// warning when one sample is stretched over a wide range.
    func createSamplePatch(name: String, family: InstrumentFamily, samples: [SampleInput], envelope: Envelope,
                           license: LicenseInfo) throws -> (InstrumentPatch, String?) {
        var zones: [SampleZone] = []
        for s in samples {
            let scoped = s.url.startAccessingSecurityScopedResource()
            defer { if scoped { s.url.stopAccessingSecurityScopedResource() } }
            let fileName = try store.importFile(from: s.url, into: store.sampleDirectory)
            let rate = (try? AVAudioFile(forReading: store.sampleDirectory.appendingPathComponent(fileName)))?.processingFormat.sampleRate ?? 44_100
            func frame(_ t: Double) -> Int { Int(t * rate) }
            zones.append(SampleZone(fileName: fileName, rootNote: s.rootNote, keyRange: s.keyRange, velocityRange: s.velocityRange,
                                    startFrame: frame(s.trimStart), endFrame: s.trimEnd.map(frame),
                                    loopStart: s.loop.map { frame($0.lowerBound) }, loopEnd: s.loop.map { frame($0.upperBound) }))
        }
        let patch = InstrumentPatch(name: name, family: family, sourceType: .userSample, sampleZones: zones,
                                    envelope: envelope, license: license)
        let instrument = try cache.instrument(for: patch)
        library.upsert(patch)
        save()
        var warning: String?
        if instrument.maxStretchSemitones > 7 {
            warning = "Some keys are \(instrument.maxStretchSemitones) semitones away from their sample, so they'll sound unnatural (pitch-shifted). Add samples recorded at other pitches for a realistic instrument, or narrow the key range."
        }
        return (patch, warning)
    }

    // MARK: Analysis (one-click: analyse → arrange → ready to play)

    var serverToken: String? {
        get { Keychain.get("analysisServerToken") }
        set { Keychain.set(newValue, for: "analysisServerToken"); objectWillChange.send() }
    }

    /// - Parameter useServer: the user consented to upload this song to *their* analysis server.
    func analyze(songId: UUID, useServer: Bool = false) {
        guard var song = library.song(id: songId), let url = audioURL(for: song) else { return }
        analysisTasks[songId]?.cancel()
        song.analysisStatus = .running
        song.analysisError = nil
        update(song)
        analysisProgress[songId] = 0
        analysisNotice[songId] = nil
        let patches = library.patches
        let client = useServer ? AnalysisServerClient(settings: serverSettings, token: serverToken) : nil
        let settings = serverSettings
        let stemDir = store.stemDirectory(for: songId)
        let snapshot = song

        analysisTasks[songId] = Task.detached(priority: .userInitiated) { [weak self] in
            func stage(_ text: String, _ p: Double) async {
                await MainActor.run { self?.analysisStage[songId] = text; self?.analysisProgress[songId] = p }
            }
            do {
                var stems: [StemInfo.Kind: TonePilotCore.AudioBuffer] = [:]
                var stemInfos: [StemInfo] = []
                var serverMelody: MelodyTrack?
                var progressBase = 0.0
                if let client {
                    do {
                        await stage("Uploading to your analysis server…", 0.02)
                        let job = try await client.submit(audioFile: url, consent: true, model: settings.model, transcribeVocals: settings.transcribeVocals)
                        await stage("Separating vocals and instruments (Demucs)…", 0.05)
                        let result = try await client.waitForResult(job: job) { p in
                            Task { @MainActor in self?.analysisProgress[songId] = 0.05 + 0.35 * p }
                        }
                        await stage("Downloading stems…", 0.4)
                        for stem in result.stems {
                            guard let kind = StemInfo.Kind(rawValue: stem.kind) else { continue }
                            let file = try await client.downloadStem(stem, to: stemDir)
                            stems[kind] = try AudioFileDecoder.decodeMono(url: file)
                            stemInfos.append(StemInfo(kind: kind, fileName: file.lastPathComponent, model: stem.model))
                        }
                        serverMelody = result.melody
                        try? await client.delete(job: job) // don't leave the user's audio on the server
                        progressBase = 0.45
                    } catch {
                        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        await MainActor.run { self?.analysisNotice[songId] = "Server analysis unavailable (\(message)). Analysed on this iPhone instead." }
                    }
                }
                // Parts separated on this iPhone: analyse from them (beat from drums, chords from
                // the instruments, melody from the vocals).
                if stems.isEmpty, let local = await MainActor.run(body: { self?.audioTracks(for: snapshot) }) {
                    let parts = local.compactMap { t in SongStudio.stemKind(t.id).map { ($0, t.url) } }
                    if !parts.isEmpty { await stage("Reading the separated parts…", 0.02) }
                    for (kind, file) in parts { stems[kind] = try AudioFileDecoder.decodeMono(url: file) }
                }
                await stage("Decoding audio…", progressBase + 0.02)
                let audio = try AudioFileDecoder.decodeMono(url: url)
                await stage("Analysing tempo, key, chords, melody and sections…", progressBase + 0.05)
                let current = await MainActor.run { self?.library.song(id: songId) } ?? snapshot
                let base = progressBase + 0.05
                let throttle = ProgressThrottle()
                let output = try SongPipeline.run(song: current, audio: audio, stems: stems, melodyOverride: serverMelody, patches: patches) { p in
                    if Task.isCancelled { return false }
                    let value = base + (0.95 - base) * p
                    if throttle.shouldSend(value) { Task { @MainActor in self?.analysisProgress[songId] = value } }
                    return true
                }
                await MainActor.run {
                    guard let self else { return }
                    var s = output.song
                    if !stemInfos.isEmpty { s.stems = stemInfos }
                    self.analysisProgress[songId] = nil
                    self.analysisStage[songId] = nil
                    self.update(s)
                    if self.activeSongId == songId { self.startPerformance(songId: songId) }
                    // First analysis done: separate the parts (Moises-style) in the background.
                    if self.autoSeparate, s.sourceType == .importedFile, self.stemKinds(for: s).isEmpty,
                       self.separationError[songId] == nil {
                        self.separateStems(songId)
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self, var s = self.library.song(id: songId) else { return }
                    s.analysisStatus = error is CancellationError || (error as? SongAnalysisError) == .cancelled ? .notStarted : .failed
                    s.analysisError = Self.describe(error)
                    self.analysisProgress[songId] = nil
                    self.analysisStage[songId] = nil
                    self.update(s)
                }
            }
        }
    }

    /// Listen Mode: analyses audio captured from the microphone while the song played from the
    /// user's streaming app. On-device only — the captured audio is never stored or uploaded, and
    /// is released when analysis finishes.
    func analyzeListened(songId: UUID, audio: TonePilotCore.AudioBuffer) {
        guard var song = library.song(id: songId) else { return }
        analysisTasks[songId]?.cancel()
        song.analysisStatus = .running
        song.analysisError = nil
        // No file to use as a clock later: switching follows a tap-started timer by default.
        if song.switching == nil { song.switching = SwitchingSettings(mode: .assisted, reference: .timer) }
        update(song)
        analysisProgress[songId] = 0
        analysisStage[songId] = "Analysing what TonePilot heard…"
        let patches = library.patches
        let snapshot = song
        analysisTasks[songId] = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let current = await MainActor.run { self?.library.song(id: songId) } ?? snapshot
                let throttle = ProgressThrottle()
                let output = try SongPipeline.run(song: current, audio: audio, patches: patches) { p in
                    if Task.isCancelled { return false }
                    if throttle.shouldSend(p) { Task { @MainActor in self?.analysisProgress[songId] = p } }
                    return true
                }
                await MainActor.run {
                    guard let self else { return }
                    self.analysisProgress[songId] = nil
                    self.analysisStage[songId] = nil
                    self.analysisNotice[songId] = "Analysed from the microphone — accuracy depends on volume and room noise. Listen again to re-analyse."
                    self.update(output.song)
                }
            } catch {
                await MainActor.run {
                    guard let self, var s = self.library.song(id: songId) else { return }
                    s.analysisStatus = .failed
                    s.analysisError = Self.describe(error)
                    self.analysisProgress[songId] = nil
                    self.analysisStage[songId] = nil
                    self.update(s)
                }
            }
        }
    }

    func cancelAnalysis(songId: UUID) { analysisTasks[songId]?.cancel() }

    nonisolated static func describe(_ error: Error) -> String {
        switch error as? SongAnalysisError {
        case .tooShort: return "The audio is shorter than 8 seconds."
        case .silent: return "The audio appears to be silent."
        case .cancelled: return "Analysis was cancelled."
        case nil: return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Any song left "running" (app was killed mid-analysis) can be resumed.
    func resumeInterruptedAnalyses() {
        for song in library.songs where song.analysisStatus == .running && analysisTasks[song.id] == nil {
            analyze(songId: song.id)
        }
    }

    func testServer() async -> String {
        guard let client = AnalysisServerClient(settings: serverSettings, token: serverToken) else { return "Enter a valid http(s) address and enable the server." }
        do {
            let h = try await client.health()
            return "Connected · Demucs \(h.demucs ? "ready" : "not installed") · Basic Pitch \(h.basicPitch ? "ready" : "not installed") · files kept \(Int(h.retentionHours)) h"
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
