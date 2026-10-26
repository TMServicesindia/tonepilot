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

    /// Arms or disarms live fill-in for the open song (call when the song, tone or settings change).
    func refreshArpeggioLive() {
        guard let song = song(activeSongId), let arp = song.arpeggio, arp.liveFill == true, let section = arpeggioSection(song),
              let pattern = arp.playable(for: section.id) else {
            arpeggioLiveFlag.withLock { $0 = false }
            arpeggioFollower = nil
            arpeggioLiveChord = nil
            return
        }
        loadArpeggioSound(arp)
        arpeggioFollower = ArpeggioFollower(pattern: pattern, bpm: arp.effectiveBPM, split: arp.effectiveSplit,
                                            quality: ArpeggioFollower.songQuality(chords: song.chordEvents, key: song.key?.value))
        arpeggioFollowerSection = section.id
        arpeggioLiveFlag.withLock { $0 = true }
    }

    /// A note from the Casio (main thread, with the time it arrived on the MIDI thread).
    func arpeggioNote(_ note: Int, at time: Double) {
        guard let host, let song = song(activeSongId) else { return }
        // Follow the section the song is in (or the one chosen while paused).
        if let section = arpeggioSection(song), section.id != arpeggioFollowerSection { refreshArpeggioLive() }
        guard var follower = arpeggioFollower else { return }
        let fill = follower.noteOn(note, at: time)
        arpeggioFollower = follower
        guard let fill else { return }
        let sr = host.core.sampleRate, h = host.controller.accompanimentHandle(.arpeggio)
        let last = Int64(fill.barSeconds * sr) - 1
        var events: [SequencerEvent] = []
        for n in fill.notes where (0...127).contains(n.note) {
            let on = Int64(n.time * sr), off = min(last, Int64((n.time + max(0.05, n.length)) * sr))
            guard off > on else { continue }
            events.append(SequencerEvent(frame: on, handle: h, note: UInt8(n.note), velocity: UInt8(max(1, min(127, 30 + 90 * n.velocity)))))
            events.append(SequencerEvent(frame: off, handle: h, note: UInt8(n.note), velocity: 0))
        }
        host.controller.setPattern(events, loopSeconds: fill.barSeconds)
        host.controller.playPatternOnce(elapsed: CACurrentMediaTime() - fill.barStart)
        arpeggioLiveChord = "\(NoteName.sharpNames[fill.chord.root]) \(fill.chord.quality == .minor ? "minor" : "major")"
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
