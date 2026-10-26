import AVFoundation
import Foundation
import TonePilotCore
#if os(iOS)
import os
#endif

/// On-device stem separation with Demucs v4 (htdemucs, 4 sources) through demucs.cpp:
/// splits a song into drums, bass, other (music) and vocals, like Moises does in the cloud.
/// Blocks of the song are separated in parallel and written to AAC files as they finish, so
/// memory stays bounded. Nothing leaves the iPhone.
enum StemSeparator {
    enum Failure: LocalizedError {
        case modelMissing, modelLoad, unreadable(String), separation(Int32), cancelled, write(String)
        var errorDescription: String? {
            switch self {
            case .modelMissing: return "The separation model isn't included in this build."
            case .modelLoad: return "The separation model couldn't be loaded."
            case .unreadable(let m): return "The song couldn't be read for separation (\(m))."
            case .separation(let c): return "Separation failed (code \(c))."
            case .cancelled: return "Separation was cancelled."
            case .write(let m): return "The separated parts couldn't be saved (\(m))."
            }
        }
    }

    static let modelName = "ggml-model-htdemucs-4s-f16"
    /// demucs.cpp output order for the 4-source model.
    static let order: [StemInfo.Kind] = [.drums, .bass, .other, .vocals]
    static let sampleRate = 44_100.0

    /// Tests point this at the weights file.
    nonisolated(unsafe) static var modelOverride: URL?

    static var modelURL: URL? {
        modelOverride ?? Bundle.main.url(forResource: modelName, withExtension: "bin", subdirectory: "Models")
            ?? Bundle.main.url(forResource: modelName, withExtension: "bin")
    }

    static var isAvailable: Bool { modelURL != nil }

    /// Parallel workers. iOS closes apps that go over their memory limit (≈3 GB on an iPhone 15),
    /// so this is based on the memory actually available, not the number of cores. Measured on
    /// Apple Silicon with TonePilot's optimised engine: ~0.8 GB per worker at its peak (2 workers
    /// 1.6 GB), so an iPhone 15 runs 2 — re-checked before every block.
    static var workers: Int {
        if let w = workersOverride { return w }
        let perWorker = 1_000 * 1_048_576, reserve = 700 * 1_048_576
        let available = availableMemory
        guard available > 0 else { return 1 }
        return max(1, min(2, (available - reserve) / perWorker))
    }

    /// Memory this app can still use before iOS closes it (0 when unknown, e.g. on macOS).
    static var availableMemory: Int {
        #if os(iOS)
        return Int(os_proc_available_memory())
        #else
        return 0
        #endif
    }
    nonisolated(unsafe) static var workersOverride: Int?
    /// How the last separation ran (diagnostics and tests).
    nonisolated(unsafe) static var lastRun: String?
    /// Tests: every block's raw output (sources × 2 channels × frames) before it's merged.
    nonisolated(unsafe) static var rawBlock: ((Int, [Float]) -> Void)?
    /// Tests: called after each block is written.
    nonisolated(unsafe) static var blockDone: ((Int) -> Void)?

    /// Blocking; run on a background thread. Returns the stems written to `outputDir`.
    static func separate(input: URL, outputDir: URL, progress: @escaping (Double) -> Void,
                         isCancelled: @escaping () -> Bool) throws -> [StemInfo] {
        guard let modelURL else { throw Failure.modelMissing }
        let (left, right) = try decodeStereo(input)
        if isCancelled() { throw Failure.cancelled }
        guard let model = tp_demucs_load(modelURL.path) else { throw Failure.modelLoad }
        defer { tp_demucs_free(model) }
        let sources = Int(tp_demucs_source_count(model))
        guard sources == order.count else { throw Failure.modelLoad }
        // The neural network runs on the GPU / Neural Engine when the Core ML model is in the app
        // (several times faster, same output); otherwise everything runs on the CPU.
        let network = CoreMLNetwork()
        network?.install()
        defer {
            network?.uninstall()
            if let network { lastRun = "Core ML: \(network.segments) segments in \(String(format: "%.1f", network.seconds)) s" }
        }

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let files = try order.map { kind -> (StemInfo.Kind, URL, AVAudioFile) in
            let url = outputDir.appendingPathComponent("\(kind.rawValue).m4a")
            try? FileManager.default.removeItem(at: url)
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
                                           AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000]
            do {
                let f = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
                return (kind, url, f)
            } catch { throw Failure.write(error.localizedDescription) }
        }

        let n = left.count
        let plan = StemChunkPlan(total: n, chunkLength: Int(sampleRate * 15), overlap: Int(sampleRate))
        var merger = StemMerger(plan: plan, trackCount: sources * 2)
        let tracker = ProgressTracker(total: plan.chunks.count, report: progress)
        let k = workers

