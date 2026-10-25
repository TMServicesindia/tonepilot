import XCTest
@testable import TonePilotCore

final class ModelAndPersistenceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TonePilotTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func sampleLibrary() -> Library {
        let arrangement = Arrangement.starterFilmStack()
        let song = Song(title: "Test Song", artist: "Composer", film: "Film", language: "Tamil", tags: ["melody"],
                        sourceType: .importedFile, sourceReference: "test.mp3", userConfirmedRights: true,
                        duration: 200, bpm: .user(96), key: Estimate(MusicalKey(tonic: 9, mode: .minor), confidence: 0.6, provenance: .algorithm),
                        sections: [SongSection(type: .intro, startTime: 0, endTime: 20, arrangementId: arrangement.id),
                                   SongSection(type: .chorus, startTime: 20, endTime: 60, arrangementId: arrangement.id)],
                        arrangements: [arrangement])
        var lib = Library(songs: [song], playlists: [Playlist(name: "Gig", songIds: [song.id])])
        lib.mergeFactoryPatches(FactoryPatches.all)
        return lib
    }

    func testLibraryRoundTripsThroughJSON() throws {
        let lib = sampleLibrary()
        let decoded = try LibraryCodec.decode(LibraryCodec.encode(lib))
        XCTAssertEqual(decoded.songs, lib.songs)
        XCTAssertEqual(decoded.patches, lib.patches)
        XCTAssertEqual(decoded.playlists, lib.playlists)
        XCTAssertEqual(decoded.schemaVersion, Library.currentSchemaVersion)
    }

    func testMigratesVersion1Library() throws {
        let v1 = """
        {"songs":[{"id":"\(UUID().uuidString)","title":"Old","sourceType":"manual","userConfirmedRights":false,
          "analysisStatus":"notStarted","chordEvents":[],"sections":[],"arrangements":[],"isFavorite":false,
          "createdAt":"2025-01-01T00:00:00Z","updatedAt":"2025-01-01T00:00:00Z"}],
         "patches":[]}
        """
        let lib = try LibraryCodec.decode(Data(v1.utf8))
        XCTAssertEqual(lib.songs.first?.title, "Old")
        XCTAssertEqual(lib.songs.first?.beatTimes, [])
        XCTAssertEqual(lib.songs.first?.tags, [])
        XCTAssertEqual(lib.schemaVersion, Library.currentSchemaVersion)
    }

    func testRejectsFutureSchema() {
        let data = Data(#"{"schemaVersion":99,"songs":[],"patches":[]}"#.utf8)
        XCTAssertThrowsError(try LibraryCodec.decode(data)) { error in
            XCTAssertEqual(error as? LibraryStoreError, .unsupportedFutureSchema(99))
        }
    }

    func testStoreSavesLoadsAndRecoversFromCorruptFile() throws {
        let store = try LibraryStore(rootDirectory: tempDir)
        XCTAssertEqual(try store.load().songs.count, 0)
        let lib = sampleLibrary()
        try store.save(lib)
        try store.save(lib) // second save creates the backup
        XCTAssertEqual(try store.load().songs, lib.songs)

        try Data("{ not json".utf8).write(to: store.libraryURL)
        XCTAssertEqual(try store.load().songs.map(\.title), ["Test Song"], "should fall back to backup")
    }

    func testImportFileAvoidsNameCollisions() throws {
        let store = try LibraryStore(rootDirectory: tempDir)
        let src = tempDir.appendingPathComponent("song.mp3")
        try Data([1, 2, 3]).write(to: src)
        XCTAssertEqual(try store.importFile(from: src, into: store.audioDirectory), "song.mp3")
        XCTAssertEqual(try store.importFile(from: src, into: store.audioDirectory), "song 2.mp3")
    }

    func testSearchMatchesTagsAndMetadata() {
        let lib = sampleLibrary()
        XCTAssertEqual(lib.searchSongs("tamil").count, 1)
        XCTAssertEqual(lib.searchSongs("MELODY").count, 1)
        XCTAssertEqual(lib.searchSongs("hindi").count, 0)
        XCTAssertEqual(lib.searchSongs("  ").count, 1)
    }

    func testDeleteSongRemovesFromPlaylists() {
        var lib = sampleLibrary()
        lib.deleteSong(id: lib.songs[0].id)
        XCTAssertTrue(lib.songs.isEmpty)
        XCTAssertTrue(lib.playlists[0].songIds.isEmpty)
    }

    func testFactoryPatchIdsAreStableAndUnique() {
        XCTAssertEqual(FactoryPatches.id(forProgram: 0), FactoryPatches.id(forProgram: 0))
        XCTAssertEqual(Set(FactoryPatches.all.map(\.id)).count, FactoryPatches.all.count)
        var lib = Library()
        lib.mergeFactoryPatches(FactoryPatches.all)
        lib.mergeFactoryPatches(FactoryPatches.all)
        XCTAssertEqual(lib.patches.count, FactoryPatches.all.count)
    }

    func testAudibleLayersHonourMuteSoloAndEnable() {
        let a = Layer(patchId: UUID()), b = Layer(patchId: UUID(), muted: true), c = Layer(patchId: UUID(), enabled: false)
        var arr = Arrangement(name: "x", layers: [a, b, c])
        XCTAssertEqual(arr.audibleLayers.map(\.id), [a.id])
        arr.layers[1].solo = true
        XCTAssertEqual(arr.audibleLayers.map(\.id), [b.id], "solo overrides mute")
        arr.layers[2].solo = true
        XCTAssertEqual(arr.audibleLayers.map(\.id), [b.id], "disabled layers never sound")
    }

    func testLayerClampsParameters() {
        let l = Layer(patchId: UUID(), volume: 3, pan: -5, octave: 9, transpose: -40)
        XCTAssertEqual(l.volume, 1)
        XCTAssertEqual(l.pan, -1)
        XCTAssertEqual(l.octave, 3)
        XCTAssertEqual(l.transpose, -12)
        XCTAssertEqual(l.semitoneOffset, 24)
    }

    func testGainStagingAddsHeadroomForStacks() {
        let arr = Arrangement.starterFilmStack()
        let total = arr.audibleLayers.map { GainStaging.effectiveGain(layer: $0, in: arr) }.reduce(0, +)
        let naive = arr.audibleLayers.map { $0.volume * arr.masterGain }.reduce(0, +)
        XCTAssertLessThan(total, naive)
    }

    // MARK: Section editing

    func testSplitMergeResize() throws {
        let s = SongSection(type: .verse, startTime: 10, endTime: 30, confidence: 0.3, provenance: .algorithm)
        var list = try SectionEditor.split([s], id: s.id, at: 20)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].endTime, 20)
        XCTAssertEqual(list[1].startTime, 20)
        XCTAssertEqual(list[0].provenance, .user)

        XCTAssertThrowsError(try SectionEditor.split(list, id: list[0].id, at: 10.1))

        list = try SectionEditor.merge(list, list[1].id, list[0].id)
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].startTime, 10)
        XCTAssertEqual(list[0].endTime, 30)

        let next = SongSection(type: .chorus, startTime: 30, endTime: 50)
        list = try SectionEditor.resize(list + [next], id: list[0].id, start: 5, end: 35, songDuration: 60)
        XCTAssertEqual(list[0].startTime, 5)
        XCTAssertEqual(list[1].startTime, 35, "neighbour pushed so sections never overlap")
        XCTAssertThrowsError(try SectionEditor.resize(list, id: list[0].id, start: 5, end: 49.9, songDuration: 60))
        XCTAssertEqual(SectionEditor.section(at: 40, in: list)?.type, .chorus)
    }

    func testApplyAnalysisKeepsUserCorrections() {
        var song = Song(title: "s", bpm: .user(100),
                        sections: [SongSection(type: .intro, startTime: 0, endTime: 10)])
        let result = SongAnalysisResult(duration: 120, bpm: Estimate(50, confidence: 0.5, provenance: .algorithm),
                                        beats: [0, 0.5], key: nil, chords: [],
                                        sections: [SongSection(type: .chorus, startTime: 0, endTime: 120, provenance: .algorithm)],
                                        timbres: [:], suggestions: [], limitations: [])
        song.apply(result)
        XCTAssertEqual(song.bpm?.value, 100)
        XCTAssertEqual(song.sections.map(\.type), [.intro])
        XCTAssertEqual(song.analysisStatus, .completed)
    }
}
