import XCTest
@testable import TonePilotCore

final class ListenSessionTests: XCTestCase {
    func feed(_ s: inout ListenSession, _ audio: [Float]) {
        var i = 0
        while i < audio.count { s.append(Array(audio[i..<min(audio.count, i + 4096)])); i += 4096 }
    }

    func testAutoStopsAfterSongEndsAndTrimsSilence() {
        var cfg = ListenSession.Config(); cfg.minSecondsBeforeAutoStop = 10; cfg.trailingSilenceSeconds = 3
        var s = ListenSession(config: cfg)
        let sr = Int(cfg.sampleRate)
        let silence = [Float](repeating: 0.0005, count: sr * 2)
        let song = SyntheticSong.render(pattern: ["A"], beatsPerSection: 32).samples // 16 s
        feed(&s, silence)
        feed(&s, song)
        XCTAssertFalse(s.shouldAutoStop, "still playing")
        feed(&s, [Float](repeating: 0.0005, count: sr * 4))
        XCTAssertTrue(s.shouldAutoStop, "song ended")
        let audio = s.finish()
        XCTAssertEqual(audio.duration, 16, accuracy: 0.6, "leading/trailing silence trimmed")
        XCTAssertTrue(s.samples.isEmpty, "memory released")
    }

    func testCapAndQuietDetection() {
        var cfg = ListenSession.Config(); cfg.maxSeconds = 5
        var s = ListenSession(config: cfg)
        feed(&s, [Float](repeating: 0, count: Int(cfg.sampleRate) * 4))
        XCTAssertTrue(s.isTooQuiet)
        feed(&s, [Float](repeating: 0.2, count: Int(cfg.sampleRate) * 4))
        XCTAssertEqual(s.elapsed, 5, accuracy: 0.01)
        XCTAssertTrue(s.isFull)
        XCTAssertTrue(s.shouldAutoStop)
    }

    func testCapturedAudioRunsThroughPipeline() throws {
        // Simulate a room capture: song + noise + reduced level.
        var s = ListenSession()
        var rng: UInt64 = 7
        let song = SyntheticSong.render(pattern: ["A", "B", "A", "B"], beatsPerSection: 32).samples.map { x -> Float in
            rng = rng &* 6364136223846793005 &+ 1
            return x * 0.4 + Float(Int64(bitPattern: rng >> 11) % 1000) / 1_000_000
        }
        feed(&s, song)
        let out = try SongPipeline.run(song: Song(title: "Listened", sourceType: .listened, userConfirmedRights: true),
                                       audio: s.finish(), patches: FactoryPatches.all)
        XCTAssertEqual(out.song.analysisStatus, .completed)
        XCTAssertEqual(out.song.bpm?.value ?? 0, 120, accuracy: 3)
        XCTAssertGreaterThanOrEqual(out.song.sections.count, 3)
        XCTAssertTrue(out.song.sections.allSatisfy { out.song.arrangement(for: $0) != nil })
    }
}
