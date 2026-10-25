import XCTest
@testable import TonePilotCore

final class AnalysisServerTests: XCTestCase {
    /// Melody JSON produced by the real server (Basic Pitch 0.4.0 + overtone cleanup) on a test tune.
    static let serverMelodyJSON = #"{"notes": [{"id": "4198A843-A481-4E83-94AF-8F25F8E2E49B", "start": 0.1858, "duration": 0.5341, "midi": 64, "bendCents": [], "confidence": 0.975, "isOrnamented": false, "userEdited": false}, {"id": "5EDC60C4-558D-47AF-A0B1-7DCA4B9EE444", "start": 0.7895, "duration": 0.5341, "midi": 67, "bendCents": [], "confidence": 0.995, "isOrnamented": false, "userEdited": false}, {"id": "F6DC2C99-018F-4057-B61D-07F93749532E", "start": 1.3932, "duration": 0.5457, "midi": 69, "bendCents": [], "confidence": 0.981, "isOrnamented": false, "userEdited": false}, {"id": "CB4B7C2D-E849-44E5-BD3F-4D1886465057", "start": 1.9866, "duration": 0.743, "midi": 72, "bendCents": [], "confidence": 1.0, "isOrnamented": false, "userEdited": false}], "source": "vocalStem", "voicedRatio": 0.927, "difficultPhrases": []}"#

    func testServerMelodyDecodesIntoMelodyTrack() throws {
        let json = #"{"stems":[{"kind":"vocals","url":"/v1/jobs/x/stems/vocals.wav","model":"htdemucs"}],"melody":"# + Self.serverMelodyJSON + #","models":[{"name":"Demucs","license":"MIT","url":"https://github.com/adefossez/demucs"}],"retentionHours":24,"notes":["n"]}"#
        let result = try AnalysisServerClient.decodeResult(Data(json.utf8))
        XCTAssertEqual(result.melody?.notes.map(\.midi), [64, 67, 69, 72])
        XCTAssertEqual(result.melody?.source, .vocalStem)
        XCTAssertEqual(result.stems.first?.kind, "vocals")
    }

    func testClientRequiresConfigurationAndConsent() async throws {
        XCTAssertNil(AnalysisServerClient(settings: AnalysisServerSettings(enabled: false, baseURL: "http://x"), token: nil))
        XCTAssertNil(AnalysisServerClient(settings: AnalysisServerSettings(enabled: true, baseURL: "ftp://x"), token: nil))
        let c = try XCTUnwrap(AnalysisServerClient(settings: AnalysisServerSettings(enabled: true, baseURL: "http://127.0.0.1:1"), token: nil))
        do {
            _ = try await c.submit(audioFile: URL(fileURLWithPath: "/nonexistent"), consent: false, model: "htdemucs", transcribeVocals: true)
            XCTFail("must refuse without consent")
        } catch { XCTAssertEqual(error as? AnalysisServerError, .consentRequired) }
    }

    /// Live round trip against `python -m tests.dev_server` (set TONEPILOT_SERVER_URL).
    func testLiveServerRoundTrip() async throws {
        guard let base = ProcessInfo.processInfo.environment["TONEPILOT_SERVER_URL"] else { throw XCTSkip("no server") }
        let client = try XCTUnwrap(AnalysisServerClient(settings: AnalysisServerSettings(enabled: true, baseURL: base), token: "dev-token"))
        let health = try await client.health()
        XCTAssertTrue(health.basicPitch)
        XCTAssertTrue(health.authRequired)

        // Render the test tune as WAV and upload it.
        let sr = 22_050
        let tune: [(Int, Double, Double)] = [(64, 0.2, 0.5), (67, 0.8, 0.5), (69, 1.4, 0.5), (72, 2.0, 0.7)]
        var frames = [Float](repeating: 0, count: sr * 3)
        for (m, s, d) in tune {
            let f = 440 * pow(2, Double(m - 69) / 12)
            for i in Int(s * Double(sr))..<Int((s + d) * Double(sr)) {
                let t = Double(i) / Double(sr)
                var v = 0.0
                for h in 1...4 { v += sin(2 * Double.pi * f * Double(h) * t) / Double(h) }
                frames[i] += Float(v * 0.2)
            }
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tune-\(UUID().uuidString).wav")
        try WAVDecoder.encode16(frames, sampleRate: sr).write(to: file)
        let job = try await client.submit(audioFile: file, consent: true, model: "htdemucs", transcribeVocals: true)
        let result = try await client.waitForResult(job: job, timeout: 300)
        XCTAssertEqual(result.melody?.notes.map(\.midi), [64, 67, 69, 72])
        let stemDir = FileManager.default.temporaryDirectory.appendingPathComponent("stems-\(job)")
        let vocal = try await client.downloadStem(result.stems.first { $0.kind == "vocals" }!, to: stemDir)
        let decoded = try WAVDecoder.decodeMono(url: vocal)
        XCTAssertEqual(decoded.frames.count, frames.count)
        try await client.delete(job: job)
        do { _ = try await client.status(job: job); XCTFail("deleted") } catch {
            guard case AnalysisServerError.http(404, _) = error else { return XCTFail("\(error)") }
        }
    }
}
