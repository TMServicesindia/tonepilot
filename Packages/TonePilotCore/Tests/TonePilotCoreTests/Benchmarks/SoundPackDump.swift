import XCTest
@testable import TonePilotCore

/// CI step of the sound-pack build: renders every pack tone playing the tone table's standard
/// phrase in its 3 registers (exactly as `ToneTableDump` does for the library), so the same
/// Python export (`tone_t1.py --export-tables`) computes embeddings for the pack's tones.
/// Reads the CI-only WAV copies (`wav/<pack id>/*.wav`). Runs when TP_PACKS and TP_PACK_DUMP are set.
final class SoundPackDump: XCTestCase {
    func testDumpPackTones() throws {
        let env = ProcessInfo.processInfo.environment
        guard let root = env["TP_PACKS"], let dump = env["TP_PACK_DUMP"] else { throw XCTSkip("set TP_PACKS and TP_PACK_DUMP") }
        let base = URL(fileURLWithPath: root), out = URL(fileURLWithPath: dump)
        try FileManager.default.createDirectory(at: out.appendingPathComponent("table"), withIntermediateDirectories: true)
        var table: [[String: Any]] = []
        let ids = try FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent("packs").path).sorted()
        for id in ids {
            let pack = try SoundPack.decode(Data(contentsOf: base.appendingPathComponent("packs/\(id)/pack.json")))
            XCTAssertEqual(pack.problems(), [], "\(id) is playable")
            for patch in pack.patches {
                let samples = try patch.sampleZones.map { z -> LoadedInstrument.UserSample in
                    let wav = base.appendingPathComponent("wav/\(id)/" + (z.fileName as NSString).lastPathComponent.replacingOccurrences(of: ".flac", with: ".wav"))
                    let d = try WAVDecoder.decodeMono(url: wav)
                    return LoadedInstrument.UserSample(frames: d.frames, sampleRate: d.sampleRate, zone: z)
                }
                let inst = LoadedInstrument(name: patch.name, userSamples: samples, envelope: patch.envelope)
                for reg in ToneTableDump.registers {
                    let notes = ToneTableDump.phrase(base: reg)
                    let audio = ToneMatcher.render(patch, instrument: inst, notes: notes, seconds: (notes.last?.end ?? 5) + 0.6, sampleRate: ToneTableDump.sr)
                    let file = "table/\(id)_\(patch.id.uuidString)_\(reg).wav"
                    try InstrumentSetRender.writeWav(audio.samples, to: out.appendingPathComponent(file), sr: ToneTableDump.sr)
                    table.append(["file": file, "patch": patch.id.uuidString, "name": patch.name, "family": patch.family.rawValue,
                                  "pack": id, "register": reg, "notes": ToneTableDump.noteList(notes)])
                }
            }
        }
        try JSONSerialization.data(withJSONObject: table, options: .prettyPrinted).write(to: out.appendingPathComponent("table.json"))
        print("PACKDUMP \(table.count) clips from \(ids.count) packs")
    }
}
