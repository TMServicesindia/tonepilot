import CoreML
import Foundation

/// Runs the htdemucs neural network on the iPhone's GPU / Neural Engine with Core ML. demucs.cpp
/// still does everything around it on the CPU (spectrogram, normalisation, mask and inverse
/// spectrogram), and calls this for each 7.8 s segment. The model is the full 32-bit conversion,
/// checked in CI to match PyTorch's output (92 dB), so quality is the same as the CPU engine.
/// If Core ML fails, demucs.cpp falls back to its CPU path for that segment.
final class CoreMLNetwork: @unchecked Sendable {
    static let modelName = "HTDemucs"
    static let bins = 2048, frames = 336, samples = 343_980

    /// Tests point this at a compiled model (.mlmodelc).
    nonisolated(unsafe) static var modelOverride: URL?
    /// Tests: force the CPU engine.
    nonisolated(unsafe) static var disabled = false
    /// Why the model couldn't be loaded (diagnostics).
    nonisolated(unsafe) static var loadError: String?

    static var modelURL: URL? {
        modelOverride ?? Bundle.main.url(forResource: modelName, withExtension: "mlmodelc", subdirectory: "Models")
            ?? Bundle.main.url(forResource: modelName, withExtension: "mlmodelc")
    }

    private let model: MLModel
    private let lock = NSLock()
    private var failed = false
    private(set) var segments = 0
    private(set) var seconds = 0.0

    init?(computeUnits: MLComputeUnits = .all) {
        guard !Self.disabled, let url = Self.modelURL else { return nil }
        let config = MLModelConfiguration()
        config.computeUnits = computeUnits
        do { model = try MLModel(contentsOf: url, configuration: config) } catch {
            Self.loadError = error.localizedDescription
            return nil
        }
    }

    /// One segment: x (1,4,bins,frames) and xt (1,2,samples) in, x_out (1,16,bins,frames) and
    /// xt_out (1,8,samples) out, all row-major float32. Returns 0 on success.
    func run(x: UnsafePointer<Float>, xt: UnsafePointer<Float>, xOut: UnsafeMutablePointer<Float>,
             xtOut: UnsafeMutablePointer<Float>, bins: Int, frames: Int, samples: Int) -> Int32 {
        guard bins == Self.bins, frames == Self.frames, samples == Self.samples else { return 2 }
        // One prediction at a time: the GPU is shared; the CPU workers keep overlapping around it.
        lock.lock(); defer { lock.unlock() }
        if failed { return 1 }
        let start = Date()
        do {
            let xa = try MLMultiArray(dataPointer: UnsafeMutableRawPointer(mutating: x), shape: [1, 4, bins, frames].map { NSNumber(value: $0) },
                                      dataType: .float32, strides: [4 * bins * frames, bins * frames, frames, 1].map { NSNumber(value: $0) })
            let xta = try MLMultiArray(dataPointer: UnsafeMutableRawPointer(mutating: xt), shape: [1, 2, samples].map { NSNumber(value: $0) },
                                       dataType: .float32, strides: [2 * samples, samples, 1].map { NSNumber(value: $0) })
            let out = try autoreleasepool {
                try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["x": xa, "xt": xta]))
            }
            guard let xo = out.featureValue(for: "x_out")?.multiArrayValue,
                  let xto = out.featureValue(for: "xt_out")?.multiArrayValue,
                  Self.copy(xo, to: xOut, shape: [1, 16, bins, frames]),
                  Self.copy(xto, to: xtOut, shape: [1, 8, samples]) else { failed = true; return 1 }
        } catch {
            failed = true
            return 1
        }
        segments += 1
        seconds += Date().timeIntervalSince(start)
        return 0
    }

    /// Copies a Core ML output (float32 or float16, any strides) into a row-major float buffer.
    static func copy(_ a: MLMultiArray, to dst: UnsafeMutablePointer<Float>, shape expected: [Int]) -> Bool {
        let shape = a.shape.map(\.intValue), strides = a.strides.map(\.intValue)
        guard shape == expected else { return false }
        let count = shape.reduce(1, *)
        var dense = [Int](repeating: 1, count: shape.count)
        for i in stride(from: shape.count - 2, through: 0, by: -1) { dense[i] = dense[i + 1] * shape[i + 1] }
        let contiguous = strides == dense
        return a.withUnsafeBytes { raw -> Bool in
            func each(_ value: (Int) -> Float) {
                if contiguous { for i in 0..<count { dst[i] = value(i) }; return }
                // Strided (e.g. padded rows from the GPU): walk the last axis per row.
                let last = shape[shape.count - 1], lastStride = strides[strides.count - 1]
                for row in 0..<(count / last) {
                    var rem = row, offset = 0
                    for d in stride(from: shape.count - 2, through: 0, by: -1) { offset += (rem % shape[d]) * strides[d]; rem /= shape[d] }
                    for j in 0..<last { dst[row * last + j] = value(offset + j * lastStride) }
                }
            }
            switch a.dataType {
            case .float32:
                let p = raw.bindMemory(to: Float.self)
                if contiguous { dst.update(from: p.baseAddress!, count: count) } else { each { p[$0] } }
                return true
            case .float16:
                let p = raw.bindMemory(to: Float16.self)
                each { Float(p[$0]) }
                return true
            default:
                return false
            }
        }
    }

    /// Registers this network with demucs.cpp until `uninstall()`.
    func install() {
        tp_demucs_set_network({ context, x, xt, xOut, xtOut, bins, frames, samples in
            guard let context, let x, let xt, let xOut, let xtOut else { return 1 }
            return Unmanaged<CoreMLNetwork>.fromOpaque(context).takeUnretainedValue()
                .run(x: x, xt: xt, xOut: xOut, xtOut: xtOut, bins: Int(bins), frames: Int(frames), samples: Int(samples))
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func uninstall() { tp_demucs_set_network(nil, nil) }
}
