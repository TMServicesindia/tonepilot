import Foundation

/// Iterative radix-2 real-input FFT returning a magnitude spectrum.
/// Pure Swift so the analysis pipeline is testable on any platform; on iOS the
/// same interface could later be backed by Accelerate/vDSP for speed.
/// Not thread-safe: create one instance per analysis thread.
public final class MagnitudeFFT {
    public let size: Int
    private let log2n: Int
    private let cosTable: [Float]
    private let sinTable: [Float]
    private let bitReverse: [Int]
    private let window: [Float]
    private var re: [Float]
    private var im: [Float]

    /// - Parameter size: power of two, e.g. 2048.
    public init(size: Int) {
        precondition(size >= 2 && size & (size - 1) == 0, "FFT size must be a power of two")
        self.size = size
        var l = 0
        while (1 << l) < size { l += 1 }
        log2n = l
        cosTable = (0..<size / 2).map { Float(cos(2 * Double.pi * Double($0) / Double(size))) }
        sinTable = (0..<size / 2).map { Float(-sin(2 * Double.pi * Double($0) / Double(size))) }
        bitReverse = (0..<size).map { i in
            var r = 0, x = i
            for _ in 0..<l { r = (r << 1) | (x & 1); x >>= 1 }
            return r
        }
        // Periodic Hann window.
        window = (0..<size).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(size))) }
        re = [Float](repeating: 0, count: size)
        im = [Float](repeating: 0, count: size)
    }

    /// Windowed magnitude spectrum of `samples[offset ..< offset+size]` (zero-padded past the end).
    /// Writes `size/2 + 1` bins into `output`.
    public func magnitudes(_ samples: [Float], offset: Int, into output: inout [Float]) {
        let n = size
        for i in 0..<n {
            let j = offset + i
            re[bitReverse[i]] = (j >= 0 && j < samples.count) ? samples[j] * window[i] : 0
            im[bitReverse[i]] = 0
        }
        var half = 1
        while half < n {
            let step = n / (half * 2)
            var start = 0
            while start < n {
                var k = 0
                for j in start..<(start + half) {
                    let wr = cosTable[k], wi = sinTable[k]
                    let xr = re[j + half], xi = im[j + half]
                    let tr = wr * xr - wi * xi
                    let ti = wr * xi + wi * xr
                    re[j + half] = re[j] - tr
                    im[j + half] = im[j] - ti
                    re[j] += tr
                    im[j] += ti
                    k += step
                }
                start += half * 2
            }
            half *= 2
        }
        if output.count != n / 2 + 1 { output = [Float](repeating: 0, count: n / 2 + 1) }
        for k in 0...(n / 2) { output[k] = (re[k] * re[k] + im[k] * im[k]).squareRoot() }
    }
}
