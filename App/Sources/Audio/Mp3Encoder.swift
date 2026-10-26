import AVFoundation
import Foundation

/// Converts a recording (any file AVAudioFile reads) to MP3 with LAME 3.100: 44.1 or 48 kHz
/// stereo, 256 kbit/s, high-quality encoding. Runs in chunks, so memory stays small.
enum Mp3Encoder {
    enum Failure: LocalizedError {
        case read(String), encoder, write(String)
        var errorDescription: String? {
            switch self {
            case .read(let m): return "The recording couldn't be read (\(m))."
            case .encoder: return "The MP3 encoder couldn't start."
            case .write(let m): return "The MP3 couldn't be saved (\(m))."
            }
        }
    }

    static let bitrate: Int32 = 256

    /// - Returns: the MP3's duration in seconds.
    @discardableResult
    static func encode(_ input: URL, to output: URL, progress: ((Double) -> Void)? = nil) throws -> Double {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: input) } catch { throw Failure.read(error.localizedDescription) }
        let format = file.processingFormat
        let rate = format.sampleRate, channels = Int(format.channelCount)
        guard let lame = lame_init() else { throw Failure.encoder }
        defer { lame_close(lame) }
        lame_set_in_samplerate(lame, Int32(rate))
        lame_set_out_samplerate(lame, Int32(rate))
        lame_set_num_channels(lame, 2)
        lame_set_mode(lame, JOINT_STEREO)
        lame_set_brate(lame, bitrate)
        lame_set_quality(lame, 2)
        guard lame_init_params(lame) >= 0 else { throw Failure.encoder }

        FileManager.default.createFile(atPath: output.path, contents: nil)
        guard let out = try? FileHandle(forWritingTo: output) else { throw Failure.write("can't create the file") }
        defer { try? out.close() }

        let chunk: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { throw Failure.encoder }
        var mp3 = [UInt8](repeating: 0, count: Int(chunk) * 5 / 4 + 7_200)
        let total = max(1, Double(file.length))
        var read: Double = 0
        // Read exactly up to the end (asking for frames past it can throw).
        while file.framePosition < file.length {
            let want = AVAudioFrameCount(min(AVAudioFramePosition(chunk), file.length - file.framePosition))
            do { try file.read(into: buffer, frameCount: want) } catch { throw Failure.read(error.localizedDescription) }
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let data = buffer.floatChannelData else { throw Failure.read("unsupported format") }
            let left = data[0], right = data[channels > 1 ? 1 : 0]
            let written = mp3.withUnsafeMutableBufferPointer { m in
                lame_encode_buffer_ieee_float(lame, left, right, Int32(n), m.baseAddress, Int32(m.count))
            }
            guard written >= 0 else { throw Failure.encoder }
            out.write(Data(mp3[0..<Int(written)]))
            read += Double(n)
            progress?(read / total)
        }
        let flushed = mp3.withUnsafeMutableBufferPointer { m in lame_encode_flush(lame, m.baseAddress, Int32(m.count)) }
        if flushed > 0 { out.write(Data(mp3[0..<Int(flushed)])) }
        return read / rate
    }
}
