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
    public static func run(song input: Song, audio: AudioBuffer, stems: [StemInfo.Kind: AudioBuffer] = [:],
                           melodyOverride: MelodyTrack? = nil, patches: [InstrumentPatch],
                           progress: ((Double) -> Bool)? = nil) throws -> Output {
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
        let arranged = AutoArranger.arrange(song, timbres: result.timbres, patches: patches)
        _ = progress?(1)
        return Output(song: arranged.song, result: result, arrangedSections: arranged.arranged)
    }
}
