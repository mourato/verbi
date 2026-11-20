import AVFoundation
import Foundation

/// In-memory audio helpers for remote incremental dictation windows.
///
/// All helpers are `nonisolated` so window encoding, silence analysis, and
/// error classification stay off the `@MainActor` during the stop path.
/// Nothing here logs or returns speech content.
public enum RemoteWindowAudioSupport {
    private enum Constants {
        static let sampleRate = 16000
        static let bitsPerSample = 16
        static let channels = 1
    }

    /// Encodes 16 kHz mono float samples as 16-bit PCM WAV data.
    public nonisolated static func wavData(from samples: [Float]) -> Data {
        var data = Data()
        let sampleCount = samples.count
        let byteRate = Constants.sampleRate * Constants.channels * Constants.bitsPerSample / 8
        let blockAlign = Constants.channels * Constants.bitsPerSample / 8
        let dataChunkSize = sampleCount * blockAlign

        func appendUInt32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        func appendUInt16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }

        data.append(contentsOf: "RIFF".utf8)
        appendUInt32(UInt32(36 + dataChunkSize))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(UInt16(Constants.channels))
        appendUInt32(UInt32(Constants.sampleRate))
        appendUInt32(UInt32(byteRate))
        appendUInt16(UInt16(blockAlign))
        appendUInt16(UInt16(Constants.bitsPerSample))
        data.append(contentsOf: "data".utf8)
        appendUInt32(UInt32(dataChunkSize))

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            appendUInt16(UInt16(bitPattern: Int16(clamped * Float(Int16.max))))
        }
        return data
    }

    /// Writes window samples to a temporary WAV file for a remote request.
    /// Callers own cleanup of the returned URL.
    public nonisolated static func writeTemporaryWAV(samples: [Float]) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("verbi-remote-window-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        try wavData(from: samples).write(to: url, options: .atomic)
        return url
    }

    /// Peak and RMS of in-memory samples. Pure computation, no logging.
    public nonisolated static func silenceMetrics(samples: [Float]) -> (peak: Float, rms: Float) {
        guard !samples.isEmpty else { return (0, 0) }
        var peak: Float = 0
        var sumSquares: Float = 0
        for sample in samples {
            let magnitude = abs(sample)
            if magnitude > peak {
                peak = magnitude
            }
            sumSquares += sample * sample
        }
        return (peak, sqrt(sumSquares / Float(samples.count)))
    }

    /// Peak and RMS of an audio file, read fully off the caller's thread.
    /// Returns nil when the file cannot be decoded.
    public nonisolated static func silenceMetrics(for audioURL: URL) -> (peak: Float, rms: Float)? {
        guard let file = try? AVAudioFile(forReading: audioURL),
              file.length > 0
        else { return nil }
        let frameCount = AVAudioFrameCount(min(file.length, 16000 * 30))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else { return nil }
        do {
            try file.read(into: buffer, frameCount: frameCount)
        } catch {
            return nil
        }
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else { return nil }
        let frames = UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength))
        var peak: Float = 0
        var sumSquares: Float = 0
        for sample in frames {
            let magnitude = abs(sample)
            if magnitude > peak {
                peak = magnitude
            }
            sumSquares += sample * sample
        }
        return (peak, sqrt(sumSquares / Float(frames.count)))
    }

    /// Whether an error message signals a remote rate limit (HTTP 429 family).
    /// Inspects only the provider status text, never speech content.
    public nonisolated static func isRateLimited(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("429")
            || message.contains("rate limit")
            || message.contains("rate_limit")
            || message.contains("too many requests")
    }
}
