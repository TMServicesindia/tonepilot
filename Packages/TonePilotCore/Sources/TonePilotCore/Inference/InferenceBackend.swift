import Foundation

/// A dense float tensor: shape + row-major values. The only data type that crosses the
/// inference boundary, so every back-end (Core ML, LiteRT, replay) sees the same contract.
public struct Tensor: Equatable, Sendable {
    public var shape: [Int]
    public var values: [Float]

    public init(shape: [Int], values: [Float]) throws {
        let count = shape.reduce(1, *)
        guard shape.allSatisfy({ $0 > 0 }), count == values.count else {
            throw InferenceError.badInput("tensor shape \(shape) needs \(count) values, got \(values.count)")
        }
        self.shape = shape
        self.values = values
    }

    public var count: Int { values.count }
}

public enum InferenceError: Error, Equatable, CustomStringConvertible {
    case modelNotLoaded(String)
    case loadFailed(model: String, reason: String)
    case badInput(String)
    case shapeMismatch(name: String, expected: [Int], got: [Int])
    case missingOutput(String)
    case backendFailure(String)

    public var description: String {
        switch self {
        case .modelNotLoaded(let m): return "model \(m) is not loaded"
        case .loadFailed(let m, let r): return "model \(m) failed to load: \(r)"
        case .badInput(let r): return "bad input: \(r)"
        case .shapeMismatch(let n, let e, let g): return "\(n): expected shape \(e), got \(g)"
        case .missingOutput(let n): return "output \(n) missing"
        case .backendFailure(let r): return "back-end failure: \(r)"
        }
    }
}

/// What a model takes and returns, in TonePilot's own (logical) tensor names, plus the name each
/// back-end uses for the same tensor (Core ML feature names, LiteRT signature keys…).
public struct ModelDescriptor: Codable, Equatable, Sendable {
    public var name: String
    /// Logical input name → shape.
    public var inputs: [String: [Int]]
    /// Logical output name → shape.
    public var outputs: [String: [Int]]
    /// Back-end id ("coreml", "litert", …) → logical name → that back-end's tensor name.
    public var backendNames: [String: [String: String]]

    public init(name: String, inputs: [String: [Int]], outputs: [String: [Int]], backendNames: [String: [String: String]] = [:]) {
        self.name = name
        self.inputs = inputs
        self.outputs = outputs
        self.backendNames = backendNames
    }

    /// The back-end's name for a logical tensor (the logical name when none is mapped).
    public func backendName(_ logical: String, for backend: String) -> String { backendNames[backend]?[logical] ?? logical }

    /// Checks names and shapes of inputs before a run (shared by every back-end).
    public func validate(inputs given: [String: Tensor]) throws {
        for (name, shape) in inputs {
            guard let t = given[name] else { throw InferenceError.badInput("missing input \(name)") }
            guard t.shape == shape else { throw InferenceError.shapeMismatch(name: name, expected: shape, got: t.shape) }
        }
        if let extra = given.keys.sorted().first(where: { inputs[$0] == nil }) { throw InferenceError.badInput("unknown input \(extra)") }
    }

    /// Checks that a run returned every output with the declared shape.
    public func validate(outputs got: [String: Tensor]) throws {
        for (name, shape) in outputs {
            guard let t = got[name] else { throw InferenceError.missingOutput(name) }
            guard t.shape == shape else { throw InferenceError.shapeMismatch(name: name, expected: shape, got: t.shape) }
        }
    }
}

/// Runs neural models for TonePilotCore. iOS implements it with Core ML, Android with LiteRT
/// (through the C bridge), tests with `ReplayBackend`. Analysis code only ever talks to this.
public protocol InferenceBackend: AnyObject, Sendable {
    /// "coreml", "litert", "replay", …
    var id: String { get }
    /// Loads (or reloads) a model file for `descriptor`. Throws `loadFailed` with a reason.
    func load(_ descriptor: ModelDescriptor, from url: URL) throws
    func isLoaded(_ model: String) -> Bool
    /// Runs a loaded model. Inputs and outputs use logical names and are validated against the
    /// descriptor (`badInput`, `shapeMismatch`, `missingOutput`, `modelNotLoaded`).
    func run(_ model: String, inputs: [String: Tensor]) throws -> [String: Tensor]
    func unload(_ model: String)
}

/// The back-end the platform registered at launch (none = no neural features available).
public enum InferenceRegistry {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: InferenceBackend?

    public static var backend: InferenceBackend? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

// MARK: - Replay back-end (tests, deterministic)

/// Returns recorded outputs for a model, after validating inputs exactly like a real back-end.
/// It proves the contract and the code around inference, **not** real model compatibility —
/// that is what the Core ML and LiteRT contract runs are for.
public final class ReplayBackend: InferenceBackend, @unchecked Sendable {
    public let id = "replay"
    private let lock = NSLock()
    private var descriptors: [String: ModelDescriptor] = [:]
    private var recordings: [String: [String: Tensor]] = [:]

    public init() {}

    /// Registers what `model` returns; `load` must still be called before `run`.
    public func record(_ model: String, outputs: [String: Tensor]) { lock.withLock { recordings[model] = outputs } }

    public func load(_ descriptor: ModelDescriptor, from url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw InferenceError.loadFailed(model: descriptor.name, reason: "file not found: \(url.lastPathComponent)")
        }
        lock.withLock { descriptors[descriptor.name] = descriptor }
    }

    public func isLoaded(_ model: String) -> Bool { lock.withLock { descriptors[model] != nil } }

    public func run(_ model: String, inputs: [String: Tensor]) throws -> [String: Tensor] {
        let (descriptor, outputs) = lock.withLock { (descriptors[model], recordings[model]) }
        guard let descriptor else { throw InferenceError.modelNotLoaded(model) }
        try descriptor.validate(inputs: inputs)
        guard let outputs else { throw InferenceError.backendFailure("no recording for \(model)") }
        try descriptor.validate(outputs: outputs)
        return outputs
    }

    public func unload(_ model: String) { lock.withLock { _ = descriptors.removeValue(forKey: model) } }
}
