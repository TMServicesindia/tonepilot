import Foundation
import TonePilotCore
import UIKit

/// Lets through progress updates of at least 1% (each one redraws the screen).
final class ProgressThrottle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1.0
    func shouldSend(_ p: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard p - last >= 0.01 || p >= 1 else { return false }
        last = p
        return true
    }
}

/// Thread-safe set of song ids whose background work should stop.
final class CancelFlags: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: Set<UUID> = []
    func set(_ id: UUID) { lock.lock(); ids.insert(id); lock.unlock() }
    func clear(_ id: UUID) { lock.lock(); ids.remove(id); lock.unlock() }
    func contains(_ id: UUID) -> Bool { lock.lock(); defer { lock.unlock() }; return ids.contains(id) }
}

/// Moises-style separation on this iPhone: vocals, drums, bass and music as separate parts.
extension AppModel {
    /// The separator is part of the app; its model is downloaded when first needed.
    var canSeparate: Bool { true }

    func isSeparating(_ songId: UUID) -> Bool { separationProgress[songId] != nil }

    /// Rough time left, from the speed so far.
    func separationTimeLeft(_ songId: UUID) -> TimeInterval? {
        guard let p = separationProgress[songId], p > 0.03, let start = separationStart[songId] else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        return max(0, elapsed / p - elapsed)
    }

    /// Separates with the chosen pack (4 or 6 parts), downloading its model first if needed.
    func separateStems(_ songId: UUID) {
        let pack = separationPack
        guard !isSeparating(songId), modelDownloadProgress[pack] == nil else { return }
        if models.isInstalled(pack) { runSeparation(songId, pack: pack); return }
        downloadModel(pack) { [weak self] ok in if ok { self?.runSeparation(songId, pack: pack) } }
    }

