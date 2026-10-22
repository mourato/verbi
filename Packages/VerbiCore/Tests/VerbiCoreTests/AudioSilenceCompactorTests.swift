import AVFoundation
@testable import VerbiCore
@testable import VerbiCoreAudio
import XCTest

final class AudioSilenceCompactorTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var compactor: AudioSilenceCompactor!

    override func setUp() async throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioSilenceCompactorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        compactor = AudioSilenceCompactor()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectoryURL)
        tempDirectoryURL = nil
        compactor = nil
    }

    func testCompactForTranscription_RemovesLeadingAndTrailingSilence() async throws {
        let inputURL = try makeAudioFile(
            named: "trim-edges",
            segments: [.silence(1.0), .tone(1.0, amplitude: 0.3), .silence(1.0)],
        )
        let outputURL = tempDirectoryURL.appendingPathComponent("trim-edges-output.wav")

        let result = try await compactor.compactForTranscription(
            inputURL: inputURL,
            outputURL: outputURL,
            format: .wav,
        )

        XCTAssertTrue(result.wasCompacted)
        XCTAssertLessThan(result.compactedDuration, result.originalDuration)
        XCTAssertGreaterThan(result.removedDuration, 1.0)
    }

    func testCompactForTranscription_RemovesInternalLongSilence() async throws {
        let inputURL = try makeAudioFile(
            named: "trim-middle",
            segments: [.tone(1.0, amplitude: 0.3), .silence(1.2), .tone(1.0, amplitude: 0.3)],
        )
        let outputURL = tempDirectoryURL.appendingPathComponent("trim-middle-output.wav")

        let result = try await compactor.compactForTranscription(
            inputURL: inputURL,
            outputURL: outputURL,
            format: .wav,
        )

        XCTAssertTrue(result.wasCompacted)
        XCTAssertGreaterThan(result.removedDuration, 0.7)
    }

    func testCompactForTranscription_PreservesShortPause() async throws {
        let inputURL = try makeAudioFile(
            named: "short-pause",
            segments: [.tone(1.0, amplitude: 0.3), .silence(0.5), .tone(1.0, amplitude: 0.3)],
        )
        let outputURL = tempDirectoryURL.appendingPathComponent("short-pause-output.wav")

        let result = try await compactor.compactForTranscription(
            inputURL: inputURL,
            outputURL: outputURL,
            format: .wav,
        )

        XCTAssertFalse(result.wasCompacted)
        XCTAssertEqual(result.outputURL, inputURL)
    }

    func testCompactForTranscription_PreservesLowSpeechAboveThreshold() async throws {
        let inputURL = try makeAudioFile(
            named: "low-speech",
            segments: [.silence(1.0), .tone(1.0, amplitude: 0.01), .silence(1.0)],
        )
        let outputURL = tempDirectoryURL.appendingPathComponent("low-speech-output.wav")

        let result = try await compactor.compactForTranscription(
            inputURL: inputURL,
            outputURL: outputURL,
            format: .wav,
        )

        XCTAssertTrue(result.wasCompacted)
        XCTAssertGreaterThan(result.compactedDuration, 0.9)
    }

    func testCompactForTranscription_FallsBackWhenInputIsEffectivelySilence() async throws {
        let inputURL = try makeAudioFile(
            named: "all-silence",
            segments: [.silence(2.0)],
        )
        let outputURL = tempDirectoryURL.appendingPathComponent("all-silence-output.wav")

        let result = try await compactor.compactForTranscription(
            inputURL: inputURL,
            outputURL: outputURL,
            format: .wav,
        )

        XCTAssertFalse(result.wasCompacted)
        XCTAssertEqual(result.outputURL, inputURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testCompactForTranscription_PreservesRequestedOutputFormat() async throws {
        let inputURL = try makeAudioFile(
            named: "format-source",
            segments: [.silence(1.0), .tone(1.0, amplitude: 0.3), .silence(1.0)],
            format: .wav,
        )
        let outputURL = tempDirectoryURL.appendingPathComponent("format-output.m4a")

        let result = try await compactor.compactForTranscription(
            inputURL: inputURL,
            outputURL: outputURL,
            format: .m4a,
        )

        XCTAssertTrue(result.wasCompacted)
        XCTAssertEqual(result.outputURL.pathExtension.lowercased(), "m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    private func makeAudioFile(
        named name: String,
        segments: [TestSegment],
        format: AppSettingsStore.AudioFormat = .wav,
    ) throws -> URL {
        let url = tempDirectoryURL.appendingPathComponent(name).appendingPathExtension(format.fileExtension)
        let sampleRate = 16_000.0
        let settings: [String: Any] = switch format {
        case .m4a:
            [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
            ]
        case .wav:
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: true,
            ]
        }

        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false,
        )

        for segment in segments {
            let frameCount = AVAudioFrameCount(sampleRate * segment.duration)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: frameCount,
            ) else {
                XCTFail("Failed to allocate audio buffer for test segment")
                continue
            }

            buffer.frameLength = frameCount
            if let channelData = buffer.floatChannelData {
                for frameIndex in 0..<Int(frameCount) {
                    channelData[0][frameIndex] = segment.sample(at: frameIndex, sampleRate: sampleRate)
                }
            }

            try audioFile.write(from: buffer)
        }

        return url
    }
}

private struct TestSegment {
    let duration: Double
    let amplitude: Float

    static func silence(_ duration: Double) -> TestSegment {
        TestSegment(duration: duration, amplitude: 0)
    }

    static func tone(_ duration: Double, amplitude: Float) -> TestSegment {
        TestSegment(duration: duration, amplitude: amplitude)
    }

    func sample(at frameIndex: Int, sampleRate: Double) -> Float {
        guard amplitude != 0 else { return 0 }
        let angle = 2 * Double.pi * Double(frameIndex) * 440.0 / sampleRate
        return sin(Float(angle)) * amplitude
    }
}
