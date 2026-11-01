import Foundation
import TonePilotCore

/// The C function a platform registers to run models (Android: tonepilot_jni.c → Kotlin LiteRT).
/// `request` is JSON (op: load / run / unload); inputs arrive concatenated in `input`, outputs
/// are written concatenated into `output` (capacity in floats); `response` receives JSON
/// (`{"ok":true,…}` or `{"ok":false,"kind":…,"error":…}`). Returns 0 on success.
public typealias TPInferFunction = @convention(c) (
    _ request: UnsafePointer<CChar>, _ input: UnsafePointer<Float>?, _ inputCount: Int64,
    _ output: UnsafeMutablePointer<Float>?, _ outputCapacity: Int64,
    _ response: UnsafeMutablePointer<CChar>, _ responseCapacity: Int32) -> Int32

/// `InferenceBackend` over a registered C callback, so TonePilotCore runs models on Android
/// through the same contract as Core ML on iOS. Validation happens here, in shared code.
public final class CallbackInferenceBackend: InferenceBackend, @unchecked Sendable {
    public let id: String
    private let fn: TPInferFunction
    private let lock = NSLock()
    private var descriptors: [String: ModelDescriptor] = [:]

    public init(id: String = "litert", function: @escaping TPInferFunction) {
        self.id = id
        self.fn = function
    }

    private func call(_ request: [String: Any], input: [Float] = [], outputCapacity: Int = 0) throws -> ([String: Any], [Float]) {
        let json = String(data: try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys]), encoding: .utf8)!
        var output = [Float](repeating: 0, count: max(1, outputCapacity))
        var response = [CChar](repeating: 0, count: 64 * 1024)
        let status = json.withCString { req in
            input.withUnsafeBufferPointer { inp in
                output.withUnsafeMutableBufferPointer { out in
                    response.withUnsafeMutableBufferPointer { resp in
                        fn(req, inp.baseAddress, Int64(input.count), out.baseAddress, Int64(outputCapacity), resp.baseAddress!, Int32(resp.count))
                    }
                }
            }
        }
        let text = String(cString: response)
        let parsed = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        if status != 0 || parsed["ok"] as? Bool != true {
            let reason = parsed["error"] as? String ?? "status \(status)"
            switch parsed["kind"] as? String {
            case "loadFailed": throw InferenceError.loadFailed(model: request["model"] as? String ?? "?", reason: reason)
            case "modelNotLoaded": throw InferenceError.modelNotLoaded(request["model"] as? String ?? "?")
            default: throw InferenceError.backendFailure(reason)
            }
        }
        return (parsed, output)
    }

    public func load(_ descriptor: ModelDescriptor, from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InferenceError.loadFailed(model: descriptor.name, reason: "file not found: \(url.lastPathComponent)")
        }
        let names: (([String: [Int]]) -> [String: [Int]]) = { d in
            Dictionary(uniqueKeysWithValues: d.map { (descriptor.backendName($0.key, for: self.id), $0.value) })
        }
        _ = try call(["op": "load", "model": descriptor.name, "path": url.path,
                      "inputs": names(descriptor.inputs), "outputs": names(descriptor.outputs)])
        lock.withLock { descriptors[descriptor.name] = descriptor }
    }

    public func isLoaded(_ model: String) -> Bool { lock.withLock { descriptors[model] != nil } }

    public func run(_ model: String, inputs: [String: Tensor]) throws -> [String: Tensor] {
        guard let d = lock.withLock({ descriptors[model] }) else { throw InferenceError.modelNotLoaded(model) }
        try d.validate(inputs: inputs)
        var flat: [Float] = [], inSpecs: [[String: Any]] = []
        for key in inputs.keys.sorted() {
            let t = inputs[key]!
            inSpecs.append(["name": d.backendName(key, for: id), "shape": t.shape, "offset": flat.count, "count": t.count])
            flat += t.values
        }
        let outKeys = d.outputs.keys.sorted()
        let capacity = outKeys.reduce(0) { $0 + d.outputs[$1]!.reduce(1, *) }
        let outSpecs: [[String: Any]] = outKeys.map { ["name": d.backendName($0, for: id), "shape": d.outputs[$0]!] }
        let (resp, buffer) = try call(["op": "run", "model": model, "inputs": inSpecs, "outputs": outSpecs], input: flat, outputCapacity: capacity)
        var result: [String: Tensor] = [:]
        for spec in resp["outputs"] as? [[String: Any]] ?? [] {
            guard let name = spec["name"] as? String, let shape = spec["shape"] as? [Int],
                  let offset = spec["offset"] as? Int, let count = spec["count"] as? Int,
                  offset >= 0, count >= 0, offset + count <= buffer.count,
                  let logical = outKeys.first(where: { d.backendName($0, for: id) == name }) else { continue }
            result[logical] = try Tensor(shape: shape, values: Array(buffer[offset..<(offset + count)]))
        }
        try d.validate(outputs: result)
        return result
    }

    public func unload(_ model: String) {
        _ = try? call(["op": "unload", "model": model])
        lock.withLock { _ = descriptors.removeValue(forKey: model) }
    }
}
