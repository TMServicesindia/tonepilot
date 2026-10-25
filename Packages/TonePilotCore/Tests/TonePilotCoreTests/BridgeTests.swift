import XCTest
@testable import TonePilotBridge
@testable import TonePilotCore

/// The JSON/C facade used by the Android app.
final class BridgeTests: XCTestCase {
    private func makeCore() throws -> (AppCore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-\(UUID().uuidString)")
        let sf = root.appendingPathComponent("SoundFonts", isDirectory: true)
        try FileManager.default.createDirectory(at: sf, withIntermediateDirectories: true)
        // A one-preset test bank stands in for GeneralUser GS (bank 0 program 0 = Grand Piano).
        try TestSoundFont.make().write(to: sf.appendingPathComponent(FactoryPatches.defaultSoundFontFile))
        return (try AppCore(rootDirectory: root, sampleRate: 48_000), root)
    }

    private func call(_ core: AppCore, _ object: [String: Any]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: object)
        let out = core.call(String(data: data, encoding: .utf8)!)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any], out)
    }

    private func waitForSoundFont(_ core: AppCore) throws {
        for _ in 0..<100 {
            if (try call(core, ["cmd": "state"]))["soundFontReady"] as? Bool == true { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTFail("sound font never loaded")
    }

    private func peak(_ core: AppCore, frames: Int = 4800) -> Float {
        var l = [Float](repeating: 0, count: frames), r = l
        l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
            core.render(frames: frames, left: lp.baseAddress!, right: rp.baseAddress!)
        } }
        return zip(l, r).map { max(abs($0), abs($1)) }.max() ?? 0
    }

    func testKeyboardPlaysTheSelectedToneThroughRawMIDIBytes() throws {
        let (core, _) = try makeCore()
        try waitForSoundFont(core)
        let state = try call(core, ["cmd": "state"])
        XCTAssertEqual(state["toneName"] as? String, "Grand Piano", "keyboard is never silent on first launch")
        XCTAssertLessThan(peak(core), 0.0001)

        core.midi([0x90, 69, 100])                  // note on A4
        XCTAssertGreaterThan(peak(core), 0.01)
        core.midi([0x80, 69, 0])                    // note off
        for _ in 0..<40 { _ = peak(core) }          // release tail
        XCTAssertLessThan(peak(core), 0.001)
        let log = try call(core, ["cmd": "state"])["midiLog"] as? [String] ?? []
        XCTAssertTrue(log.contains { $0.contains("Note On") }, "\(log)")

        // Large host buffers (more than the engine block) are split, not truncated.
        core.midi([0x90, 60, 100])
        XCTAssertGreaterThan(peak(core, frames: 10_000), 0.01)
        _ = try call(core, ["cmd": "panic"])
    }

    func testToneListAndSelection() throws {
        let (core, root) = try makeCore()
        let tones = try call(core, ["cmd": "tones", "search": "strings"])
        let groups = try XCTUnwrap(tones["groups"] as? [[String: Any]])
        let entries = groups.flatMap { $0["entries"] as? [[String: Any]] ?? [] }
        let strings = try XCTUnwrap(entries.first { ($0["name"] as? String)?.contains("Strings") == true })
        XCTAssertEqual(try call(core, ["cmd": "activateTone", "id": strings["id"]!])["ok"] as? Bool, true)
        XCTAssertEqual(try call(core, ["cmd": "state"])["toneName"] as? String, strings["name"] as? String)

        // Edits to a factory instrument go to a copy in My Tones.
        _ = try call(core, ["cmd": "editLayer", "index": 0, "volume": 0.5, "octave": 1])
        let state = try call(core, ["cmd": "state"])
        XCTAssertTrue((state["toneName"] as? String)?.hasSuffix("(edited)") == true)
        let layer = try XCTUnwrap((state["layers"] as? [[String: Any]])?.first)
        XCTAssertEqual(layer["octave"] as? Int, 1)
        let mine = try call(core, ["cmd": "tones", "search": ""])["groups"] as? [[String: Any]]
        XCTAssertEqual((mine?.first { $0["kind"] as? String == "mine" }?["entries"] as? [Any])?.count, 1)

        // Last tone is restored on the next launch.
        _ = try call(core, ["cmd": "flush"])
        let again = try AppCore(rootDirectory: root, sampleRate: 48_000)
        XCTAssertEqual(try call(again, ["cmd": "state"])["toneName"] as? String, state["toneName"] as? String)
    }

    func testImportAnalyseAndPlayFlow() throws {
        let (core, _) = try makeCore()
        let audio = PipelineTests.songWithMelody()
        // The platform copies the file into the audio folder; a WAV stands in for the MP3.
        let audioDir = core.store.audioDirectory
        try WAVDecoder.encode16(audio.samples, sampleRate: Int(audio.sampleRate)).write(to: audioDir.appendingPathComponent("song.wav"))
        let imported = try call(core, ["cmd": "importSong", "fileName": "song.wav", "originalName": "My Song.mp3", "duration": audio.duration])
        let id = try XCTUnwrap(imported["id"] as? String)
        var listed = try call(core, ["cmd": "library"])["songs"] as? [[String: Any]]
        XCTAssertEqual(listed?.first?["title"] as? String, "My Song")
        XCTAssertEqual(listed?.first?["status"] as? String, "running")

        // Decoded PCM arrives in chunks at the file's native rate (here 2× the analysis rate).
        let upsampled = audio.samples.flatMap { [$0, $0] }
        _ = try call(core, ["cmd": "pcmBegin", "key": id, "sampleRate": audio.sampleRate * 2])
        stride(from: 0, to: upsampled.count, by: 8192).forEach { i in
            let chunk = Array(upsampled[i..<min(i + 8192, upsampled.count)])
            chunk.withUnsafeBufferPointer { core.pcmAppend(key: id, $0) }
        }
        _ = try call(core, ["cmd": "analyze", "id": id])

        let song = try call(core, ["cmd": "song", "id": id])
        XCTAssertEqual(song["status"] as? String, "completed", "\(song["error"] ?? "")")
        let sections = try XCTUnwrap(song["sections"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(sections.count, 3)
        XCTAssertFalse((sections[0]["toneName"] as? String ?? "").isEmpty)
        XCTAssertFalse((song["overview"] as? [[String]] ?? []).isEmpty)
        listed = try call(core, ["cmd": "library"])["songs"] as? [[String: Any]]
        XCTAssertNotNil(listed?.first?["bpm"])

        let guide = try call(core, ["cmd": "sectionGuide", "songId": id, "sectionId": sections[0]["id"]!])
        XCTAssertFalse((guide["leftHandPattern"] as? String ?? "").isEmpty)
        XCTAssertEqual(guide["nextId"] as? String, sections[1]["id"] as? String)

        // Play: automatic switching follows the backing track position.
        _ = try call(core, ["cmd": "startPerformance", "id": id])
        _ = try call(core, ["cmd": "setSwitching", "songId": id, "mode": "automatic", "reference": "backingTrack"])
        let second = try XCTUnwrap(sections[1]["start"] as? Double)
        _ = try call(core, ["cmd": "tick", "time": second + 0.5, "rate": 1])
        let state = try call(core, ["cmd": "state"])
        XCTAssertEqual(state["sectionId"] as? String, sections[1]["id"] as? String)
        XCTAssertEqual(state["switchMode"] as? String, "automatic")
        let live = try call(core, ["cmd": "liveGuide"])
        XCTAssertEqual(live["available"] as? Bool, true)
        XCTAssertNotNil(live["pattern"], "\(live)")

        // Corrections.
        _ = try call(core, ["cmd": "setBPM", "songId": id, "value": 121])
        XCTAssertEqual((try call(core, ["cmd": "song", "id": id])["bpm"] as? [String: Any])?["text"] as? String, "121 BPM")
        _ = try call(core, ["cmd": "deleteSong", "id": id])
        XCTAssertEqual((try call(core, ["cmd": "library"])["songs"] as? [Any])?.count, 0)
    }

    func testUnreadableAudioFailsWithAShortMessage() throws {
        let (core, _) = try makeCore()
        try Data("not audio".utf8).write(to: core.store.audioDirectory.appendingPathComponent("bad.mp3"))
        let id = try XCTUnwrap(try call(core, ["cmd": "importSong", "fileName": "bad.mp3", "originalName": "bad.mp3"])["id"] as? String)
        _ = try call(core, ["cmd": "analyze", "id": id])   // no PCM decoded
        let song = try call(core, ["cmd": "song", "id": id])
        XCTAssertEqual(song["status"] as? String, "failed")
        XCTAssertTrue((song["error"] as? String ?? "").contains("couldn't be read"))
    }

    func testResamplerKeepsPitchAndLength() {
        let rate = 44_100.0
        let tone = (0..<44_100).map { Float(sin(2 * Double.pi * 440 * Double($0) / rate)) }
        let out = Resampler.resample(tone, from: rate, to: 22_050)
        XCTAssertEqual(out.count, 22_050)
        // Zero crossings per second ≈ 2 × 440.
        let crossings = zip(out, out.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        XCTAssertEqual(Double(crossings), 440, accuracy: 3)
        XCTAssertGreaterThan(out.map(abs).max() ?? 0, 0.8, "440 Hz passes the anti-alias filter")
    }
}
