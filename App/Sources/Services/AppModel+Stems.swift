import Foundation
import TonePilotCore
import UIKit

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
    var canSeparate: Bool { StemSeparator.isAvailable }

    func isSeparating(_ songId: UUID) -> Bool { separationProgress[songId] != nil }

    /// Rough time left, from the speed so far.
    func separationTimeLeft(_ songId: UUID) -> TimeInterval? {
        guard let p = separationProgress[songId], p > 0.03, let start = separationStart[songId] else { return nil }
        let elapsed = Date().timeIntervalSince(start)
        return max(0, elapsed / p - elapsed)
    }

    func separateStems(_ songId: UUID) {
        guard canSeparate, !isSeparating(songId), let song = song(songId), let url = audioURL(for: song) else { return }
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
        return song.arrangements.first { !used.contains($0.id) && $0.origin != .aiOriginal }
    }

    /// Plays the main tone for the whole song (section changes stop switching the tone).
    func useMainTone(_ songId: UUID) {
        guard var song = song(songId) else { return }
        if mainTone(of: song) == nil {
            song.arrangements.append(.starterFilmStack(name: "Main tone"))
            update(song)
        }
        guard let tone = mainTone(of: song) else { return }
        var sw = song.switching ?? SwitchingSettings()
        sw.mode = .manual
        updateSwitching(sw)
        activate(tone, songId: songId, sectionId: nil)
    }

    /// Back to a tone per section, switching automatically.
    func useSectionTones(_ songId: UUID) {
        guard let song = song(songId) else { return }
        var sw = song.switching ?? SwitchingSettings()
        sw.mode = .automatic
        if audioURL(for: song) == nil, sw.reference == .backingTrack { sw.reference = .timer }
        updateSwitching(sw)
        let t = songPosition ?? cursor
        if let section = song.orderedSections.last(where: { $0.startTime <= t + 0.01 }) ?? song.orderedSections.first {
            activateSection(section.id)
        }
    }

    func isUsingMainTone(_ song: Song) -> Bool {
        guard let main = mainTone(of: song) else { return false }
        return activeSongId == song.id && activeArrangement?.id == main.id
    }
}
