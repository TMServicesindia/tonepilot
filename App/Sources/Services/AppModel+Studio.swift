import Foundation
import TonePilotCore

/// Song Studio: one place to play a song, mix its parts, and change section tones.
extension AppModel {
    // MARK: Opening

    /// Opens `songId` in the Song Studio tab, ready to play.
    func openStudio(_ songId: UUID) {
        if activeSongId != songId {
            stopBackingTrack()
            cursor = 0
            loopSectionId = nil
        }
        if var song = song(songId) {
            var acc = song.accompaniment ?? AccompanimentSettings()
            let before = acc
            SongStudio.applyFirstOpenDefaults(&acc, hasAudio: audioURL(for: song) != nil)
            if acc != before { song.accompaniment = acc; update(song) }
        }
        // Always switch the performance to this song (another song may still be loaded).
        if activeSongId != songId { startPerformance(songId: songId) } else { ensurePerformance(songId: songId) }
        selectedTab = .studio
        loadWaveform(songId)
    }

    /// Leaves the song (free play with any tone).
    func closeStudioSong() {
        stopBackingTrack()
        stopTimerClock()
        activeSongId = nil
        activeSectionId = nil
        loopSectionId = nil
        cursor = 0
    }

    // MARK: Transport

    var isStudioPlaying: Bool {
        guard let song = song(activeSongId) else { return false }
        return audioURL(for: song) != nil ? isSectionPlaying : songPosition != nil
    }

    func studioTogglePlay() {
        guard let song = song(activeSongId) else { return }
        if isStudioPlaying { studioPause(); return }
        if audioURL(for: song) == nil {
            // No recording (Listen Mode songs): the song clock starts now — begin playing on beat 1.
            startTimerClock(at: cursor)
            return
        }
        if let loop = loopSectionId, let section = song.sections.first(where: { $0.id == loop }) {
            let from = (section.startTime..<section.endTime).contains(cursor) ? cursor : section.startTime
            playBackingTrack(from: from, to: section.endTime, loop: true, rate: studioRate)
        } else {
            playBackingTrack(from: cursor >= (song.duration ?? .infinity) - 0.5 ? 0 : cursor, rate: studioRate)
        }
    }

    func studioPause() {
        if let p = songPosition { cursor = p }
        guard let song = song(activeSongId) else { return }
        if audioURL(for: song) != nil { stopBackingTrack() } else { stopTimerClock() }
    }

    /// Moves to `time`; keeps playing if the song was playing.
    func studioSeek(to time: Double) {
        guard let song = song(activeSongId) else { return }
        let t = max(0, min(time, song.duration ?? time))
        cursor = t
        if let section = song.orderedSections.last(where: { $0.startTime <= t + 0.01 }) {
            if loopSectionId != nil, !(section.startTime..<section.endTime).contains(t) { loopSectionId = section.id }
            activate(song.arrangement(for: section), songId: song.id, sectionId: section.id)
        }
        if isStudioPlaying { studioPause(); cursor = t; studioTogglePlay() }
    }

    func studioJump(to sectionId: UUID) {
        guard let section = song(activeSongId)?.sections.first(where: { $0.id == sectionId }) else { return }
        if loopSectionId != nil { loopSectionId = sectionId }
        studioSeek(to: section.startTime)
    }

    /// Loops the current section (or stops looping).
    func studioToggleLoop() {
        let wasPlaying = isStudioPlaying
        if loopSectionId != nil {
            loopSectionId = nil
        } else {
            let t = songPosition ?? cursor
            loopSectionId = song(activeSongId)?.orderedSections.last { $0.startTime <= t + 0.01 }?.id ?? activeSectionId
        }
        if wasPlaying { studioPause(); studioTogglePlay() }
    }

    func setStudioRate(_ rate: Float) {
        studioRate = rate
        if isStudioPlaying { studioPause(); studioTogglePlay() }
    }

    // MARK: Mixer

    func studioTracks(for song: Song) -> [StudioTrack] {
        SongStudio.tracks(for: song, hasAudio: audioURL(for: song) != nil, stems: stemKinds(for: song))
    }

    private func editMix(_ songId: UUID, resequence: Bool = false, _ change: (inout AccompanimentSettings) -> Void) {
        guard var song = song(songId) else { return }
        var acc = song.accompaniment ?? AccompanimentSettings()
        change(&acc)
        song.accompaniment = acc
        update(song)
        guard activeSongId == songId else { return }
        if resequence { configureAccompaniment(for: song) } else { applyMix(song) }
    }

    func setTrack(_ id: String, on: Bool, songId: UUID) {
        editMix(songId) { SongStudio.setOn(id, on, &$0) }
    }

