import Foundation

/// The one-click workflow: analyse authorised audio, store results without clobbering user
/// corrections, and auto-arrange every section. Returns a ready-to-play song.
public enum SongPipeline {
    public struct Output: Sendable {
        public var song: Song
        public var result: SongAnalysisResult
        public var arrangedSections: [UUID]
    }

    /// - Parameter melodyOverride: a better melody from elsewhere (e.g. Basic Pitch on the server's
    ///   vocal stem). It replaces the on-device estimate before arranging, since the melody drives
    ///   lead choice and the keyboard split.
    /// - Parameter instruments: recognises the instruments heard per section (family → 0...1,
    ///   see `InstrumentEvidence`), e.g. Apple's on-device sound classifier in the app. The
    ///   arranger picks tones from what is actually played (brass, synth, flute…).
    public static func run(song input: Song, audio: AudioBuffer, stems: [StemInfo.Kind: AudioBuffer] = [:],
                           melodyOverride: MelodyTrack? = nil, patches: [InstrumentPatch],
                           progress: ((Double) -> Bool)? = nil,
                           instruments: (([SongSection]) -> [UUID: [String: Double]])? = nil) throws -> Output {
        var options = SongAnalyzer.Options()
        options.stems = stems
        options.extractMelody = melodyOverride == nil
        var result = try SongAnalyzer.analyze(audio, options: options) { p in progress?(p * 0.95) ?? true }
        if var m = melodyOverride {
            if m.difficultPhrases.isEmpty { m.difficultPhrases = MelodyExtractor.difficultPhrases(m.notes) }
            result.melody = m
            result = SongAnalyzer.refreshLeadActivity(result)
        }
        var song = input
        song.apply(result)
        if song.switching == nil { song.switching = SwitchingSettings() }
        if song.accompaniment == nil { song.accompaniment = AccompanimentSettings() }
        if let instruments {
            let heard = instruments(song.sections)
            for i in song.sections.indices { if let h = heard[song.sections[i].id], !h.isEmpty { song.sections[i].instruments = h } }
        }
        let arranged = AutoArranger.arrange(song, timbres: result.timbres, patches: patches)
        _ = progress?(1)
        return Output(song: arranged.song, result: result, arrangedSections: arranged.arranged)
    }
}
