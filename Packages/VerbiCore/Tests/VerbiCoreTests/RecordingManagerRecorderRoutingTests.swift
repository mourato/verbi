@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

@MainActor
final class RecordingManagerRecorderRoutingTests: XCTestCase {
    private var manager: RecordingManager?

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsStore.shared.isMeetingTranscriptionEnabled = false
    }

    override func tearDown() async throws {
        await manager?.reset()
        manager = nil
        await RecordingExclusivityCoordinator.shared.endRecording()
        await RecordingExclusivityCoordinator.shared.endAssistant()
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testDictationStartUsesOnlyDictationRecorder() async {
        let dictation = MockAudioRecorder()
        let meeting = MockAudioRecorder()
        let manager = makeManager(dictation: dictation, meeting: meeting)
        self.manager = manager

        await manager.startCapture(purpose: .dictation)

        XCTAssertTrue(dictation.startRecordingCalled)
        XCTAssertFalse(meeting.startRecordingCalled)
        XCTAssertTrue(manager.isRecording)

        await manager.stopRecording(transcribe: false)

        XCTAssertEqual(dictation.stopRecordingCalledCount, 1)
        XCTAssertEqual(meeting.stopRecordingCalledCount, 0)
    }

    func testMeetingStartUsesOnlyMeetingRecorder() async {
        let dictation = MockAudioRecorder()
        let meeting = MockAudioRecorder()
        let manager = makeManager(dictation: dictation, meeting: meeting)
        self.manager = manager

        await manager.startCapture(purpose: .meeting)

        XCTAssertFalse(dictation.startRecordingCalled)
        XCTAssertTrue(meeting.startRecordingCalled)
        XCTAssertTrue(manager.isRecording)

        await manager.stopRecording(transcribe: false)

        XCTAssertEqual(dictation.stopRecordingCalledCount, 0)
        XCTAssertEqual(meeting.stopRecordingCalledCount, 1)
    }

    private func makeManager(dictation: MockAudioRecorder, meeting: MockAudioRecorder) -> RecordingManager {
        RecordingManager(
            dictationRecorder: dictation,
            meetingRecorder: meeting,
            systemRecorder: MockSystemAudioCapture(),
            transcriptionClient: MockTranscriptionClient(),
            postProcessingService: MockPostProcessingService(),
            storage: MockStorageService(),
            activeAppContextProvider: MockActiveAppContextProvider(),
            captureContextResolver: MockCaptureContextResolver(),
            apiKeyExists: { _ in true }
        )
    }
}
