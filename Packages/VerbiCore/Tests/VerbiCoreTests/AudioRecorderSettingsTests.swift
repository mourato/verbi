@preconcurrency import AVFoundation
@testable import VerbiCoreAudio
import XCTest

final class AudioRecorderSettingsTests: XCTestCase {
    private func makeRecorder(fileExtension: String) throws -> (AVAudioRecorder, [String: Any]) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-settings-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let settings = AudioRecorder.recorderSettings(
            for: url,
            sampleRate: 48000,
            channels: 1,
            aacSettings: [AVEncoderBitRateKey: 128_000]
        )
        return try (AVAudioRecorder(url: url, settings: settings), settings)
    }

    func testWAVOutputUsesLinearPCMThatAVAudioRecorderAccepts() throws {
        let (_, settings) = try makeRecorder(fileExtension: "wav")
        XCTAssertEqual(settings[AVFormatIDKey] as? AudioFormatID, kAudioFormatLinearPCM)
    }

    func testM4AOutputUsesAACThatAVAudioRecorderAccepts() throws {
        let (_, settings) = try makeRecorder(fileExtension: "m4a")
        XCTAssertEqual(settings[AVFormatIDKey] as? AudioFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(settings[AVEncoderBitRateKey] as? Int, 128_000)
    }

    func testAACIntoWAVIsRejectedSoTheMatchingMatters() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recorder-settings-\(UUID().uuidString).wav")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let aacSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 1
        ]
        XCTAssertThrowsError(try AVAudioRecorder(url: url, settings: aacSettings))
    }
}