    func setTrackLevel(_ id: String, _ level: Double, songId: UUID) {
        editMix(songId) { SongStudio.setLevel(id, level, &$0) }
    }

    /// Live preview while a slider moves (saved when the drag ends via `setTrackLevel`).
    func previewTrackLevel(_ id: String, _ level: Double, songId: UUID) {
        guard var song = song(songId), activeSongId == songId else { return }
        var acc = song.accompaniment ?? AccompanimentSettings()
        SongStudio.setLevel(id, level, &acc)
        song.accompaniment = acc
        applyMix(song)
    }

    func toggleSolo(_ id: String, songId: UUID) {
        editMix(songId) { SongStudio.toggleSolo(id, &$0) }
    }

    func setChordStyle(_ style: AccompanimentSettings.ChordStyle, songId: UUID) {
        editMix(songId, resequence: true) { $0.chordStyle = style }
    }

    func setDrumStyle(_ style: AccompanimentSettings.DrumStyle, songId: UUID) {
        editMix(songId, resequence: true) { $0.drumStyle = style }
    }

    // MARK: AI plays difficult parts

    /// Sections where the AI melody plays; nil = the whole song.
    func setAIPartSections(_ ids: [UUID]?, songId: UUID) {
        editMix(songId, resequence: true) { $0.guideSections = ids }
    }

    func toggleAIPart(_ sectionId: UUID, songId: UUID) {
        guard let song = song(songId) else { return }
        var ids = song.accompaniment?.guideSections ?? song.sections.map(\.id)
        if let i = ids.firstIndex(of: sectionId) { ids.remove(at: i) } else { ids.append(sectionId) }
        setAIPartSections(ids, songId: songId)
    }

    func setAIPartSound(_ patchId: UUID?, songId: UUID) {
        editMix(songId) { $0.guidePatchId = patchId }
    }

    // MARK: Section tones

    /// Plays `tone` on the keyboard without assigning it (tone picker preview).
    func previewTone(_ tone: Arrangement) {
        previewingToneId = tone.id
        activate(tone, songId: activeSongId, sectionId: activeSectionId)
    }

    /// Ends a preview and goes back to the section's own tone.
    func endTonePreview() {
        previewingToneId = nil
        if let id = activeSectionId { activateSection(id) }
    }

    /// Uses `tone` for one section. The section gets its own copy (My Version), so the original
    /// tone and the AI Original stay unchanged and Restore AI Original still works.
    func assignTone(_ tone: Arrangement, songId: UUID, sectionId: UUID) {
        guard var song = song(songId), let i = song.sections.firstIndex(where: { $0.id == sectionId }) else { return }
        let section = song.sections[i]
        let aiOriginal = song.aiOriginal(for: section)
        var copy = tone
        copy.id = UUID()
        copy.name = "\(section.label) – \(tone.name.replacingOccurrences(of: " (My Version)", with: ""))"
        copy.origin = .myVersion
        copy.derivedFrom = aiOriginal?.id
        copy.createdAt = Date()
        copy.updatedAt = Date()
        let old = section.arrangementId
        song.arrangements.append(copy)
        song.sections[i].arrangementId = copy.id
        // Drop the previous My Version if nothing uses it any more (AI Originals are kept).
        if let old, old != aiOriginal?.id, !song.sections.contains(where: { $0.arrangementId == old }),
           song.arrangements.first(where: { $0.id == old })?.origin == .myVersion {
            song.arrangements.removeAll { $0.id == old }
        }
        update(song)
        previewingToneId = nil
        if activeSongId == songId, activeSectionId == sectionId || activeSectionId == nil {
            activate(copy, songId: songId, sectionId: sectionId)
        }
    }

    /// The tone to edit for a section: its My Version, detached first if other sections share it.
    func editableTone(songId: UUID, sectionId: UUID) -> Arrangement? {
        guard let song = song(songId), let section = song.sections.first(where: { $0.id == sectionId }),
              let tone = song.arrangement(for: section) else { return nil }
        if tone.origin == .aiOriginal {
            var s = song
            let mine = tone.makeMyVersion()
            s.arrangements.append(mine)
            if let i = s.sections.firstIndex(where: { $0.id == sectionId }) { s.sections[i].arrangementId = mine.id }
            update(s)
            return mine
        }
        return tone
    }

    // MARK: Waveform

    func loadWaveform(_ songId: UUID) {
        guard waveforms[songId] == nil, let song = song(songId), let url = audioURL(for: song) else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let audio = try? AudioFileDecoder.decodeMono(url: url, sampleRate: 4_000) else { return }
            let peaks = SongStudio.waveform(audio.samples, bins: 600)
            await MainActor.run { self?.waveforms[songId] = peaks }
        }
    }
}
