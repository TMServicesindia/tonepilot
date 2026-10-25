import AVFoundation
import TonePilotCore

enum AudioDecodeError: LocalizedError {
    case unreadable(String)
    case converterUnavailable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadable(let why): return "Could not read this audio file: \(why)"
        case .converterUnavailable: return "This audio format cannot be converted for analysis."
        case .cancelled: return "Decoding was cancelled."
        }
    }
}

/// Decodes MP3/M4A/WAV/AIFF (anything AVAudioFile reads) into mono Float samples at the
/// analysis sample rate. Runs on a background task; memory ≈ 5 MB per minute of audio.
enum AudioFileDecoder {
    static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Mono at the file's own sample rate (for user samples, where resampling would waste quality).
    static func decodeMonoNative(url: URL) throws -> (frames: [Float], sampleRate: Double) {
        let rate: Double
        do { rate = try AVAudioFile(forReading: url).processingFormat.sampleRate } catch {
            throw AudioDecodeError.unreadable(error.localizedDescription)
        }
        let buffer = try decodeMono(url: url, sampleRate: rate)
        return (buffer.samples, rate)
    }

    static func decodeMono(url: URL, sampleRate: Double = AnalysisConfig().sampleRate) throws -> TonePilotCore.AudioBuffer {
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) } catch { throw AudioDecodeError.unreadable(error.localizedDescription) }
        let inFormat = file.processingFormat
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: 32_768),
              let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: 32_768) else {
            throw AudioDecodeError.converterUnavailable
        }
        converter.downmix = true // average stereo channels instead of dropping one

        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * sampleRate / inFormat.sampleRate) + 1024)
        var reachedEnd = false

        while true {
            if Task.isCancelled { throw AudioDecodeError.cancelled }
            outBuffer.frameLength = 0
            var convertError: NSError?
            let status = converter.convert(to: outBuffer, error: &convertError) { _, inputStatus in
                if reachedEnd { inputStatus.pointee = .endOfStream; return nil }
                do {
                    try file.read(into: inBuffer)
                } catch {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if inBuffer.frameLength == 0 {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if status == .error {
                throw AudioDecodeError.unreadable(convertError?.localizedDescription ?? "conversion failed")
            }
            if let ch = outBuffer.floatChannelData?[0], outBuffer.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: ch, count: Int(outBuffer.frameLength)))
            }
            if status == .endOfStream || (status == .inputRanDry && reachedEnd) { break }
        }
        return TonePilotCore.AudioBuffer(samples: samples, sampleRate: sampleRate)
    }
}
