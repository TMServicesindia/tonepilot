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
