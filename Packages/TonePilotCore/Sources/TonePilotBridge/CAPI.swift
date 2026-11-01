import Foundation
import TonePilotCore

// C entry points for the Android app's JNI/AAudio shim (app/src/main/cpp/tonepilot_jni.c).
// One process-wide AppCore. Strings returned by tp_call are malloc'd; free them with tp_free.

private let coreLock = NSLock()
nonisolated(unsafe) private var sharedCore: AppCore?
/// Read on the audio thread without locking; written once before audio starts.
nonisolated(unsafe) private var renderCore: AppCore?

/// Creates the app core. Returns 1 on success, 0 on failure (see tp_last_error).
@_cdecl("tp_init")
public func tp_init(_ root: UnsafePointer<CChar>, _ sampleRate: Double) -> Int32 {
    coreLock.lock(); defer { coreLock.unlock() }
    if sharedCore != nil { return 1 }
    do {
        let core = try AppCore(rootDirectory: URL(fileURLWithPath: String(cString: root), isDirectory: true), sampleRate: sampleRate)
        sharedCore = core
        renderCore = core
        return 1
    } catch {
        initError = "\(error)"
        return 0
    }
}

nonisolated(unsafe) private var initError = ""

@_cdecl("tp_last_error")
public func tp_last_error() -> UnsafeMutablePointer<CChar>? { strdup(initError) }

/// Audio thread: fills `frames` samples in each of `left` and `right`.
@_cdecl("tp_render")
public func tp_render(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, _ frames: Int32) {
    guard let core = renderCore else {
        for i in 0..<Int(frames) { left[i] = 0; right[i] = 0 }
        return
    }
    core.render(frames: Int(frames), left: left, right: right)
}

/// MIDI thread: raw MIDI 1.0 bytes from a keyboard.
@_cdecl("tp_midi")
public func tp_midi(_ bytes: UnsafePointer<UInt8>, _ count: Int32) {
    guard let core = renderCore, count > 0 else { return }
    core.midi(Array(UnsafeBufferPointer(start: bytes, count: Int(count))))
}

/// JSON command → JSON result (malloc'd).
@_cdecl("tp_call")
public func tp_call(_ request: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
    guard let core = renderCore else { return strdup("{\"error\":\"not started\"}") }
    return strdup(core.call(String(cString: request)))
}

@_cdecl("tp_free")
public func tp_free(_ p: UnsafeMutablePointer<CChar>?) { free(p) }

/// Adds decoded mono samples to the buffer opened with {"cmd":"pcmBegin","key":…}.
@_cdecl("tp_pcm_append")
public func tp_pcm_append(_ key: UnsafePointer<CChar>, _ samples: UnsafePointer<Float>, _ count: Int32) {
    guard let core = renderCore, count > 0 else { return }
    core.pcmAppend(key: String(cString: key), UnsafeBufferPointer(start: samples, count: Int(count)))
}

/// Listen Mode: mono microphone samples at `sampleRate`.
@_cdecl("tp_listen_append")
public func tp_listen_append(_ samples: UnsafePointer<Float>, _ count: Int32, _ sampleRate: Double) {
    guard let core = renderCore, count > 0 else { return }
    core.listenAppend(UnsafeBufferPointer(start: samples, count: Int(count)), sampleRate: sampleRate)
}

// MARK: Inference (Phase 1): the platform registers a model runner; the core tests it.

nonisolated(unsafe) private var inferFunction: TPInferFunction?

/// Registers the platform's model runner (Android: LiteRT through tonepilot_jni.c) and makes it
/// the core's inference back-end.
@_cdecl("tp_set_inference_callback")
public func tp_set_inference_callback(_ fn: TPInferFunction?) {
    coreLock.lock(); defer { coreLock.unlock() }
    inferFunction = fn
    InferenceRegistry.backend = fn.map { CallbackInferenceBackend(function: $0) }
}

/// Runs the shared inference contract against the registered back-end with the fixture in
/// `fixtureDir` and the model file at `modelPath`. Returns the report as JSON (malloc'd).
@_cdecl("tp_inference_contract")
public func tp_inference_contract(_ fixtureDir: UnsafePointer<CChar>, _ modelPath: UnsafePointer<CChar>, _ tolerance: Float) -> UnsafeMutablePointer<CChar>? {
    guard let backend = InferenceRegistry.backend else { return strdup("{\"error\":\"no inference back-end registered\"}") }
    do {
        let fixture = try InferenceContract.loadFixture(dir: URL(fileURLWithPath: String(cString: fixtureDir), isDirectory: true),
                                                        modelURL: URL(fileURLWithPath: String(cString: modelPath)), tolerance: tolerance)
        let report = InferenceContract.run(backend, fixture)
        var json = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(report))) as? [String: Any] ?? [:]
        json["passed"] = report.passed
        return strdup(String(data: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]), encoding: .utf8) ?? "{}")
    } catch {
        return strdup("{\"error\":\"\(error)\"}")
    }
}

/// Runs the shared import pipeline on the mix-only test song and compares it with the recorded
/// fixture at `expectedPath`. Returns {"passed":Bool,"difference":String?} (malloc'd).
@_cdecl("tp_pipeline_check")
public func tp_pipeline_check(_ expectedPath: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
    do {
        let (ok, d) = try FixtureCheck.checkMixOnly(expectedJSON: Data(contentsOf: URL(fileURLWithPath: String(cString: expectedPath))))
        let json: [String: Any] = ["passed": ok, "difference": d ?? NSNull()]
        return strdup(String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8) ?? "{}")
    } catch {
        return strdup("{\"passed\":false,\"error\":\"\(error)\"}")
    }
}
