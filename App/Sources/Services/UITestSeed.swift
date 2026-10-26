import AVFoundation
import Foundation
import TonePilotCore

/// Speed & crash tests (App/UITests) launch the app with `-TPUITest`: the setup wizard is
/// skipped and a generated demo song is added — 40 s of audio with sections, chords, beats,
/// four separated parts and Song Arpeggio patterns — so every screen has real content.
/// Never active in normal use.
enum UITestSeed {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-TPUITest") }
    static let title = "Demo Song"

    static func prepareDefaults() {
        guard enabled else { return }
        UserDefaults.standard.set(true, forKey: "hasCompletedSetup")
        UserDefaults.standard.set(true, forKey: "studioIntroDismissed")
        UserDefaults.standard.set(false, forKey: "autoSeparate")
    }

    @MainActor static func seed(_ model: AppModel) {
        guard enabled, !model.library.songs.contains(where: { $0.title == title }) else { return }
        let sr = 44_100.0, seconds = 40.0, bpm = 100.0
        let beat = 60 / bpm, bar = beat * 4
        let progression = ["C", "Am", "F", "G"]
        var song = Song(title: title, artist: "TonePilot tests", sourceType: .importedFile, sourceReference: "uitest-demo.wav",
                        userConfirmedRights: true, duration: seconds, analysisStatus: .completed)
        song.bpm = Estimate(bpm, confidence: 0.9, provenance: .algorithm)
        song.key = Estimate(MusicalKey(tonic: 0, mode: .major), confidence: 0.9, provenance: .algorithm)
        song.timeSignature = Estimate(4, confidence: 0.9, provenance: .algorithm)
        song.beatTimes = stride(from: 0.0, through: seconds, by: beat).map { $0 }
        song.chordEvents = stride(from: 0.0, to: seconds, by: bar).enumerated().map { i, t in
            ChordEvent(time: t, duration: bar, symbol: progression[i % 4], confidence: 0.9)
        }
        song.chordGuide = ChordGuide.build(chords: song.chordEvents, key: song.key?.value)
        let tone = Arrangement.starterFilmStack(name: "Main tone")
        song.arrangements = [tone]
        song.sections = [("Intro", SectionType.intro, 0.0, 9.6), ("Verse 1", .verse, 9.6, 24.0), ("Chorus", .chorus, 24.0, seconds)]
            .map { SongSection(type: $0.1, label: $0.0, startTime: $0.2, endTime: $0.3, confidence: 0.9, provenance: .algorithm, arrangementId: tone.id) }
        let pattern = ArpeggioPattern(beatsPerBar: 4, stepsPerBeat: 4,
                                      hits: [.init(step: 0, degree: .root, velocity: 1, length: 3), .init(step: 4, degree: .fifth, velocity: 0.7, length: 3),
                                             .init(step: 8, degree: .octave, velocity: 0.8, length: 3), .init(step: 12, degree: .third, velocity: 0.7, length: 3)],
                                      centerNote: 55, timingMatch: 0.9, positionMatch: 0.9, bars: 8)
        song.arpeggio = SongArpeggio(patterns: Dictionary(uniqueKeysWithValues: song.sections.map { ($0.id.uuidString, pattern) }), bpm: bpm)

        // Audio: a plucked chord per beat (music), bass roots, a kick, and a hummed melody.
        let n = Int(seconds * sr)
        var drums = [Float](repeating: 0, count: n), bass = drums, music = drums, vocals = drums
        let roots = ["C": 48.0, "Am": 45.0, "F": 41.0, "G": 43.0]
        func f(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }
        for i in 0..<n {
            let t = Double(i) / sr, tb = t.truncatingRemainder(dividingBy: beat)
            let chord = progression[Int(t / bar) % 4], root = roots[chord]!
            let third = chord == "Am" ? 3.0 : 4.0
            drums[i] = Float(0.5 * sin(2 * .pi * 55 * tb) * exp(-tb * 25))
            bass[i] = Float(0.25 * sin(2 * .pi * f(root - 12) * t))
            music[i] = Float(0.12 * (sin(2 * .pi * f(root + 12) * t) + sin(2 * .pi * f(root + 12 + third) * t) + sin(2 * .pi * f(root + 19) * t)) * exp(-tb * 4))
            vocals[i] = Float(0.15 * sin(2 * .pi * f(72 + Double(Int(t) % 5)) * t) * (t.truncatingRemainder(dividingBy: 4) < 3 ? 1 : 0))
        }
        let parts: [StemInfo.Kind: [Float]] = [.drums: drums, .bass: bass, .other: music, .vocals: vocals]
        let mix = (0..<n).map { i in (drums[i] + bass[i] + music[i] + vocals[i]) * 0.8 }
        do {
            try write(mix, sr: sr, to: model.store.audioDirectory.appendingPathComponent("uitest-demo.wav"))
            let dir = model.store.stemDirectory(for: song.id)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var stems: [StemInfo] = []
            for kind in [StemInfo.Kind.drums, .bass, .other, .vocals] {
                try write(parts[kind]!, sr: sr, to: dir.appendingPathComponent("\(kind.rawValue).wav"))
                stems.append(StemInfo(kind: kind, fileName: "\(kind.rawValue).wav", model: "demo"))
            }
            song.stems = stems
        } catch {
            model.engineError = "Test song couldn't be written: \(error.localizedDescription)"
        }
        model.update(song)
    }

    private static func write(_ samples: [Float], sr: Double, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        for i in samples.indices { buf.floatChannelData![0][i] = samples[i]; buf.floatChannelData![1][i] = samples[i] }
        buf.frameLength = AVAudioFrameCount(samples.count)
        try file.write(from: buf)
    }
}
