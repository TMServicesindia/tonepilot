import CoreML
import Foundation
import TonePilotCore
import UIKit

/// On-device measurements for Gate 2. Every number in the report is MEASURED on this device;
/// anything the device does not expose is reported as unavailable, never estimated.
@MainActor
final class LabBenchmark: ObservableObject {
    @Published var log: [String] = []
    @Published var running = false
    @Published var reportURL: URL?

    func run(sustainedSeconds: Int) async {
        running = true; log = []; reportURL = nil
        defer { running = false }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let sink: @Sendable (String) -> Void = { line in Task { @MainActor [weak self] in self?.log.append(line) } }
        let report = await Task.detached(priority: .userInitiated) { LabBenchmark.measure(sustainedSeconds: sustainedSeconds, say: sink) }.value
        save(report)
    }

    /// All measurement work, synchronous and off the main thread (UIKit state is read on main).
    nonisolated static func measure(sustainedSeconds: Int, say: @Sendable (String) -> Void) -> [String: Any] {
        var report: [String: Any] = ["label": "MEASURED on a physical device by TonePilot Lab", "date": ISO8601DateFormatter().string(from: Date()),
                                     "device": onMain { Self.deviceInfo() }, "sustained_seconds": sustainedSeconds]
        say("Device \(Self.machine()), iOS \(onMain { UIDevice.current.systemVersion })")

        // 1. Front-end parity on device (Swift mel vs the PyTorch fixture).
        let audio = Self.floats("audio") ?? Self.synthetic(seconds: 2.5)
        let t0 = Date(); let mel = EfficientATFrontEnd.logMel(audio); let melMs = Date().timeIntervalSince(t0) * 1000
        var fe: [String: Any] = ["frames": mel.frames, "ms_for_2.5s": melMs]
        if let ref = Self.floats("mel"), ref.count == mel.values.count {
            fe["max_abs_diff_vs_pytorch"] = zip(ref, mel.values).map { abs($0 - $1) }.max() ?? 0
        } else { fe["max_abs_diff_vs_pytorch"] = "fixture not bundled" }
        report["front_end"] = fe; say("Front-end: \(fe)")
        guard mel.frames >= 101 else { say("Too few frames"); return report }
        let input = try! MLMultiArray(shape: [1, 1, 128, 101], dataType: .float32)
        for m in 0..<128 { for t in 0..<101 { input[m * 101 + t] = NSNumber(value: mel.values[m * mel.frames + t]) } }
        let provider = try! MLDictionaryFeatureProvider(dictionary: ["mel": MLFeatureValue(multiArray: input)])

        // 2. Each model × compute unit: cold load + first prediction, warm latency percentiles.
        var models: [String: Any] = [:]
        var best: (name: String, units: MLComputeUnits, ms: Double)?
        let units: [(String, MLComputeUnits)] = [("cpuOnly", .cpuOnly), ("cpuAndNeuralEngine", .cpuAndNeuralEngine), ("all", .all)]
        for name in ["EfficientAT_mn10_as_fp16", "EfficientAT_mn10_as_fp32"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else { models[name] = "not bundled"; continue }
            var per: [String: Any] = ["size_mb": Self.sizeMB(url)]
            for (uname, u) in units {
                let cfg = MLModelConfiguration(); cfg.computeUnits = u
                let c0 = Date()
                guard let model = try? MLModel(contentsOf: url, configuration: cfg) else { per[uname] = "load failed"; continue }
                let loadMs = Date().timeIntervalSince(c0) * 1000
                let f0 = Date(); let first = try? model.prediction(from: provider); let firstMs = Date().timeIntervalSince(f0) * 1000
                var warm: [Double] = []
                for _ in 0..<110 { let w0 = Date(); _ = try? model.prediction(from: provider); warm.append(Date().timeIntervalSince(w0) * 1000) }
                warm = Array(warm.dropFirst(10)).sorted()
                let q = { (p: Double) in warm[min(warm.count - 1, Int(p * Double(warm.count)))] }
                var r: [String: Any] = ["load_ms": loadMs, "first_prediction_ms": firstMs, "warm_ms_median": q(0.5), "warm_ms_p90": q(0.9), "warm_ms_p95": q(0.95),
                                        "footprint_mb": Self.footprintMB()]
                if let probs = first?.featureValue(for: "probs")?.multiArrayValue, let ref = Self.floats("ref_probs"), ref.count == probs.count {
                    var d: Float = 0; for i in 0..<ref.count { d = max(d, abs(probs[i].floatValue - ref[i])) }
                    r["max_abs_diff_probs_vs_pytorch"] = d
                }
                per[uname] = r; say("\(name) \(uname): median \(String(format: "%.2f", q(0.5))) ms")
                if best == nil || q(0.5) < best!.ms { best = (name, u, q(0.5)) }
            }
            models[name] = per
        }
        report["models"] = models
        guard let best, let url = Bundle.main.url(forResource: best.name, withExtension: "mlmodelc") else { return report }
        let cfg = MLModelConfiguration(); cfg.computeUnits = best.units
        let model = try! MLModel(contentsOf: url, configuration: cfg)
        report["best"] = ["model": best.name, "units": "\(best.units.rawValue)", "warm_ms_median": best.ms]

        // 3. Full-song analysis time (front-end + inference, 1 s windows, 0.5 s hop) for 1/3/4/5 minutes.
        var songs: [String: Any] = [:]
        for minutes in [1, 3, 4, 5] {
            let x = Self.synthetic(seconds: Double(minutes * 60))
            let a0 = Date(); let m = EfficientATFrontEnd.logMel(x); let feS = Date().timeIntervalSince(a0)
            let b0 = Date(); var windows = 0
            for start in stride(from: 0, through: m.frames - 101, by: 50) {
                let arr = try! MLMultiArray(shape: [1, 1, 128, 101], dataType: .float32)
                let ptr = arr.dataPointer.bindMemory(to: Float.self, capacity: 128 * 101)
                for mm in 0..<128 { for t in 0..<101 { ptr[mm * 101 + t] = m.values[mm * m.frames + start + t] } }
                _ = try? model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["mel": MLFeatureValue(multiArray: arr)]))
                windows += 1
            }
            let infS = Date().timeIntervalSince(b0)
            songs["\(minutes)min"] = ["front_end_s": feS, "inference_s": infS, "total_s": feS + infS, "windows": windows,
                                      "real_time_factor": (feS + infS) / Double(minutes * 60), "footprint_mb": Self.footprintMB()]
            say("\(minutes)-min song: \(String(format: "%.2f", feS + infS)) s (front-end \(String(format: "%.2f", feS)) s)")
        }
        report["full_song"] = songs

        // 4. Sustained load: thermal state, footprint and battery.
        let (battery0, state0) = onMain { (UIDevice.current.batteryLevel, UIDevice.current.batteryState.rawValue) }
        var samples: [[String: Any]] = []; let s0 = Date(); var n = 0; var lastSample = -1
        while Date().timeIntervalSince(s0) < Double(sustainedSeconds) {
            _ = try? model.prediction(from: provider); n += 1
            let sec = Int(Date().timeIntervalSince(s0))
            if sec != lastSample && sec % 5 == 0 {
                lastSample = sec
                samples.append(["t": sec, "thermal": Self.thermal(), "footprint_mb": Self.footprintMB(), "windows": n])
                if sec % 30 == 0 { say("sustained \(sec)s thermal \(Self.thermal())") }
            }
        }
        let (batteryAfter, stateAfter) = onMain { (UIDevice.current.batteryLevel, UIDevice.current.batteryState.rawValue) }
        report["sustained"] = ["windows": n, "windows_per_s": Double(n) / Double(sustainedSeconds), "samples": samples,
                               "battery_level_before": battery0 < 0 ? "unavailable" : battery0 as Any,
                               "battery_level_after": batteryAfter < 0 ? "unavailable" : batteryAfter as Any,
                               "battery_state_before": state0, "battery_state_after": stateAfter,
                               "note": "Battery level has 1% (or 5%) granularity on iOS; precise energy is not exposed to apps."]
        report["peak_footprint_mb"] = Self.footprintMB()
        return report
    }

    private func save(_ report: [String: Any]) {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("tonepilot-lab-\(Int(Date().timeIntervalSince1970)).json")
        if let d = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: url); reportURL = url }
        log.append("Report saved: \(url.lastPathComponent) (Files app → TonePilot Lab)")
    }

    // MARK: Helpers
    nonisolated static func onMain<T>(_ f: @MainActor () -> T) -> T {
        if Thread.isMainThread { return MainActor.assumeIsolated(f) }
        return DispatchQueue.main.sync { MainActor.assumeIsolated(f) }
    }
    nonisolated static func machine() -> String {
        var s = utsname(); uname(&s)
        return withUnsafeBytes(of: &s.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
    static func deviceInfo() -> [String: Any] {
        ["machine": machine(), "ios": UIDevice.current.systemVersion, "cores": ProcessInfo.processInfo.activeProcessorCount,
         "memory_gb": Double(ProcessInfo.processInfo.physicalMemory) / 1e9, "low_power_mode": ProcessInfo.processInfo.isLowPowerModeEnabled]
    }
    nonisolated static func thermal() -> String {
        switch ProcessInfo.processInfo.thermalState { case .nominal: return "nominal"; case .fair: return "fair"; case .serious: return "serious"; case .critical: return "critical"; @unknown default: return "unknown" }
    }
    nonisolated static func footprintMB() -> Double {
        var info = task_vm_info_data_t(); var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
        return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }
    nonisolated static func sizeMB(_ url: URL) -> Double {
        let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
        var total = 0
        while let f = e?.nextObject() as? URL { total += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return Double(total) / 1e6
    }
    nonisolated static func floats(_ name: String) -> [Float]? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "f32"), let d = try? Data(contentsOf: url) else { return nil }
        return d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
    nonisolated static func synthetic(seconds: Double) -> [Float] {
        let sr = 32_000.0, n = Int(seconds * sr)
        var x = [Float](repeating: 0, count: n); var r: UInt64 = 7
        for i in 0..<n {
            let t = Double(i) / sr
            r = r &* 6364136223846793005 &+ 1442695040888963407
            x[i] = Float(0.3 * sin(2 * .pi * 220 * t) + 0.2 * sin(2 * .pi * 330 * t) * sin(2 * .pi * 0.5 * t)) + Float(Int64(bitPattern: r >> 11) % 1000) / 20_000
        }
        return x
    }
}
