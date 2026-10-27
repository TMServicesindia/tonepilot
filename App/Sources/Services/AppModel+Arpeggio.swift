import Foundation
import QuartzCore
import TonePilotCore

/// Which pattern the Song Arpeggio preview is playing.
struct ArpeggioPreview: Equatable {
    let songId: UUID
    let sectionId: UUID
}

/// Song Arpeggio: each section plays a basic broken-chord style adjusted to the song.
/// - Live fill-in: you start each bar with your R · 5 · 8 in the left hand; TonePilot decides the
///   chord and plays the rest of the bar in your tone — song playing or paused.
/// - Preview: the section's pattern on the song's own chords, on the engine's own pattern clock.
extension AppModel {
    func arpeggioSections(_ song: Song) -> [SongSection] {
        song.orderedSections.filter { song.arpeggio?.pattern(for: $0.id) != nil }
    }

    /// Section the arpeggio follows: the one playing (song running), else the one chosen on the page.
    func arpeggioSection(_ song: Song) -> SongSection? {
        let sections = arpeggioSections(song)
        if let t = songPosition, let playing = sections.last(where: { $0.startTime <= t + 0.01 }) { return playing }
        return sections.first { $0.id == arpeggioSectionId } ?? sections.first { $0.type == .verse } ?? sections.first
    }

    /// The fill's sound: "same as my keys" (the active tone's chord-hand layer) unless one was chosen.
    func arpeggioPatch(_ arp: SongArpeggio) -> InstrumentPatch? {
        if let id = arp.soundId, let p = library.patch(id: id) { return p }
        let layers = activeArrangement?.layers.filter { !$0.muted } ?? []
        let left = layers.first { $0.keyRange.contains(48) } ?? layers.first
        return left.flatMap { library.patch(id: $0.patchId) } ?? library.patch(id: FactoryPatches.softPianoId)
    }

    private func loadArpeggioSound(_ arp: SongArpeggio) {
        guard let host else { return }
        if let error = host.controller.setAccompaniment(.arpeggio, patch: arpeggioPatch(arp), volume: arp.effectiveVolume, cache: cache) {
            engineError = error
        }
    }

    // MARK: Live fill-in

    func setArpeggioLive(_ on: Bool, songId: UUID) {
        editArpeggio(songId) { arp, _ in arp.liveFill = on }
        if on { stopArpeggioPreview() }
        refreshArpeggioLive()
    }

    /// Arms or disarms live fill-in for the open song (call when the song, section, tone or
    /// settings change). The fill itself runs on the MIDI thread (`LiveFill`).
    func refreshArpeggioLive() {
        guard let host, let song = song(activeSongId), let arp = song.arpeggio, arp.liveFill == true,
              let section = arpeggioSection(song), let pattern = arp.playable(for: section.id) else {
            arpeggioLiveFlag.withLock { $0 = false }
            liveFill.install(nil, handle: 0, sampleRate: 48_000, controller: host?.controller, beats: [], stepsPerBeat: 3)
            arpeggioLiveChord = nil
            return
        }
        loadArpeggioSound(arp)
        // Timing from the song: its tempo and feel (steps per beat), locked to its beat while it plays.
        let stepSeconds = 60 / max(30, arp.effectiveBPM) / Double(pattern.stepsPerBeat)
        let chords = song.chordEvents
        let typical = LiveArpeggiator.typicalChordLength(chords, from: section.startTime, to: section.endTime)
        let quality = LiveArpeggiator.songQuality(chords: chords, key: song.key?.value)
        let fill = liveFill
        let arpeggiator = LiveArpeggiator(
            pattern: pattern, stepSeconds: stepSeconds, split: arp.effectiveSplit, memory: arp.memory,
            // Playing: until the song's next chord change; paused: the section's usual chord length.
            chordLength: { [weak fill] t in
                guard let now = fill?.songTime(at: t), let next = chords.first(where: { $0.time > now + 0.1 }) else { return typical }
                return max(0.3, min(4, next.time - now))
            },
            // The song's chord counts only while it plays (paused: its chords overall, then the key).
            songQuality: { [weak fill] pc, t in quality(pc, fill?.songTime(at: t) ?? -1) },
            snap: { [weak fill] t in fill?.snapToSong(t) ?? t })
        let songId = song.id
        liveFill.onChange = { [weak self] chord, memory in
            guard let self else { return }
            self.arpeggioLiveChord = chord.map { "\(NoteName.sharpNames[$0.root]) \($0.quality == .minor ? "minor" : "major")" }
            self.saveChordMemory(memory, songId: songId)
        }
        liveFill.install(arpeggiator, handle: host.controller.accompanimentHandle(.arpeggio), sampleRate: host.core.sampleRate,
                         controller: host.controller, beats: song.beatTimes, stepsPerBeat: pattern.stepsPerBeat)
        arpeggioFollowerSection = section.id
        arpeggioLiveFlag.withLock { $0 = true }
    }

