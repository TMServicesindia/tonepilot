import Foundation
import XCTest
@testable import TonePilotCore
@testable import TonePilotBridge

/// Phase 1 equivalence: the shared SongImportPipeline produces the same output as the previous
/// orchestration (and as the fixtures recorded before the migration), on both call paths.
final class PipelineEquivalenceTests: XCTestCase {
    override func tearDown() { ImportPipelineFlags.useSharedPipeline = true }

    func testSharedPipelineMatchesPreviousFlowAndRecordedFixtures() throws {
        for c in PipelineFixtures.cases() {
            let previous = try PipelineFixtures.normalise(PipelineFixtures.legacyRun(c))
            let instruments = c.instruments
            let shared = try SongImportPipeline.run(
                .init(song: c.song, audio: c.audio, stems: c.stems, melodyOverride: c.melodyOverride, listened: c.listened,
                      stemInfos: c.stemInfos, patches: FactoryPatches.all),
                hooks: .init(progress: { _ in true },
                             instruments: instruments.map { inst in { sections in Dictionary(uniqueKeysWithValues: sections.map { ($0.id, inst) }) } },
                             toneInstrument: c.toneMatching ? PipelineFixtures.synthLoader : nil)).song
            let sharedNorm = try PipelineFixtures.normalise(shared)
            XCTAssertNil(PipelineFixtures.diff(previous, sharedNorm, tol: 0), "\(c.name): shared pipeline differs from the previous flow")
            let stored = try JSONSerialization.jsonObject(with: Data(contentsOf: PipelineFixtures.dir.appendingPathComponent("\(c.name).json")))
            XCTAssertNil(PipelineFixtures.diff(stored, sharedNorm), "\(c.name): shared pipeline differs from the recorded fixture")
        }
    }

    /// Android bridge, real call path (Listen Mode → analyze): identical songs with the shared
    /// pipeline and with the previous orchestration.
    func testAndroidBridgeGivesTheSameSongEitherWay() throws {
        let audio = SyntheticSong.render(pattern: ["A", "B", "A", "B"], beatsPerSection: 32)
        func run(shared: Bool) throws -> Any {
            ImportPipelineFlags.useSharedPipeline = shared
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("tp-eq-\(UUID().uuidString)")
            let core = try AppCore(rootDirectory: root, sampleRate: 48_000)
            defer { try? FileManager.default.removeItem(at: root) }
            core.listenBegin()
            audio.samples.withUnsafeBufferPointer { core.listenAppend($0, sampleRate: audio.sampleRate) }
            let id = try XCTUnwrap(core.listenFinish(title: "Equivalence", link: nil))
            let song = try XCTUnwrap(core.song(id))
            XCTAssertEqual(song.analysisStatus, .completed)
            return try PipelineFixtures.normalise(song)
        }
        let previous = try run(shared: false), shared = try run(shared: true)
        XCTAssertNil(PipelineFixtures.diff(previous, shared, tol: 0), "Android bridge differs between orchestrations")
    }
}
