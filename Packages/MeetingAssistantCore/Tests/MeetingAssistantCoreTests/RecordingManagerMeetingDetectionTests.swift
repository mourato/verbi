import Combine
import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class RecordingManagerMeetingDetectionTests: XCTestCase {
    private var manager: RecordingManager?
    private var mockMic: MockAudioRecorder?
    private var mockSystem: MockAudioRecorder?
    private var mockTranscription: MockTranscriptionClient?
    private var mockPostProcessing: MockPostProcessingService?
    private var mockStorage: MockStorageService?
    private var mockCaptureContextResolver: MockCaptureContextResolver?

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsStore.shared.isMeetingTranscriptionEnabled = true
        let mic = MockAudioRecorder()
        let system = MockAudioRecorder()
        let transcription = MockTranscriptionClient()
        let postProcessing = MockPostProcessingService()
        let storage = MockStorageService()
        let resolver = MockCaptureContextResolver()
        mockMic = mic
        mockSystem = system
        mockTranscription = transcription
        mockPostProcessing = postProcessing
        mockStorage = storage
        mockCaptureContextResolver = resolver
        manager = RecordingManager(
            micRecorder: mic,
            systemRecorder: system,
            transcriptionClient: transcription,
            postProcessingService: postProcessing,
            storage: storage,
            activeAppContextProvider: MockActiveAppContextProvider(),
            captureContextResolver: resolver,
            apiKeyExists: { _ in true }
        )
    }

    override func tearDown() async throws {
        await manager?.reset()
        manager = nil
        mockMic = nil
        mockSystem = nil
        mockTranscription = nil
        mockPostProcessing = nil
        mockStorage = nil
        mockCaptureContextResolver = nil
        await RecordingExclusivityCoordinator.shared.endRecording()
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testToastWithoutSummaryOnlyDisablesCapturedSession() async throws {
        let manager = try XCTUnwrap(manager)
        let settings = AppSettingsStore.shared
        settings.meetingDetectionMode = .off
        settings.postProcessingEnabled = true
        settings.enhancementsAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini")
        settings.selectedPromptId = UUID()
        let promptID = settings.selectedPromptId
        let context = ResolvedCaptureContext(purpose: .meeting, meetingApp: .zoom)

        await manager.startMeetingFromDetectionToast(context, skipPostProcessing: true)
        let meeting = try XCTUnwrap(manager.currentMeeting)
        let session = manager.makeTranscriptionSessionSnapshot(meeting)
        XCTAssertTrue(manager.isRecording)
        XCTAssertTrue(session.skipPostProcessing)
        XCTAssertEqual(session.useCaseConfig?.applyPostProcessing, false)
        XCTAssertEqual(settings.selectedPromptId, promptID)

        await manager.stopRecording(transcribe: false)
        XCTAssertNil(manager.meetingSkippingPostProcessingID)
        await manager.startCapture(purpose: .meeting)
        let nextMeeting = try XCTUnwrap(manager.currentMeeting)
        let nextSession = manager.makeTranscriptionSessionSnapshot(nextMeeting)
        XCTAssertFalse(nextSession.skipPostProcessing)
        XCTAssertEqual(settings.selectedPromptId, promptID)
        XCTAssertEqual(nextSession.useCaseConfig?.applyPostProcessing, true)
        // A retained snapshot stays disabled even after the next capture starts.
        XCTAssertFalse(manager.makeUseCaseConfig(session: session, settings: settings).applyPostProcessing)
    }

    func testFailedToastStartClearsSessionOverride() async throws {
        let manager = try XCTUnwrap(manager)
        let mic = try XCTUnwrap(mockMic)
        mic.shouldFailStart = true
        await manager.startMeetingFromDetectionToast(
            ResolvedCaptureContext(purpose: .meeting, meetingApp: .zoom),
            skipPostProcessing: true
        )
        XCTAssertNil(manager.currentMeeting)
        XCTAssertNil(manager.meetingSkippingPostProcessingID)
        XCTAssertNil(manager.meetingDetectionToastStartContext)
    }

    func testDisablingDetectionDuringStartDoesNotRestoreRecordingToast() async throws {
        let provider = SuspendedMeetingContextProvider()
        let manager = try RecordingManager(
            micRecorder: XCTUnwrap(mockMic),
            systemRecorder: XCTUnwrap(mockSystem),
            transcriptionClient: XCTUnwrap(mockTranscription),
            postProcessingService: XCTUnwrap(mockPostProcessing),
            storage: XCTUnwrap(mockStorage),
            activeAppContextProvider: provider,
            captureContextResolver: XCTUnwrap(mockCaptureContextResolver),
            apiKeyExists: { _ in true }
        )
        AppSettingsStore.shared.meetingDetectionMode = .notify
        let entered = expectation(description: "Capture preparation suspended")
        provider.onFetch = { entered.fulfill() }
        let start = Task {
            await manager.startMeetingFromDetectionToast(ResolvedCaptureContext(purpose: .meeting, meetingApp: .zoom))
        }
        await fulfillment(of: [entered], timeout: 2)
        XCTAssertNotNil(manager.meetingDetectionToastStartContext)
        AppSettingsStore.shared.meetingDetectionMode = .off
        manager.disableMeetingDetection()
        XCTAssertNil(manager.meetingDetectionToastStartContext)
        provider.resume()
        await start.value
        XCTAssertTrue(manager.isRecording)
        XCTAssertNil(MeetingDetectionToastController.shared.currentState)
        await manager.stopRecording(transcribe: false)
    }

    func testAutomaticMeetingEntryDoesNotMonitorInTestBundle() throws {
        let manager = try XCTUnwrap(manager)
        manager.setAutomaticMeetingRecordingEnabled(true)
        XCTAssertNil(manager.automaticMeetingRecordingCancellable)
        XCTAssertFalse(MeetingDetectionToastController.shared.isVisible)
    }
}

@MainActor
private final class SuspendedMeetingContextProvider: ActiveAppContextProvider {
    var onFetch: (() -> Void)?
    private var continuation: CheckedContinuation<ActiveAppContext?, Never>?

    func fetchActiveAppContext() async throws -> ActiveAppContext? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            onFetch?()
        }
    }

    func resume() {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
