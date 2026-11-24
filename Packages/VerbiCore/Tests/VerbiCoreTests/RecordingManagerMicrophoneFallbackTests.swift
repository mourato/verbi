@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

@MainActor
final class RecordingManagerMicrophoneFallbackTests: XCTestCase {
    func testMicrophoneLabelPrefersActiveCaptureDevice() {
        let mic = MockAudioRecorder()
        mic.activeMicrophoneDeviceName = "Fake USB Microphone"
        let manager = RecordingManager(
            micRecorder: mic,
            systemRecorder: MockSystemAudioCapture(),
            transcriptionClient: MockTranscriptionClient(),
            postProcessingService: MockPostProcessingService(),
            storage: MockStorageService()
        )

        XCTAssertEqual(manager.resolveMicrophoneDeviceName(), "Fake USB Microphone")
        XCTAssertNil(manager.microphoneFallbackNoticeDeviceName())

        mic.activeMicrophoneDidFallBackToDefault = true

        XCTAssertEqual(manager.microphoneFallbackNoticeDeviceName(), "Fake USB Microphone")
    }
}
