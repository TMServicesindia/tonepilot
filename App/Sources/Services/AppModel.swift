import AVFoundation
import SwiftUI
import TonePilotCore

/// App-wide state. Owns the library, the sound engine, MIDI input and the note router,
/// and is the only place that mutates the library (then saves it, debounced).
@MainActor
final class AppModel: ObservableObject {
    @Published var library = Library()
    @Published var activeSongId: UUID?
    @Published var activeArrangement: Arrangement?
    @Published var activeSectionId: UUID?
    @Published var outputPeak: Float = 0
    @Published var outputClipped = false
    @Published var engineError: String?
    @Published var patchLoadErrors: [String] = []
    @Published var analysisProgress: [UUID: Double] = [:]
    @Published var isSectionPlaying = false
    @Published var velocityCurve: VelocityCurve = .linear {
        didSet { router.velocityCurve = velocityCurve }
    }

    let store: LibraryStore
    let engine: SoundEngine
    let midi = MIDIInputManager()
    let router = NoteRouter()
    private(set) lazy var sectionPlayer = SectionPlayer(player: engine.songPlayer, engine: engine.engine)
    private var saveTask: Task<Void, Never>?
    private var analysisTasks: [UUID: Task<Void, Never>] = [:]

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("TonePilot", isDirectory: true)
        // Directory creation only fails if the disk is full or sandbox is broken; surface it but continue.
        let store = (try? LibraryStore(rootDirectory: root)) ?? (try! LibraryStore(rootDirectory: FileManager.default.temporaryDirectory))
        self.store = store
        self.engine = SoundEngine(soundFontDirectory: store.soundFontDirectory)

