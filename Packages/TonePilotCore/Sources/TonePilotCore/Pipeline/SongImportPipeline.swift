import Foundation

/// The shared import → analyse → arrange step that the iOS app (`AppModel`) and the Android
/// bridge (`AppCore`) both run, moved into the core so it lands once on both platforms.
///
/// Behaviour-preserving (Phase 1): it performs exactly what the two orchestrators did, in the
/// same order — a song captured by Listen Mode gets the assisted/timer switching default, then
/// `SongPipeline.run` with the platform's hooks, then freshly separated parts replace the song's
/// stem records. Decoding, separation, server upload, progress text and UI updates stay in the
/// platform code. The previous orchestration remains available (`ImportPipelineFlags`) until
/// output equivalence has been shown on both platforms.
public enum SongImportPipeline {
    public struct Request {
        public var song: Song
        public var audio: AudioBuffer
        /// Separated parts decoded at the analysis rate (empty: analyse from the mix).
        public var stems: [StemInfo.Kind: AudioBuffer]
        /// A better melody from elsewhere (e.g. the analysis server's vocal transcription).
        public var melodyOverride: MelodyTrack?
        /// Captured by Listen Mode (microphone).
        public var listened: Bool
        /// Records of parts separated for this analysis; replace `song.stems` when not empty.
        public var stemInfos: [StemInfo]
        public var patches: [InstrumentPatch]

        public init(song: Song, audio: AudioBuffer, stems: [StemInfo.Kind: AudioBuffer] = [:], melodyOverride: MelodyTrack? = nil,
                    listened: Bool = false, stemInfos: [StemInfo] = [], patches: [InstrumentPatch]) {
            self.song = song
            self.audio = audio
            self.stems = stems
            self.melodyOverride = melodyOverride
            self.listened = listened
            self.stemInfos = stemInfos
            self.patches = patches
        }
    }

    /// Platform hooks (all optional): progress 0...1 (return false to cancel), instrument
    /// recognition per section, and a loader for tone matching.
    public struct Hooks {
        public var progress: ((Double) -> Bool)?
        public var instruments: (([SongSection]) -> [UUID: [String: Double]])?
        public var toneInstrument: ((InstrumentPatch) -> LoadedInstrument?)?

        public init(progress: ((Double) -> Bool)? = nil,
                    instruments: (([SongSection]) -> [UUID: [String: Double]])? = nil,
                    toneInstrument: ((InstrumentPatch) -> LoadedInstrument?)? = nil) {
            self.progress = progress
            self.instruments = instruments
            self.toneInstrument = toneInstrument
        }
    }

    public static func run(_ request: Request, hooks: Hooks = Hooks()) throws -> SongPipeline.Output {
        var input = request.song
        if request.listened, input.switching == nil { input.switching = SwitchingSettings(mode: .assisted, reference: .timer) }
        var output = try SongPipeline.run(song: input, audio: request.audio, stems: request.stems,
                                          melodyOverride: request.melodyOverride, patches: request.patches,
                                          progress: hooks.progress, instruments: hooks.instruments,
                                          toneInstrument: hooks.toneInstrument)
        if !request.stemInfos.isEmpty { output.song.stems = request.stemInfos }
        return output
    }
}

/// Which import orchestration runs. The shared pipeline is the default once fixtures show equal
/// outputs; the previous per-platform code stays selectable as a fallback during Phase 1.
public enum ImportPipelineFlags {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var shared = true

    public static var useSharedPipeline: Bool {
        get { lock.withLock { shared } }
        set { lock.withLock { shared = newValue } }
    }
}
