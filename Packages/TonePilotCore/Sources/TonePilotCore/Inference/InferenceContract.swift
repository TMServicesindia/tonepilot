import Foundation

/// The contract every inference back-end must pass, run identically on Linux (replay), iOS /
/// macOS (Core ML) and Android (LiteRT via the C bridge): loading errors, use before load,
/// input validation, output shapes, numeric agreement with a reference within tolerance, and
/// unloading. Returns a report instead of asserting so each platform's test runner can use it.
public enum InferenceContract {
    public struct Fixture {
        public var descriptor: ModelDescriptor
        public var modelURL: URL
        public var inputs: [String: Tensor]
        public var expected: [String: Tensor]
        /// Max absolute difference allowed per value.
        public var tolerance: Float

        public init(descriptor: ModelDescriptor, modelURL: URL, inputs: [String: Tensor], expected: [String: Tensor], tolerance: Float) {
            self.descriptor = descriptor
            self.modelURL = modelURL
            self.inputs = inputs
            self.expected = expected
            self.tolerance = tolerance
        }
    }

    public struct Report: Codable, Sendable {
        public var backend: String
        public var checks: [String: Bool]
        public var notes: [String]
        /// Largest absolute difference per output.
        public var maxAbsDiff: [String: Float]
        public var runMilliseconds: Double
        public var passed: Bool { !checks.isEmpty && checks.values.allSatisfy { $0 } }
    }

    public static func run(_ backend: InferenceBackend, _ f: Fixture) -> Report {
        var checks: [String: Bool] = [:], notes: [String] = [], diffs: [String: Float] = [:]
        let name = f.descriptor.name
        func expectError(_ label: String, _ body: () throws -> Void, matches: (InferenceError) -> Bool) {
            do { try body(); checks[label] = false; notes.append("\(label): no error thrown") }
            catch let e as InferenceError { checks[label] = matches(e); if !matches(e) { notes.append("\(label): \(e)") } }
            catch { checks[label] = false; notes.append("\(label): \(error)") }
        }
        backend.unload(name)
        expectError("load-missing-file-fails", { try backend.load(f.descriptor, from: f.modelURL.appendingPathExtension("missing")) }) {
            if case .loadFailed = $0 { return true }; return false
        }
        expectError("run-before-load-fails", { _ = try backend.run(name, inputs: f.inputs) }) {
            if case .modelNotLoaded = $0 { return true }; return false
        }
        do {
            try backend.load(f.descriptor, from: f.modelURL)
            checks["load"] = backend.isLoaded(name)
        } catch {
            checks["load"] = false; notes.append("load: \(error)")
            return Report(backend: backend.id, checks: checks, notes: notes, maxAbsDiff: diffs, runMilliseconds: 0)
        }
        if let (key, t) = f.inputs.first {
            var wrong = f.inputs
            wrong[key] = try? Tensor(shape: t.shape.map { $0 == 1 ? 1 : max(1, $0 / 2) }, values: [Float](repeating: 0, count: t.shape.map { $0 == 1 ? 1 : max(1, $0 / 2) }.reduce(1, *)))
            expectError("wrong-shape-rejected", { _ = try backend.run(name, inputs: wrong) }) {
                if case .shapeMismatch = $0 { return true }; return false
            }
            expectError("missing-input-rejected", { _ = try backend.run(name, inputs: [:]) }) {
                if case .badInput = $0 { return true }; return false
            }
        }
        let start = Date()
        do {
            let out = try backend.run(name, inputs: f.inputs)
            let ms = Date().timeIntervalSince(start) * 1000
            do { try f.descriptor.validate(outputs: out); checks["output-shapes"] = true }
            catch { checks["output-shapes"] = false; notes.append("output-shapes: \(error)") }
            var within = true
            for (k, exp) in f.expected {
                guard let got = out[k], got.count == exp.count else { within = false; notes.append("numeric: \(k) missing"); continue }
                var m: Float = 0
                for i in 0..<exp.count { m = max(m, abs(got.values[i] - exp.values[i])) }
                diffs[k] = m
                if !(m <= f.tolerance) { within = false; notes.append("numeric: \(k) max |diff| \(m) > \(f.tolerance)") }
            }
            checks["numeric-tolerance"] = within
            backend.unload(name)
            checks["unload"] = !backend.isLoaded(name)
            return Report(backend: backend.id, checks: checks, notes: notes, maxAbsDiff: diffs, runMilliseconds: ms)
        } catch {
            checks["run"] = false; notes.append("run: \(error)")
            return Report(backend: backend.id, checks: checks, notes: notes, maxAbsDiff: diffs, runMilliseconds: 0)
        }
    }

    // MARK: Fixture files (raw little-endian float32 + descriptor JSON)

    public static func readFloats(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        guard data.count % 4 == 0 else { throw InferenceError.badInput("\(url.lastPathComponent): size not a multiple of 4") }
        return data.withUnsafeBytes { raw in (0..<data.count / 4).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self))) } }
    }

    /// Loads `<dir>/descriptor.json`, `<dir>/<input>.f32` and `<dir>/<output>.f32`.
    public static func loadFixture(dir: URL, modelURL: URL, tolerance: Float) throws -> Fixture {
        let d = try JSONDecoder().decode(ModelDescriptor.self, from: Data(contentsOf: dir.appendingPathComponent("descriptor.json")))
        var inputs: [String: Tensor] = [:], expected: [String: Tensor] = [:]
        for (k, shape) in d.inputs { inputs[k] = try Tensor(shape: shape, values: readFloats(dir.appendingPathComponent("\(k).f32"))) }
        for (k, shape) in d.outputs { expected[k] = try Tensor(shape: shape, values: readFloats(dir.appendingPathComponent("\(k).f32"))) }
        return Fixture(descriptor: d, modelURL: modelURL, inputs: inputs, expected: expected, tolerance: tolerance)
    }
}