        var next = 0
        while next < plan.chunks.count {
            if isCancelled() { throw Failure.cancelled }
            // Re-check memory before every batch (the user may be playing at the same time).
            let width = min(k, workersOverride ?? workers)
            let batch = Array(plan.chunks[next..<min(plan.chunks.count, next + max(1, width))])
            next += batch.count
            let results = ResultBox(count: batch.count)
            DispatchQueue.concurrentPerform(iterations: batch.count) { j in
                let c = batch[j]
                var out = [Float](repeating: 0, count: sources * 2 * c.length)
                let slot = WorkerSlot(tracker: tracker, index: c.index)
                let ctx = Unmanaged.passRetained(slot).toOpaque()
                let code = left.withUnsafeBufferPointer { lp in
                    right.withUnsafeBufferPointer { rp in
                        out.withUnsafeMutableBufferPointer { op in
                            tp_demucs_separate(model, lp.baseAddress! + c.start, rp.baseAddress! + c.start, c.length,
                                               op.baseAddress!, { context, p in
                                                   guard let context else { return }
                                                   Unmanaged<WorkerSlot>.fromOpaque(context).takeUnretainedValue().update(p)
                                               }, ctx)
                        }
                    }
                }
                Unmanaged<WorkerSlot>.fromOpaque(ctx).release()
                results.set(j, out, code: code)
            }
            for (j, c) in batch.enumerated() { try autoreleasepool {
                let (out, code) = results.take(j)
                guard code == 0 else { throw Failure.separation(code) }
                rawBlock?(c.index, out)
                let tracks = (0..<(sources * 2)).map { t in Array(out[(t * c.length)..<((t + 1) * c.length)]) }
                let done = merger.add(c.index, tracks)
                for s in 0..<sources { try write(files[s].2, left: done[s * 2], right: done[s * 2 + 1]) }
                tracker.finished(c.index)
                blockDone?(c.index)
            } }
        }
        return files.map { StemInfo(kind: $0.0, fileName: $0.1.lastPathComponent, model: "htdemucs (on this iPhone)") }
    }

    /// Writes a stereo part as AAC (same format as the separated parts).
    static func writeStem(left: [Float], right: [Float], to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
                                       AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000]
        let file: AVAudioFile
        do { file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false) } catch {
            throw Failure.write(error.localizedDescription)
        }
        try write(file, left: left, right: right)
    }

    private static func write(_ file: AVAudioFile, left: [Float], right: [Float]) throws {
        guard !left.isEmpty else { return }
        let step = 262_144
        var offset = 0
        while offset < left.count {
            let count = min(step, left.count - offset)
            guard let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)),
                  let ch = buf.floatChannelData else { throw Failure.write("buffer") }
            left.withUnsafeBufferPointer { ch[0].update(from: $0.baseAddress! + offset, count: count) }
            right.withUnsafeBufferPointer { ch[1].update(from: $0.baseAddress! + offset, count: count) }
            buf.frameLength = AVAudioFrameCount(count)
            do { try file.write(from: buf) } catch { throw Failure.write(error.localizedDescription) }
            offset += count
        }
    }

    /// The whole song at 44.1 kHz as two planar channels (mono files are duplicated).
    static func decodeStereo(_ url: URL) throws -> ([Float], [Float]) {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw Failure.unreadable(error.localizedDescription) }
        let inFormat = file.processingFormat
        let channels = min(2, max(1, inFormat.channelCount))
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: channels, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: 32_768),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: 32_768) else {
            throw Failure.unreadable("no converter")
        }
        var left: [Float] = [], right: [Float] = []
        let expected = Int(Double(file.length) * sampleRate / inFormat.sampleRate) + 4096
        left.reserveCapacity(expected); right.reserveCapacity(expected)
        var reachedEnd = false
        while true {
            outBuffer.frameLength = 0
            var convertError: NSError?
            let status = converter.convert(to: outBuffer, error: &convertError) { _, inputStatus in
                if reachedEnd { inputStatus.pointee = .endOfStream; return nil }
                do { try file.read(into: inBuffer) } catch { reachedEnd = true; inputStatus.pointee = .endOfStream; return nil }
                if inBuffer.frameLength == 0 { reachedEnd = true; inputStatus.pointee = .endOfStream; return nil }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if status == .error { throw Failure.unreadable(convertError?.localizedDescription ?? "conversion failed") }
            if let ch = outBuffer.floatChannelData, outBuffer.frameLength > 0 {
                let count = Int(outBuffer.frameLength)
                left.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: count))
                right.append(contentsOf: UnsafeBufferPointer(start: ch[channels > 1 ? 1 : 0], count: count))
            }
            if status == .endOfStream || (status == .inputRanDry && reachedEnd) { break }
        }
        guard left.count > Int(sampleRate) else { throw Failure.unreadable("too short") }
        return (left, right)
    }
}

/// Collects block progress from the worker threads and reports overall progress (throttled).
private final class ProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var partial: [Int: Float] = [:]
    private var finishedCount = 0
    private var lastReported = -1.0
    private let total: Int
    private let report: (Double) -> Void

    init(total: Int, report: @escaping (Double) -> Void) {
        self.total = max(1, total)
        self.report = report
    }

    func update(_ index: Int, _ p: Float) {
        lock.lock()
        partial[index] = min(1, max(0, p))
        let value = overall()
        let send = value - lastReported >= 0.005
        if send { lastReported = value }
        lock.unlock()
        if send { report(value) }
    }

    func finished(_ index: Int) {
        lock.lock()
        partial[index] = nil
        finishedCount += 1
        let value = overall()
        lastReported = value
        lock.unlock()
        report(value)
    }

    private func overall() -> Double {
        (Double(finishedCount) + Double(partial.values.reduce(0, +))) / Double(total)
    }
}

private final class WorkerSlot {
    let tracker: ProgressTracker
    let index: Int
    init(tracker: ProgressTracker, index: Int) { self.tracker = tracker; self.index = index }
    func update(_ p: Float) { tracker.update(index, p) }
}

/// Thread-safe storage for one batch's outputs.
private final class ResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var outputs: [[Float]]
    private var codes: [Int32]
    init(count: Int) {
        outputs = Array(repeating: [], count: count)
        codes = Array(repeating: -1, count: count)
    }
    func set(_ i: Int, _ out: [Float], code: Int32) { lock.lock(); outputs[i] = out; codes[i] = code; lock.unlock() }
    /// Hands over (and forgets) one output so its memory is freed as soon as it's written.
    func take(_ i: Int) -> ([Float], Int32) {
        lock.lock(); defer { lock.unlock() }
        let out = outputs[i]
        outputs[i] = []
        return (out, codes[i])
    }
}