    /// Keeps what you play (major/minor per root) with the song.
    private func saveChordMemory(_ memory: [Int: ChordSymbol.Quality], songId: UUID) {
        guard var song = song(songId), var arp = song.arpeggio else { return }
        let stored = Dictionary(uniqueKeysWithValues: memory.map { (String($0.key), $0.value == .minor ? "m" : "") })
        guard stored != (arp.chordMemory ?? [:]) else { return }
        arp.chordMemory = stored
        song.arpeggio = arp
        update(song)
    }

    /// Forgets the chords you taught TonePilot for this song.
    func resetChordMemory(songId: UUID) {
        guard var song = song(songId), var arp = song.arpeggio else { return }
        arp.chordMemory = nil
        song.arpeggio = arp
        update(song)
        liveFill.resetMemory()
        refreshArpeggioLive()
    }

    // MARK: Preview

    /// Plays (or replaces) the preview of a section's pattern on the song's own chords.
    func startArpeggioPreview(songId: UUID, sectionId: UUID) {
        guard let host, let song = song(songId), let arp = song.arpeggio,
              let section = song.sections.first(where: { $0.id == sectionId }), let pattern = arp.playable(for: sectionId) else { return }
        let c = host.controller
        loadArpeggioSound(arp)
        let bars = ArpeggioRenderer.bars(of: section, in: song, pattern: pattern, bpm: arp.bpm)
        let loop = ArpeggioRenderer.loop(pattern, bars: bars, bpm: arp.effectiveBPM, handle: c.accompanimentHandle(.arpeggio),
                                         sampleRate: host.core.sampleRate, transpose: song.performanceTranspose ?? 0)
        c.setPattern(loop.events, loopSeconds: loop.seconds)
        if arpeggioPreview == nil { c.setPatternPlaying(true) }
        arpeggioPreview = ArpeggioPreview(songId: songId, sectionId: sectionId)
    }

    func stopArpeggioPreview() {
        if arpeggioPreview != nil { host?.controller.setPatternPlaying(false) }
        arpeggioPreview = nil
    }

    // MARK: Settings

    func setArpeggioStyle(_ styleId: String?, songId: UUID, sectionId: UUID) {
        editArpeggio(songId) { arp, song in
            guard let section = song.sections.first(where: { $0.id == sectionId }) else { return }
            var choices = arp.styleChoices ?? [:]
            // Repeats of the section (same group and type) share the choice.
            for s in song.sections where s.id == sectionId || (s.repetitionGroup != nil && s.repetitionGroup == section.repetitionGroup && s.type == section.type) {
                choices[s.id.uuidString] = styleId
            }
            arp.styleChoices = choices
        }
    }

    func selectArpeggioSection(_ id: UUID, songId: UUID) {
        arpeggioSectionId = id
        if arpeggioPreview?.songId == songId { startArpeggioPreview(songId: songId, sectionId: id) }
        refreshArpeggioLive()
    }

    func setArpeggioSound(_ id: UUID?, songId: UUID) { editArpeggio(songId) { arp, _ in arp.soundId = id } }
    func setArpeggioVolume(_ v: Double, songId: UUID) { editArpeggio(songId) { arp, _ in arp.volume = max(0, min(1, v)) } }
    func setArpeggioTempo(_ scale: Double, songId: UUID) { editArpeggio(songId) { arp, _ in arp.tempoScale = max(0.5, min(1.5, scale)) } }
    func setArpeggioSplit(_ note: Int, songId: UUID) { editArpeggio(songId) { arp, _ in arp.split = max(40, min(84, note)) } }

    private func editArpeggio(_ songId: UUID, _ change: (inout SongArpeggio, Song) -> Void) {
        guard var song = song(songId), var arp = song.arpeggio else { return }
        change(&arp, song)
        song.arpeggio = arp
        update(song)
        if let p = arpeggioPreview, p.songId == songId { startArpeggioPreview(songId: songId, sectionId: p.sectionId) }
        if activeSongId == songId { refreshArpeggioLive() }
    }
}