    /// Downloads a separation model (progress in `modelDownloadProgress`).
    func downloadModel(_ pack: SeparationPack, then: ((Bool) -> Void)? = nil) {
        guard modelDownloadProgress[pack] == nil else { return }
        modelDownloadError = nil
        modelDownloadProgress[pack] = 0
        let store = models
        let throttle = ProgressThrottle()
        Task.detached(priority: .userInitiated) { [weak self] in
            var failure: String?
            do {
                try await store.install(pack) { p in
                    if throttle.shouldSend(p) { Task { @MainActor in if self?.modelDownloadProgress[pack] != nil { self?.modelDownloadProgress[pack] = p } } }
                }
            } catch {
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            let failureText = failure
            await MainActor.run {
                self?.modelDownloadProgress[pack] = nil
                self?.modelDownloadError = failureText
                then?(failureText == nil)
            }
        }
    }

    func deleteModel(_ pack: SeparationPack) {
        guard modelDownloadProgress[pack] == nil else { return }
        models.delete(pack)
        objectWillChange.send()
    }

    private func runSeparation(_ songId: UUID, pack: SeparationPack) {
        guard !isSeparating(songId), let song = song(songId), let url = audioURL(for: song) else { return }
        StemSeparator.current = models.weightsURL(pack)
        CoreMLNetwork.current = models.coreMLURL(pack)
        separationError[songId] = nil
        separationProgress[songId] = 0
        separationStart[songId] = Date()
        separationCancels.clear(songId)
        let dir = store.stemDirectory(for: songId)
        let cancels = separationCancels
        UIApplication.shared.isIdleTimerDisabled = true
        // Keeps going briefly if the app is sent to the background; it resumes when reopened.
        var bgTask = UIBackgroundTaskIdentifier.invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "Separate parts") {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
        let thread = Thread { [weak self] in
            let result: Result<[StemInfo], Error>
            do {
                let stems = try StemSeparator.separate(input: url, outputDir: dir, progress: { p in
                    // (StemSeparator already reports at most every 0.5%.)
                    Task { @MainActor in if self?.separationProgress[songId] != nil { self?.separationProgress[songId] = p } }
                }, isCancelled: { cancels.contains(songId) })
                result = .success(stems)
            } catch {
                result = .failure(error)
            }
            Task { @MainActor in
                guard let self else { return }
                if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
                self.separationProgress[songId] = nil
                self.separationStart[songId] = nil
                switch result {
                case .success(let stems): self.stemsReady(songId, stems)
                case .failure(let error):
                    if case StemSeparator.Failure.cancelled = error { return }
                    self.separationError[songId] = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
        // .userInitiated keeps the work on the performance cores (.utility moves it to the
        // efficiency cores, which made separation several times slower).
        thread.qualityOfService = .userInitiated
        thread.stackSize = 8 << 20
        thread.start()
    }

    func cancelSeparation(_ songId: UUID) {
        separationCancels.set(songId)
        separationProgress[songId] = nil
        separationStart[songId] = nil
    }

    private func stemsReady(_ songId: UUID, _ stems: [StemInfo]) {
        guard var song = song(songId) else { return }
        song.stems = stems
        var acc = song.accompaniment ?? AccompanimentSettings()
        SongStudio.applyStemDefaults(&acc, stems: stems.map(\.kind))
        song.accompaniment = acc
        update(song)
        if activeSongId == songId {
            let wasPlaying = isStudioPlaying
            if wasPlaying { studioPause() }
            try? loadSongAudio(song)
            configureAccompaniment(for: song)
            if wasPlaying { studioTogglePlay() }
        }
        // Re-analyse from the parts: cleaner beat, chords and melody.
        analyze(songId: songId)
        // Then split the Music part into Lead instruments and Backing.
        splitMusic(songId)
    }

    // MARK: Lead instruments / Backing

    func canSplitMusic(_ song: Song) -> Bool {
        (song.stems ?? []).contains { $0.kind == .other } && !(song.stems ?? []).contains { $0.kind == .lead }
    }

    /// Splits the separated Music part into Lead instruments (its main melodic line) and Backing,
    /// on a background thread; the two replace Music in the mixer.
    func splitMusic(_ songId: UUID) {
        guard musicSplitProgress[songId] == nil, let song = song(songId),
              let music = song.stems?.first(where: { $0.kind == .other }) else { return }
        let dir = store.stemDirectory(for: songId)
        let input = dir.appendingPathComponent(music.fileName)
        guard FileManager.default.fileExists(atPath: input.path) else { return }
        musicSplitProgress[songId] = 0
        let throttle = ProgressThrottle()
        let thread = Thread { [weak self] in
            var made: [StemInfo]?
            var failure: String?
            autoreleasepool {
                do {
                    let (l, r) = try StemSeparator.decodeStereo(input)
                    guard let result = LeadSplitter.split(channels: [l, r], sampleRate: StemSeparator.sampleRate, progress: { p in
                        if throttle.shouldSend(p) { Task { @MainActor in self?.musicSplitProgress[songId] = p * 0.9 } }
                        return true
                    }) else { failure = "The music part is too short to split."; return }
                    try StemSeparator.writeStem(left: result.lead[0], right: result.lead[1], to: dir.appendingPathComponent("lead.m4a"))
                    try StemSeparator.writeStem(left: result.backing[0], right: result.backing[1], to: dir.appendingPathComponent("backing.m4a"))
                    made = [StemInfo(kind: .lead, fileName: "lead.m4a", model: "TonePilot lead split"),
                            StemInfo(kind: .backing, fileName: "backing.m4a", model: "TonePilot lead split")]
                } catch {
                    failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            let failureText = failure, madeStems = made
            Task { @MainActor in
                guard let self else { return }
                self.musicSplitProgress[songId] = nil
                if let failure = failureText { self.separationError[songId] = "Lead/backing split: \(failure)"; return }
                guard let made = madeStems, var song = self.song(songId) else { return }
                song.stems = (song.stems ?? []).filter { $0.kind != .lead && $0.kind != .backing } + made
                var acc = song.accompaniment ?? AccompanimentSettings()
                // "Original plays the difficult parts" now uses just the lead instruments.
                if acc.aiPartTrack == SongStudio.stem(.other) || acc.aiPartTrack == nil { acc.aiPartTrack = SongStudio.stem(.lead) }
                // Music was off → keep both halves off.
                if acc.stemsOff?.contains(SongStudio.stem(.other)) == true {
                    acc.stemsOff = (acc.stemsOff ?? []) + [SongStudio.stem(.lead), SongStudio.stem(.backing)]
                }
                song.accompaniment = acc
                self.update(song)
                if self.activeSongId == songId {
                    let wasPlaying = self.isStudioPlaying
                    if wasPlaying { self.studioPause() }
                    try? self.loadSongAudio(song)
                    self.configureAccompaniment(for: song)
                    if wasPlaying { self.studioTogglePlay() }
                }
            }
        }
        thread.qualityOfService = .userInitiated
        thread.stackSize = 8 << 20
        thread.start()
    }

    // MARK: AI plays difficult parts (recording or AI melody)

    func setAIParts(_ on: Bool, songId: UUID) {
        editStudioSettings(songId, resequence: true) { s in
            SongStudio.setAIParts(on, &s)
            if on, s.guideSections == nil, let song = self.song(songId) {
                s.guideSections = SongStudio.suggestedAIParts(song, source: s.aiPartTrack)
            }
        }
    }

    func setAIPartSource(_ id: String, songId: UUID) {
        editStudioSettings(songId, resequence: true) { s in
            SongStudio.setAIPartSource(id, &s)
            if let song = self.song(songId) { s.guideSections = SongStudio.suggestedAIParts(song, source: s.aiPartTrack) }
        }
    }

    func editStudioSettings(_ songId: UUID, resequence: Bool, _ change: (inout AccompanimentSettings) -> Void) {
        guard var song = song(songId) else { return }
        var acc = song.accompaniment ?? AccompanimentSettings()
        change(&acc)
        song.accompaniment = acc
        update(song)
        guard activeSongId == songId else { return }
        if resequence { configureAccompaniment(for: song) } else { applyMix(song) }
    }

    // MARK: Main tone (one tone for the whole song)

    /// The song's own tone that isn't tied to a section (e.g. "Main tone").
    func mainTone(of song: Song) -> Arrangement? {
        let used = Set(song.sections.compactMap(\.arrangementId))
        let own = song.arrangements.filter { !used.contains($0.id) && $0.origin != .aiOriginal }
        return own.first { $0.name == "Main tone" } ?? own.first
    }

    /// Plays the main tone for the whole song (section changes stop switching the tone). Saved per song.
    /// The main tone is made from the song (its chorus/most intense part) unless you edited it yourself.
    func useMainTone(_ songId: UUID) {
        guard var song = song(songId) else { return }
        let before = song.arrangements
        AutoArranger.refreshMainTone(&song)
        if mainTone(of: song) == nil { song.arrangements.append(.starterFilmStack(name: "Main tone")) }
        if song.arrangements != before { update(song) }
        guard let tone = mainTone(of: song) else { return }
        var sw = song.switching ?? SwitchingSettings()
        sw.mode = .manual
        sw.useMainTone = true
        saveSwitching(sw, songId: songId)
        if activeSongId == songId { activate(tone, songId: songId, sectionId: activeSectionId) }
    }

    /// Changes the keyboard's tone with each section of the song. Saved per song.
    func useSectionTones(_ songId: UUID) {
        guard let song = song(songId) else { return }
        var sw = song.switching ?? SwitchingSettings()
        sw.mode = .automatic
        sw.useMainTone = false
        if audioURL(for: song) == nil, sw.reference == .backingTrack { sw.reference = .timer }
        saveSwitching(sw, songId: songId)
        guard activeSongId == songId else { return }
        let t = songPosition ?? cursor
        if let section = song.orderedSections.last(where: { $0.startTime <= t + 0.01 }) ?? song.orderedSections.first {
            activateSection(section.id)
        }
    }

    private func saveSwitching(_ sw: SwitchingSettings, songId: UUID) {
        if activeSongId == songId { updateSwitching(sw); return }
        guard var song = song(songId) else { return }
        song.switching = sw
        update(song)
    }

    /// The song's saved choice (not whichever tone happens to be active).
    func isUsingMainTone(_ song: Song) -> Bool { (song.switching ?? SwitchingSettings()).playsMainTone }
}
