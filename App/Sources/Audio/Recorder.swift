import AVFoundation
import Foundation
import os

/// Records what TonePilot plays — your Casio's tones (and the Song Arpeggio fill), plus the song
/// parts that are playing if chosen — straight from the audio engine, so everything is in sync
/// and nothing from the room is picked up. Recording can wait for your first key press; the
/// last 0.3 s before it are kept so the first note's attack isn't cut. On stop, the recording is
/// converted to MP3 (Mp3Encoder) in Documents/Recordings, also visible in the Files app.
final class Recorder: @unchecked Sendable {
    enum State: Equatable { case idle, waitingForKey, recording, saving(Double) }

    private let lock = OSAllocatedUnfairLock()
    private var file: AVAudioFile?
    private var tapNode: AVAudioNode?
    private var waiting = false
    private var preroll: [AVAudioPCMBuffer] = []
    private var prerollFrames: AVAudioFrameCount = 0
    private var framesWritten: AVAudioFramePosition = 0
    private var sampleRate: Double = 48_000
    private var peak: Float = 0
    private(set) var tempURL: URL?

    /// Seconds recorded so far and the level since the last call (read from the main thread).
    func status() -> (seconds: Double, peak: Float) {
        lock.withLock {
            let p = peak
            peak = 0
            return (Double(framesWritten) / sampleRate, p)
        }
    }

    var isWaiting: Bool { lock.withLock { waiting } }

    /// Starts capturing `node`'s output. With `waitForKey`, nothing is kept until `keyPressed()`.
    func start(node: AVAudioNode, waitForKey: Bool) throws {
        stopTap()
        let format = node.outputFormat(forBus: 0)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording-\(UUID().uuidString).caf")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
                                       AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
                                       AVLinearPCMIsNonInterleaved: true]
        let out = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        lock.withLock {
            file = out
            tempURL = url
            waiting = waitForKey
            preroll = []
            prerollFrames = 0
            framesWritten = 0
            sampleRate = format.sampleRate
        }
        let keep = AVAudioFrameCount(format.sampleRate * 0.3)
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.receive(buffer, keep: keep)
        }
        tapNode = node
    }

    /// Your first key press: recording begins (with the moment just before it).
    func keyPressed() {
        lock.withLock {
            guard waiting, let file else { return }
            waiting = false
            for b in preroll { try? file.write(from: b); framesWritten += AVAudioFramePosition(b.frameLength) }
            preroll = []
        }
    }

    private func receive(_ buffer: AVAudioPCMBuffer, keep: AVAudioFrameCount) {
        guard let copy = Self.stereoCopy(buffer) else { return }
        var level: Float = 0
        if let d = copy.floatChannelData {
            for c in 0..<2 { for i in 0..<Int(copy.frameLength) { level = max(level, abs(d[c][i])) } }
        }
        lock.withLock {
            peak = max(peak, level)
            guard let file else { return }
            if waiting {
                preroll.append(copy)
                prerollFrames += copy.frameLength
                while prerollFrames > keep, preroll.count > 1 { prerollFrames -= preroll.removeFirst().frameLength }
            } else {
                try? file.write(from: copy)
                framesWritten += AVAudioFramePosition(copy.frameLength)
            }
        }
    }

    /// Stops capturing. Returns the raw recording, or nil if nothing was recorded.
    func stop() -> URL? {
        stopTap()
        return lock.withLock {
            let url = tempURL, frames = framesWritten
            file = nil
            waiting = false
            preroll = []
            if frames == 0, let url { try? FileManager.default.removeItem(at: url); return nil }
            return url
        }
    }

    private func stopTap() {
        tapNode?.removeTap(onBus: 0)
        tapNode = nil
    }

    /// The tap's buffer is reused by the engine: copy it (as stereo, float, non-interleaved).
    static func stereoCopy(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let src = b.floatChannelData,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: b.format.sampleRate, channels: 2, interleaved: false),
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: b.frameLength), let dst = out.floatChannelData else { return nil }
        let n = Int(b.frameLength), channels = Int(b.format.channelCount)
        dst[0].update(from: src[0], count: n)
        dst[1].update(from: src[channels > 1 ? 1 : 0], count: n)
        out.frameLength = b.frameLength
        return out
    }
}

/// Saved recordings (MP3) in Documents/Recordings.
struct Recording: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let date: Date
    let duration: Double
    let bytes: Int64
    var name: String { url.deletingPathExtension().lastPathComponent }
}

enum RecordingsFolder {
    static var url: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func list() -> [Recording] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        let files = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? []
        return files.filter { $0.pathExtension.lowercased() == "mp3" }.map { f in
            let v = try? f.resourceValues(forKeys: Set(keys))
            let duration = (try? AVAudioFile(forReading: f)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 0
            return Recording(url: f, date: v?.creationDate ?? .distantPast, duration: duration, bytes: Int64(v?.fileSize ?? 0))
        }.sorted { $0.date > $1.date }
    }

    /// "Magale take 3" style names that don't overwrite each other.
    static func freshURL(base: String) -> URL {
        let clean = base.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        var n = 1
        var candidate = url.appendingPathComponent("\(clean).mp3")
        while FileManager.default.fileExists(atPath: candidate.path) {
            n += 1
            candidate = url.appendingPathComponent("\(clean) \(n).mp3")
        }
        return candidate
    }

    static func rename(_ r: Recording, to name: String) -> Bool {
        let clean = name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return false }
        let dest = url.appendingPathComponent("\(clean).mp3")
        guard !FileManager.default.fileExists(atPath: dest.path) else { return false }
        return (try? FileManager.default.moveItem(at: r.url, to: dest)) != nil
    }
}
