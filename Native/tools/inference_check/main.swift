// Phase 1 contract check for the iOS inference back-end on macOS: runs TonePilotCore's
// InferenceContract against CoreMLBackend with the Basic Pitch *test model* (official nmp.mlpackage,
// Apache-2.0; CI only) and the reference fixture generated from the official nmp.tflite.
// Usage: inference_check <nmp.mlpackage> <fixture dir>
import CoreML
import Foundation

guard CommandLine.arguments.count == 3 else { print("usage: inference_check <model> <fixture dir>"); exit(2) }
let model = URL(fileURLWithPath: CommandLine.arguments[1]), dir = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
var failed = false
for (label, units) in [("cpuOnly", MLComputeUnits.cpuOnly), ("all", MLComputeUnits.all)] {
    do {
        // CPU-only is the gate (float32); "all" (GPU/Neural Engine, may use float16) is reported.
        let fixture = try InferenceContract.loadFixture(dir: dir, modelURL: model, tolerance: label == "cpuOnly" ? 1e-3 : 5e-2)
        let report = InferenceContract.run(CoreMLBackend(computeUnits: units), fixture)
        let diffs = report.maxAbsDiff.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.2e", $0.value))" }.joined(separator: ", ")
        print("RESULT Core ML \(label): \(report.passed ? "PASS" : "FAIL") · max |diff| \(diffs) · run \(String(format: "%.1f", report.runMilliseconds)) ms")
        for (k, v) in report.checks.sorted(by: { $0.key < $1.key }) { print("  \(v ? "ok  " : "FAIL") \(k)") }
        report.notes.forEach { print("  note: \($0)") }
        if label == "cpuOnly" && !report.passed { failed = true }
    } catch {
        print("RESULT Core ML \(label): FAIL · \(error)")
        if label == "cpuOnly" { failed = true }
    }
}
exit(failed ? 1 : 0)
