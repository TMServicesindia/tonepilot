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
    /// - Parameter toneInstrument: loads candidate tones for `PartMatcher` (off the main thread);
    ///   with stems, each instrument part's nearest tone is measured and used by the arranger.
    /// - Parameter instruments: recognises the instruments heard per section (family → 0...1,
    ///   see `InstrumentEvidence`), e.g. Apple's on-device sound classifier in the app. The
    ///   arranger picks tones from what is actually played (brass, synth, flute…).
    public static func run(song input: Song, audio: AudioBuffer, stems: [StemInfo.Kind: AudioBuffer] = [:],
                           melodyOverride: MelodyTrack? = nil, patches: [InstrumentPatch],
                           progress: ((Double) -> Bool)? = nil,
                           instruments: (([SongSection]) -> [UUID: [String: Double]])? = nil,
                           toneInstrument: ((InstrumentPatch) -> LoadedInstrument?)? = nil) throws -> Output {
        var options = SongAnalyzer.Options()
        options.stems = stems
        options.extractMelody = melodyOverride == nil
        // Analysis to 85%, tone matching of the separated parts to 95%, arranging to 100%.
        let analysisShare = toneInstrument != nil && !stems.isEmpty ? 0.85 : 0.95
        var result = try SongAnalyzer.analyze(audio, options: options) { p in progress?(p * analysisShare) ?? true }
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
        // Reverse-engineer each instrument part: the nearest tone, EQ and reverb, measured.
        if let toneInstrument, !stems.isEmpty {
            let matches = PartMatcher.match(song: song, parts: stems, patches: patches, instrument: toneInstrument) { p in
                progress?(analysisShare + (0.95 - analysisShare) * p) ?? true
            }
            if !matches.isEmpty { song.partMatches = matches }
        }
        let arranged = AutoArranger.arrange(song, timbres: result.timbres, patches: patches)
        _ = progress?(1)
        return Output(song: arranged.song, result: result, arrangedSections: arranged.arranged)
    }
}
