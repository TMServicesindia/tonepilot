import Foundation

/// Splits a song into overlapping blocks for stem separation, so blocks can be separated in
/// parallel and written to disk as they finish (memory stays bounded on a phone).
public struct StemChunkPlan: Sendable {
    public struct Chunk: Sendable, Equatable {
        public let index: Int
        /// Input frames [start, end), including the overlap on each side.
        public let start: Int
        public let end: Int
        public var length: Int { end - start }
    }

    public let total: Int
    public let chunkLength: Int
    public let overlap: Int
    public let chunks: [Chunk]

    /// - Parameters:
    ///   - total: frames in the song.
    ///   - chunkLength: frames each block owns (must be more than twice `overlap`).
    ///   - overlap: frames shared with each neighbour, cross-faded when merging.
    public init(total: Int, chunkLength: Int, overlap: Int) {
        let total = max(0, total), length = max(1, chunkLength), ov = max(0, min(overlap, (length - 1) / 2))
        self.total = total
        self.chunkLength = length
        self.overlap = ov
        let count = total == 0 ? 0 : (total + length - 1) / length
        chunks = (0..<count).map { k in
            Chunk(index: k, start: max(0, k * length - ov), end: min(total, (k + 1) * length + ov))
        }
    }
}

/// Joins separated blocks back into continuous tracks with a linear cross-fade over each overlap.
/// Feed blocks in order; each call returns the frames that are now final.
public struct StemMerger: Sendable {
    public let plan: StemChunkPlan
    public let trackCount: Int
    private var tail: [[Float]] = []
    private var emitted = 0
    private var next = 0

    public init(plan: StemChunkPlan, trackCount: Int) {
        self.plan = plan
        self.trackCount = trackCount
    }

    /// `output[track]` holds the block's frames for its input range. Returns finished frames per
    /// track, continuing from where the previous call stopped.
    public mutating func add(_ index: Int, _ output: [[Float]]) -> [[Float]] {
        precondition(index == next, "blocks must be merged in order")
        next += 1
        let chunk = plan.chunks[index]
        let isLast = index == plan.chunks.count - 1
        let boundary = index * plan.chunkLength
        let blendStart = boundary - plan.overlap
        let emitEnd = isLast ? plan.total : (index + 1) * plan.chunkLength - plan.overlap
        var out = [[Float]](repeating: [], count: trackCount)
        let width = Float(max(1, 2 * plan.overlap))
        for t in 0..<trackCount {
            let o = output[t]
            var dst = [Float]()
            dst.reserveCapacity(max(0, emitEnd - emitted))
            for f in emitted..<emitEnd {
                let local = f - chunk.start
                let v = local < o.count ? o[local] : 0
                if index > 0, f - blendStart < tail[t].count {
                    let w = Float(f - blendStart) / width
                    dst.append(tail[t][f - blendStart] * (1 - w) + v * w)
                } else {
                    dst.append(v)
                }
            }
            out[t] = dst
        }
        if !isLast {
            let from = emitEnd - chunk.start
            tail = output.map { o in from < o.count ? Array(o[from...]) : [] }
        }
        emitted = emitEnd
        return out
    }
}
