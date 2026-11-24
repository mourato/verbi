import Combine
import Foundation
@testable import VerbiCore
@testable import VerbiCoreAudio
@testable import VerbiCoreUI
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

    func testUnexpectedRecorderStopShowsIndicatorError() async {
        let recorder = MockAssistantAudioRecorder()
        let indicator = FloatingRecordingIndicatorController(settingsStore: settings)
        let service = AssistantVoiceCommandService(
            audioRecorder: recorder,
            indicator: indicator,
            settings: settings,
        )

        await service.startRecording(flow: .assistantMode)
        XCTAssertTrue(service.isRecording)

        recorder.recorderDidStop.send(false)
        await waitUntil(timeout: .seconds(5), message: "Assistant should surface the recorder failure.") {
            !service.isRecording
        }

        XCTAssertFalse(service.isRecording)
        XCTAssertTrue(indicator.isVisible)
        guard case .error = indicator.renderState.mode else {
            XCTFail("Expected indicator error mode, got \(indicator.renderState.mode)")
            return
        }
        let canBeginAgain = await RecordingExclusivityCoordinator.shared.beginAssistant()
        XCTAssertTrue(canBeginAgain)
        await RecordingExclusivityCoordinator.shared.endAssistant()
    }

    func testValidationExhaustionShowsIndicatorError() async throws {
        let fake = try FakeMicrophoneCaptureSession()
        let recorder = AudioRecorder(microphoneCaptureFactory: { onBuffer, onFailure in
            fake.setCallbacks(onBuffer: onBuffer, onFailure: onFailure)
            return fake
        })
        recorder.microphonePermissionValidator = {}
        recorder.validationInterval = 3600
        defer { _ = await recorder.stopRecording() }

        let indicator = FloatingRecordingIndicatorController(settingsStore: settings)
        let service = AssistantVoiceCommandService(
            audioRecorder: FakeSessionAssistantRecorder(recorder: recorder),
            indicator: indicator,
            settings: settings,
        )

        await service.startRecording(flow: .assistantMode)
        XCTAssertTrue(service.isRecording)

        let url = try XCTUnwrap(recorder.currentRecordingURL)
        let firstSessionID = try XCTUnwrap(recorder.activeValidationSessionID)
        await recorder.handleValidationTimeout(url: url, source: .microphone, retryCount: 0, sessionID: firstSessionID)
        let secondSessionID = try XCTUnwrap(recorder.activeValidationSessionID)
        await recorder.handleValidationTimeout(url: url, source: .microphone, retryCount: 1, sessionID: secondSessionID)

        await waitUntil(timeout: .seconds(5), message: "Assistant should surface the recorder failure.") {
            !service.isRecording
        }

        XCTAssertFalse(service.isRecording)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertTrue(indicator.isVisible)
        guard case .error = indicator.renderState.mode else {
            XCTFail("Expected indicator error mode, got \(indicator.renderState.mode)")
            return
        }
    }
}

@MainActor
private final class FakeSessionAssistantRecorder: AssistantRecordingService {
    private let recorder: AudioRecorder

    init(recorder: AudioRecorder) {
        self.recorder = recorder
    }

    var isRecording: Bool {
        recorder.isRecording
    }

    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        recorder.isRecordingPublisher
    }

    func startRecording(to outputURL: URL, source: RecordingSource, retryCount: Int) async throws {
        try await recorder.startRecording(to: outputURL, source: source, retryCount: retryCount)
    }

    func stopRecording() async -> URL? {
        await recorder.stopRecording()
    }

    func hasPermission() async -> Bool {
        await MainActor.run { recorder.hasPermission() }
    }

    func requestPermission() async {
        await recorder.requestPermission()
    }
}

@MainActor
private final class MockAssistantAudioRecorder: AssistantRecordingService {
    var isRecording = false
    var startCallCount = 0
    var stopCallCount = 0
    var nextStopURL: URL? = URL(fileURLWithPath: "/tmp/mock-assistant-audio.m4a")
    let recorderDidStop = PassthroughSubject<Bool, Never>()

    var isRecordingPublisher: AnyPublisher<Bool, Never> {
        recorderDidStop.eraseToAnyPublisher()
    }

    func startRecording(to _: URL, source _: RecordingSource, retryCount _: Int) async throws {
        await Task.yield()
        startCallCount += 1
        isRecording = true
    }

    func stopRecording() async -> URL? {
        await Task.yield()
        stopCallCount += 1
        isRecording = false
        return nextStopURL
    }

    func hasPermission() async -> Bool {
        await Task.yield()
        return true
    }

    func requestPermission() async {
        await Task.yield()
    }
}
