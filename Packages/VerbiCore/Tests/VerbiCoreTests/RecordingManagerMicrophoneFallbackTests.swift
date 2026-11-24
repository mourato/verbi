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

    func testSessionInputSourcePrefersCapturedDeviceAfterStop() {
        let mic = MockAudioRecorder()
        mic.activeMicrophoneDeviceName = "Fake Default Microphone"
        let manager = RecordingManager(
            micRecorder: mic,
            systemRecorder: MockSystemAudioCapture(),
            transcriptionClient: MockTranscriptionClient(),
            postProcessingService: MockPostProcessingService(),
            storage: MockStorageService()
        )
        manager.recordingSource = .microphone
        let meeting = CaptureSession(app: .unknown)
        var session = manager.makeTranscriptionSessionSnapshot(meeting)
        XCTAssertEqual(session.microphoneDeviceName, "Fake Default Microphone")

        mic.activeMicrophoneDeviceName = nil
        mic.activeMicrophoneDidFallBackToDefault = false

        XCTAssertEqual(manager.resolveInputSourceLabel(for: session), "Fake Default Microphone")
    }
}
