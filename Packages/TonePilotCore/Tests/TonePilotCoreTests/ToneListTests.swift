import XCTest
@testable import TonePilotCore

final class ToneListTests: XCTestCase {
    func testSingleInstrumentToneIsStableAndFullRange() {
        let p = FactoryPatches.all.first { $0.id == FactoryPatches.bansuriId }!
        let a = Arrangement.single(p), b = Arrangement.single(p)
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.layers.map(\.id), b.layers.map(\.id), "stable ids so held notes survive re-selecting")
        XCTAssertEqual(a.layers.first?.keyRange, .full)
        XCTAssertEqual(a.name, "Bansuri-like Flute")
        XCTAssertNotEqual(Arrangement.single(FactoryPatches.generalMIDI[0]).id, a.id)
    }

    func testToneListGroupsSongTonesMyTonesAndInstruments() throws {
        var lib = Library()
        lib.mergeFactoryPatches(FactoryPatches.all)
        let audio = SyntheticSong.render(pattern: ["A", "B", "A", "B"], beatsPerSection: 32)
        let out = try SongPipeline.run(song: Song(title: "Hukum"), audio: audio, patches: lib.patches)
        lib.upsert(out.song)
        lib.globalArrangements.append(Arrangement(name: "My Lead", layers: [Layer(patchId: FactoryPatches.vocalLeadId)]))

        let list = lib.toneList()
        XCTAssertFalse(list.songTones.isEmpty)
        XCTAssertTrue(list.songTones.allSatisfy { $0.tone.name.hasPrefix("Hukum – ") && $0.songId == out.song.id })
        XCTAssertEqual(Set(list.songTones.map(\.tone.id)).count, list.songTones.count, "shared section tones listed once")
        XCTAssertEqual(list.myTones.map(\.tone.name), ["My Lead"])
        let names = list.instruments.flatMap { $0.entries.map(\.tone.name) }
        XCTAssertTrue(names.contains("Grand Piano") && names.contains("Orchestral Strings") && names.contains("Bansuri-like Flute"))
        XCTAssertFalse(names.contains("Metronome Click"), "accompaniment-only sounds hidden")
        XCTAssertEqual(lib.toneList(search: "flute").instruments.flatMap(\.entries).count, 5) // Flute, Pan Flute, Bansuri-like, Low Bansuri-like, 90s Pan Flute Lead
        // Saving a song tone makes an independent copy.
        let saved = list.songTones[0].tone.savedAsMyTone(name: "Hukum Chorus")
        XCTAssertNotEqual(saved.id, list.songTones[0].tone.id)
        XCTAssertEqual(saved.origin, .user)
    }
}