        do {
            library = try store.load()
        } catch {
            engineError = "Library could not be loaded (\(error)). A new library was started; the old file was kept."
        }
        library.mergeFactoryPatches(FactoryPatches.all)
        installBundledSoundFonts()
        wireMIDI()
        observeAudioSession()
        startEngine()
    }

    // MARK: Setup

    private func installBundledSoundFonts() {
        guard let bundled = Bundle.main.urls(forResourcesWithExtension: "sf2", subdirectory: "SoundFonts") else { return }
        for url in bundled {
            let dest = store.soundFontDirectory.appendingPathComponent(url.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.copyItem(at: url, to: dest) }
        }
    }

    var installedSoundFonts: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: store.soundFontDirectory.path))?
            .filter { ["sf2", "dls"].contains(($0 as NSString).pathExtension.lowercased()) }.sorted() ?? []
    }

    var defaultSoundFontInstalled: Bool { installedSoundFonts.contains(FactoryPatches.defaultSoundFontFile) }

    private func wireMIDI() {
        let router = self.router
        let engine = self.engine
        midi.onEvents = { events in
            // CoreMIDI thread: route and play immediately, nothing else.
            for e in events { engine.perform(router.handle(e)) }
        }
        midi.onSourcesChanged = { [weak self] removed in
            // A cable pulled mid-note never sends note-off: release everything.
            if removed { self?.panic() }
        }
        midi.start()
        engine.onMeter = { [weak self] peak, clipped in
            self?.outputPeak = peak
            if clipped { self?.outputClipped = true }
        }
    }

    private func startEngine() {
        do {
            try engine.start()
            engineError = nil
            applyActiveArrangement()
        } catch {
            engineError = "Audio engine failed to start: \(error.localizedDescription)"
        }
    }

    private func observeAudioSession() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor in
                if type == .began { self?.panic() } else { self?.startEngine() }
            }
        }
        nc.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.objectWillChange.send() }
        }
        nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine.engine, queue: .main) { [weak self] _ in
            // Route/sample-rate change stops the engine; restart it.
            Task { @MainActor in self?.startEngine() }
        }
    }

    // MARK: Performance

    func panic() {
        engine.perform(router.panic())
    }

    func resetClip() { outputClipped = false }

    /// Makes `arrangement` the sound you hear when playing the Casio.
    func activate(_ arrangement: Arrangement?, songId: UUID? = nil, sectionId: UUID? = nil) {
        activeArrangement = arrangement
        if let songId { activeSongId = songId }
        activeSectionId = sectionId
        applyActiveArrangement()
    }

    func applyActiveArrangement() {
        let patches = Dictionary(uniqueKeysWithValues: library.patches.map { ($0.id, $0) })
        engine.perform(router.setArrangement(activeArrangement))
        engine.apply(activeArrangement, patches: patches) { [weak self] failures in
            self?.patchLoadErrors = failures
        }
    }

    /// Plays a note from the on-screen audition strip through the exact same path as the Casio.
    func audition(note: UInt8, on: Bool) {
        let event: MIDIEvent = on ? .noteOn(channel: 1, note: note, velocity: 96) : .noteOff(channel: 1, note: note, velocity: 0)
        engine.perform(router.handle(event))
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

    func deleteSong(_ id: UUID) {
        if let song = library.song(id: id), song.sourceType == .importedFile, let file = song.sourceReference {
            try? store.deleteAudio(named: file)
        }
        analysisTasks[id]?.cancel()
        library.deleteSong(id: id)
        if activeSongId == id { activeSongId = nil; activate(nil) }
        save()
    }

    func audioURL(for song: Song) -> URL? {
        guard song.sourceType == .importedFile, let name = song.sourceReference else { return nil }
        return store.audioDirectory.appendingPathComponent(name)
    }

    /// Copies a user-selected file into app storage and creates a song for it.
    func importAudio(from url: URL, title: String, rightsConfirmed: Bool) throws -> Song {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = try store.importFile(from: url, into: store.audioDirectory)
        let stored = store.audioDirectory.appendingPathComponent(name)
        var song = Song(title: title.isEmpty ? url.deletingPathExtension().lastPathComponent : title,
                        sourceType: .importedFile, sourceReference: name, userConfirmedRights: rightsConfirmed,
                        duration: AudioFileDecoder.duration(of: stored))
        song.arrangements = [.starterFilmStack(name: "Main tone")]
        update(song)
        return song
    }

    func importSoundFont(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        _ = try store.importFile(from: url, into: store.soundFontDirectory)
        objectWillChange.send()
        applyActiveArrangement()
    }

    // MARK: Analysis

    func analyze(songId: UUID) {
        guard var song = library.song(id: songId), let url = audioURL(for: song) else { return }
        guard song.userConfirmedRights else { return }
        analysisTasks[songId]?.cancel()
        song.analysisStatus = .running
        song.analysisError = nil
        update(song)
        analysisProgress[songId] = 0

        analysisTasks[songId] = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let audio = try AudioFileDecoder.decodeMono(url: url)
                await MainActor.run { self?.analysisProgress[songId] = 0.1 }
                let result = try SongAnalyzer.analyze(audio) { p in
                    if Task.isCancelled { return false }
                    Task { @MainActor in self?.analysisProgress[songId] = 0.1 + 0.9 * p }
                    return true
                }
                await MainActor.run {
                    guard let self, var s = self.library.song(id: songId) else { return }
                    s.apply(result)
                    self.analysisProgress[songId] = nil
                    self.update(s)
                }
            } catch {
                await MainActor.run {
                    guard let self, var s = self.library.song(id: songId) else { return }
                    s.analysisStatus = error is CancellationError || (error as? SongAnalysisError) == .cancelled ? .notStarted : .failed
                    s.analysisError = Self.describe(error)
                    self.analysisProgress[songId] = nil
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
        case nil: return error.localizedDescription
        }
    }

    /// Any song left "running" (app was killed mid-analysis) can be resumed.
    func resumeInterruptedAnalyses() {
        for song in library.songs where song.analysisStatus == .running && analysisTasks[song.id] == nil {
            analyze(songId: song.id)
        }
    }
}
