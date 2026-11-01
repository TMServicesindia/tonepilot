import Foundation
import XCTest
@testable import TonePilotCore

/// Stage 5 data check: every tone named in the instrument → tone map exists in TonePilot's library,
/// and every mapped instrument is in the taxonomy. (Research data; not used by the app yet.)
final class InstrumentToneMapTests: XCTestCase {
    func testToneMapNamesExist() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Native/tools/instruments/taxonomy.json").standardized
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("taxonomy.json not available (package-only checkout)") }
        let t = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let families = t["families"] as! [String: [String]]
        let instruments = Set(families.values.flatMap { $0 })
        let map = t["tone_map"] as! [String: [String]]
        let names = Set(FactoryPatches.all.map(\.name))
        var missing: [String] = []
        for (inst, tones) in map {
            XCTAssertTrue(instruments.contains(inst), "\(inst) is not in the taxonomy")
            for tone in tones where !names.contains(tone) { missing.append("\(inst) → \(tone)") }
        }
        XCTAssertTrue(missing.isEmpty, "tones not in FactoryPatches: \(missing.sorted())")
        let unmapped = instruments.subtracting(map.keys).sorted()
        print("TONEMAP mapped \(map.count) instruments; no tone yet for: \(unmapped.joined(separator: ", "))")
    }
}
