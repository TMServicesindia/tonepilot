import Foundation
import TonePilotCore

/// Which pattern the Song Arpeggio preview is playing.
struct ArpeggioPreview: Equatable {
    let songId: UUID
    let sectionId: UUID
}

/// Song Arpeggio, step 1: each section's learned broken-chord pattern, previewed on the song's
/// own chords on the engine's pattern clock — never tied to the song player.
extension AppModel {
    func arpeggioSections(_ song: Song) -> [SongSection] {
        song.orderedSections.filter { song.arpeggio?.pattern(for: $0.id) != nil }
    }

    /// Plays (or replaces) the preview of a section's pattern.
    func startArpeggioPreview(songId: UUID, sectionId: UUID) {
        guard let host, let song = song(songId), let arp = song.arpeggio,
              let section = song.sections.first(where: { $0.id == sectionId }), let pattern = arp.pattern(for: sectionId) else { return }
        let c = host.controller
        if let error = c.setAccompaniment(.arpeggio, patch: library.patch(id: arp.effectiveSoundId), volume: arp.effectiveVolume, cache: cache) {
            engineError = error
        }
        let bpm = arp.effectiveBPM
        let bars = ArpeggioRenderer.bars(of: section, in: song, pattern: pattern, bpm: arp.bpm)
        let loop = ArpeggioRenderer.loop(pattern, bars: bars, bpm: bpm, handle: c.accompanimentHandle(.arpeggio),
                                         sampleRate: host.core.sampleRate, transpose: song.performanceTranspose ?? 0)
        c.setPattern(loop.events, loopSeconds: loop.seconds)
        if arpeggioPreview == nil { c.setPatternPlaying(true) }
        arpeggioPreview = ArpeggioPreview(songId: songId, sectionId: sectionId)
    }

    func stopArpeggioPreview() {
        host?.controller.setPatternPlaying(false)
        arpeggioPreview = nil
    }

    /// Tap-to-correct one step; applies to every section sharing the pattern (repeats of it).
    func cycleArpeggioStep(_ step: Int, songId: UUID, sectionId: UUID) {
        editArpeggio(songId) { arp, song in
            guard var p = arp.pattern(for: sectionId), let section = song.sections.first(where: { $0.id == sectionId }) else { return }
            p.cycleStep(step)
            for s in song.sections where s.id == sectionId || (s.repetitionGroup != nil && s.repetitionGroup == section.repetitionGroup && s.type == section.type) {
                arp.patterns[s.id.uuidString] = p
            }
        }
    }

    func setArpeggioSound(_ id: UUID, songId: UUID) { editArpeggio(songId) { arp, _ in arp.soundId = id } }
    func setArpeggioVolume(_ v: Double, songId: UUID) { editArpeggio(songId) { arp, _ in arp.volume = max(0, min(1, v)) } }
    func setArpeggioTempo(_ scale: Double, songId: UUID) { editArpeggio(songId) { arp, _ in arp.tempoScale = max(0.5, min(1.5, scale)) } }

    private func editArpeggio(_ songId: UUID, _ change: (inout SongArpeggio, Song) -> Void) {
        guard var song = song(songId), var arp = song.arpeggio else { return }
        change(&arp, song)
        song.arpeggio = arp
        update(song)
        if let p = arpeggioPreview, p.songId == songId { startArpeggioPreview(songId: songId, sectionId: p.sectionId) }
    }
}
