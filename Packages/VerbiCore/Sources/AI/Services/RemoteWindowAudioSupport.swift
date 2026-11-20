import AVFoundation
import Foundation

/// Typed rate-limit error (HTTP 429) thrown by remote transcription clients
/// so incremental window batching can fail fast and classify throttling even
/// when the provider's JSON error body omits `"429"`.
public struct RemoteTranscriptionRateLimitError: LocalizedError, Sendable {
    public let provider: String
    public let statusCode: Int
    public let message: String

    public init(provider: String, statusCode: Int = 429, message: String) {
        self.provider = provider
        self.statusCode = statusCode
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}

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
        static let silenceAnalysisMaxSeconds = 30.0
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

    /// Peak and RMS of in-memory samples. Pure computation, no logging.
    public nonisolated static func silenceMetrics(samples: [Float]) -> (peak: Float, rms: Float) {
        computePeakAndRMS(samples, count: samples.count)
    }

    /// Peak and RMS of an audio file, read fully off the caller's thread.
    /// Returns nil when the file cannot be decoded.
    public nonisolated static func silenceMetrics(for audioURL: URL) -> (peak: Float, rms: Float)? {
        guard let buffer = readLeadingAudioBuffer(from: audioURL),
              let channelData = buffer.floatChannelData,
              buffer.frameLength > 0
        else { return nil }
        let frames = UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength))
        return computePeakAndRMS(frames, count: frames.count)
    }

    private nonisolated static func readLeadingAudioBuffer(from audioURL: URL) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: audioURL), file.length > 0 else { return nil }
        let frameCount = silenceAnalysisFrameCount(for: file)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: frameCount
        ) else { return nil }
        do {
            try file.read(into: buffer, frameCount: frameCount)
            return buffer
        } catch {
            return nil
        }
    }

    private nonisolated static func silenceAnalysisFrameCount(for file: AVAudioFile) -> AVAudioFrameCount {
        let sampleRate = file.processingFormat.sampleRate > 0
            ? file.processingFormat.sampleRate
            : Double(Constants.sampleRate)
        let maxFrames = AVAudioFramePosition(max(1, sampleRate * Constants.silenceAnalysisMaxSeconds))
        return AVAudioFrameCount(min(file.length, maxFrames))
    }

    /// Whether an error signals a remote rate limit (HTTP 429 family).
    /// Inspects typed status errors and provider status text only, never speech content.
    public nonisolated static func isRateLimited(_ error: Error) -> Bool {
        if error is RemoteTranscriptionRateLimitError {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("429")
            || message.contains("rate limit")
            || message.contains("rate_limit")
            || message.contains("too many requests")
    }

    private nonisolated static func computePeakAndRMS(
        _ samples: some Sequence<Float>,
        count: Int
    ) -> (peak: Float, rms: Float) {
        guard count > 0 else { return (0, 0) }
        var peak: Float = 0
        var sumSquares: Float = 0
        for sample in samples {
            let magnitude = abs(sample)
            if magnitude > peak {
                peak = magnitude
            }
            sumSquares += sample * sample
        }
        return (peak, sqrt(sumSquares / Float(count)))
    }
}
