#if canImport(CoreML)
import CoreML
import Foundation

/// iOS implementation of `InferenceBackend` (Core ML). Inputs and outputs use TonePilot's logical
/// tensor names; the descriptor maps them to Core ML feature names. Output arrays are read through
/// their strides, so non-contiguous Core ML layouts come back correctly.
public final class CoreMLBackend: InferenceBackend, @unchecked Sendable {
    public let id = "coreml"
    private let lock = NSLock()
    private var models: [String: (MLModel, ModelDescriptor)] = [:]
    private let computeUnits: MLComputeUnits

    /// `.cpuOnly` gives full float32 (used by the contract check); `.all` lets Core ML use the
    /// GPU / Neural Engine (production).
    public init(computeUnits: MLComputeUnits = .all) {
        self.computeUnits = computeUnits
    }

    public func load(_ descriptor: ModelDescriptor, from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InferenceError.loadFailed(model: descriptor.name, reason: "file not found: \(url.lastPathComponent)")
        }
        do {
            let compiled = url.pathExtension == "mlmodelc" ? url : try MLModel.compileModel(at: url)
            let config = MLModelConfiguration()
            config.computeUnits = computeUnits
            let model = try MLModel(contentsOf: compiled, configuration: config)
            // Every mapped input/output must exist in the model.
            let inputs = Set(model.modelDescription.inputDescriptionsByName.keys)
            let outputs = Set(model.modelDescription.outputDescriptionsByName.keys)
            for logical in descriptor.inputs.keys where !inputs.contains(descriptor.backendName(logical, for: id)) {
                throw InferenceError.loadFailed(model: descriptor.name, reason: "no Core ML input \(descriptor.backendName(logical, for: id))")
            }
            for logical in descriptor.outputs.keys where !outputs.contains(descriptor.backendName(logical, for: id)) {
                throw InferenceError.loadFailed(model: descriptor.name, reason: "no Core ML output \(descriptor.backendName(logical, for: id))")
            }
            lock.withLock { models[descriptor.name] = (model, descriptor) }
        } catch let e as InferenceError {
            throw e
        } catch {
            throw InferenceError.loadFailed(model: descriptor.name, reason: error.localizedDescription)
        }
    }

    public func isLoaded(_ model: String) -> Bool { lock.withLock { models[model] != nil } }

    public func run(_ model: String, inputs: [String: Tensor]) throws -> [String: Tensor] {
        guard let (ml, descriptor) = lock.withLock({ models[model] }) else { throw InferenceError.modelNotLoaded(model) }
        try descriptor.validate(inputs: inputs)
        var features: [String: MLFeatureValue] = [:]
        for (logical, tensor) in inputs {
            let array = try MLMultiArray(shape: tensor.shape.map { NSNumber(value: $0) }, dataType: .float32)
            let p = array.dataPointer.bindMemory(to: Float.self, capacity: tensor.count)
            tensor.values.withUnsafeBufferPointer { src in p.update(from: src.baseAddress!, count: tensor.count) }
            features[descriptor.backendName(logical, for: id)] = MLFeatureValue(multiArray: array)
        }
        let result: MLFeatureProvider
        do {
            result = try ml.prediction(from: MLDictionaryFeatureProvider(dictionary: features))
        } catch {
            throw InferenceError.backendFailure(error.localizedDescription)
        }
        var out: [String: Tensor] = [:]
        for logical in descriptor.outputs.keys {
            guard let array = result.featureValue(for: descriptor.backendName(logical, for: id))?.multiArrayValue else {
                throw InferenceError.missingOutput(logical)
            }
            out[logical] = try Self.tensor(from: array)
        }
        try descriptor.validate(outputs: out)
        return out
    }

    public func unload(_ model: String) { lock.withLock { _ = models.removeValue(forKey: model) } }

    /// Reads any float32/float16/double MLMultiArray through its strides into a dense tensor.
    static func tensor(from a: MLMultiArray) throws -> Tensor {
        let shape = a.shape.map(\.intValue), strides = a.strides.map(\.intValue)
        let count = shape.reduce(1, *)
        var values = [Float](repeating: 0, count: count)
        var index = [Int](repeating: 0, count: shape.count)
        func offset() -> Int { zip(index, strides).reduce(0) { $0 + $1.0 * $1.1 } }
        for i in 0..<count {
            let o = offset()
            switch a.dataType {
            case .float32: values[i] = a.dataPointer.assumingMemoryBound(to: Float.self)[o]
            case .double: values[i] = Float(a.dataPointer.assumingMemoryBound(to: Double.self)[o])
            case .float16:
                #if arch(arm64)
                values[i] = Float(a.dataPointer.assumingMemoryBound(to: Float16.self)[o])
                #else
                values[i] = a[o].floatValue
                #endif
            default: values[i] = a[o].floatValue
            }
            var d = shape.count - 1
            while d >= 0 { index[d] += 1; if index[d] < shape[d] { break }; index[d] = 0; d -= 1 }
        }
        return try Tensor(shape: shape, values: values)
    }
}
#endif
