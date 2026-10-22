import Combine
import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreData
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

    func testCancelRecordingHidesToastAndDoesNotLeakIntoManualCapture() async throws {
        let manager = try XCTUnwrap(manager)
        await manager.startMeetingFromDetectionToast(ResolvedCaptureContext(purpose: .meeting, meetingApp: .zoom))
        XCTAssertTrue(manager.isRecording)
        manager.meetingDetectionToastStartContext = ResolvedCaptureContext(purpose: .meeting, meetingApp: .zoom)
        MeetingDetectionToastController.shared.show(state: .recording(app: .zoom, appName: "Zoom", startedAt: Date()))

        await manager.cancelRecording()

        XCTAssertFalse(MeetingDetectionToastController.shared.isVisible)
        XCTAssertNil(manager.meetingDetectionToastStartContext)
        await manager.startCapture(purpose: .meeting)
        XCTAssertTrue(manager.isRecording)
        XCTAssertNil(MeetingDetectionToastController.shared.currentState)
    }

    func testCancelDuringStartHidesToastAndClearsContext() async throws {
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
        let entered = expectation(description: "Capture preparation suspended")
        provider.onFetch = { entered.fulfill() }
        let start = Task {
            await manager.startMeetingFromDetectionToast(ResolvedCaptureContext(purpose: .meeting, meetingApp: .zoom))
        }
        await fulfillment(of: [entered], timeout: 2)
        MeetingDetectionToastController.shared.show(state: .recording(app: .zoom, appName: "Zoom", startedAt: Date()))
        await manager.cancelRecording()
        XCTAssertFalse(MeetingDetectionToastController.shared.isVisible)
        XCTAssertNil(manager.meetingDetectionToastStartContext)
        provider.resume()
        await start.value
        XCTAssertNil(MeetingDetectionToastController.shared.currentState)
        await manager.reset()
    }

    func testRetryStoredNoSummarySessionSkipsPostProcessingAndPreservesOverride() async throws {
        let manager = try XCTUnwrap(manager)
        let storage = try XCTUnwrap(mockStorage)
        let rawURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        try Data(repeating: 0, count: 256).write(to: rawURL)
        defer { try? FileManager.default.removeItem(at: rawURL) }
        let identity = TranscriptionProvider.groq.modelPerformanceIdentity(modelID: "whisper-large-v3")
        let transcription = CaptureArtifact(
            meeting: CaptureSession(app: .zoom, capturePurpose: .meeting, audioFilePath: rawURL.path),
            text: "Existing",
            rawText: "Existing",
            language: "en",
            executionProvenance: ExecutionProvenance(
                transcriptionRequest: nil,
                vocabularySnapshot: .empty,
                transcriptionModelIdentity: identity,
                postProcessingModelIdentity: identity,
                skipPostProcessing: true
            )
        )
        let stack = CoreDataStack(name: "NoSummaryRecoveryTests", inMemory: true)
        let repository = CoreDataTranscriptionStorageRepository(stack: stack)
        try await CoreDataMeetingRepository(stack: stack).saveMeeting(FileSystemStorageService.convertToEntity(transcription).meeting)
        try await repository.saveTranscription(FileSystemStorageService.convertToEntity(transcription))
        let entity = try await repository.fetchTranscription(by: transcription.id)
        let stored = try FileSystemStorageService.convertToModel(XCTUnwrap(entity))
        await manager.retryTranscription(for: stored)
        let saved = try XCTUnwrap(storage.savedTranscriptions.last)
        XCTAssertEqual(saved.meeting.id, stored.meeting.id)
        XCTAssertTrue(try XCTUnwrap(saved.executionProvenance).skipPostProcessing)
        XCTAssertNil(saved.processedContent)
        XCTAssertNil(saved.postProcessingModel)
        XCTAssertEqual(mockPostProcessing?.processTranscriptionCallCount, 0)
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
