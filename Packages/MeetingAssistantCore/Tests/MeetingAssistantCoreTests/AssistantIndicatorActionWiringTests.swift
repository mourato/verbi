import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class AssistantIndicatorActionWiringTests: XCTestCase {
    private var settings: AppSettingsStore!
    private var originalIndicatorEnabled = false

    override func setUp() async throws {
        try await super.setUp()
        await RecordingExclusivityCoordinator.shared.endAssistant()
        await RecordingExclusivityCoordinator.shared.endRecording()
        settings = .shared
        originalIndicatorEnabled = settings.recordingIndicatorEnabled
        RecordingIndicatorProcessingStateStore.shared.reset()
        settings.isAssistantEnabled = true
        settings.recordingIndicatorEnabled = false
    }

    override func tearDown() async throws {
        RecordingIndicatorProcessingStateStore.shared.reset()
        settings.recordingIndicatorEnabled = originalIndicatorEnabled
        await RecordingExclusivityCoordinator.shared.endAssistant()
        await RecordingExclusivityCoordinator.shared.endRecording()
        try await super.tearDown()
    }

    func testAssistantIndicatorCancelActionInvokesAssistantCancellationPath() async {
        settings.recordingIndicatorEnabled = true

        let recorder = MockAssistantAudioRecorder()
        let indicator = FloatingRecordingIndicatorController(settingsStore: settings)
        let service = AssistantVoiceCommandService(
            audioRecorder: recorder,
            indicator: indicator,
            settings: settings,
        )

        await service.startRecording(flow: .assistantMode)
        XCTAssertTrue(service.isRecording)

        indicator.invokeCancelActionForTesting()
        await waitUntil(message: "Assistant cancellation should stop recording.") {
            !service.isRecording
        }

        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(recorder.stopCallCount, 1)
    }

    func testAssistantIndicatorStopActionInvokesAssistantStopAndProcessPath() async {
        settings.recordingIndicatorEnabled = true

        let recorder = MockAssistantAudioRecorder()
        recorder.nextStopURL = nil
        let indicator = FloatingRecordingIndicatorController(settingsStore: settings)
        let service = AssistantVoiceCommandService(
            audioRecorder: recorder,
            indicator: indicator,
            settings: settings,
        )

        settings.isAssistantIntegrationsEnabled = true
        await service.startRecording(flow: .integrationDispatch)
        XCTAssertTrue(service.isRecording)

        indicator.invokeStopActionForTesting()
        await waitUntil(message: "Assistant stop action should finish processing.") {
            !service.isRecording && !service.isProcessing
        }

        XCTAssertFalse(service.isRecording)
        XCTAssertFalse(service.isProcessing)
        XCTAssertEqual(recorder.stopCallCount, 1)
    }

    func testAssistantProcessingSnapshotTracksLifecycle() async {
        settings.recordingIndicatorEnabled = true

        let recorder = MockAssistantAudioRecorder()
        recorder.nextStopURL = nil
        let indicator = FloatingRecordingIndicatorController(settingsStore: settings)
        let service = AssistantVoiceCommandService(
            audioRecorder: recorder,
            indicator: indicator,
            settings: settings,
        )

        await service.startRecording(flow: .assistantMode)
        XCTAssertNil(indicator.processingSnapshot)

        indicator.invokeStopActionForTesting()
        await waitUntil(message: "Assistant processing should finish.") {
            !service.isProcessing
        }

        XCTAssertNil(indicator.processingSnapshot)
    }

    func testAssistantModeStartStillWorksWhenIntegrationsAreDisabled() async {
        settings.isAssistantIntegrationsEnabled = false

        let recorder = MockAssistantAudioRecorder()
        let indicator = FloatingRecordingIndicatorController(settingsStore: settings)
        let service = AssistantVoiceCommandService(
            audioRecorder: recorder,
            indicator: indicator,
            settings: settings,
        )

        await service.startRecording(flow: .assistantMode)

        XCTAssertTrue(service.isRecording)
        XCTAssertEqual(recorder.startCallCount, 1)
    }

    func testIntegrationDispatchStartIsBlockedWhenIntegrationsAreDisabled() async {
        settings.isAssistantIntegrationsEnabled = false

        let recorder = MockAssistantAudioRecorder()
        let indicator = FloatingRecordingIndicatorController(settingsStore: settings)
        let service = AssistantVoiceCommandService(
            audioRecorder: recorder,
            indicator: indicator,
            settings: settings,
        )

        await service.startRecording(flow: .integrationDispatch)

        XCTAssertFalse(service.isRecording)
        XCTAssertEqual(recorder.startCallCount, 0)
    }
}

@MainActor
private final class MockAssistantAudioRecorder: AssistantRecordingService {
    var isRecording = false
    var startCallCount = 0
    var stopCallCount = 0
    var nextStopURL: URL? = URL(fileURLWithPath: "/tmp/mock-assistant-audio.m4a")

    func startRecording(to _: URL, source _: RecordingSource, retryCount _: Int) async throws {
        startCallCount += 1
        isRecording = true
    }

    func stopRecording() async -> URL? {
        stopCallCount += 1
        isRecording = false
        return nextStopURL
    }

    func hasPermission() async -> Bool {
        true
    }

    func requestPermission() async {}
}
