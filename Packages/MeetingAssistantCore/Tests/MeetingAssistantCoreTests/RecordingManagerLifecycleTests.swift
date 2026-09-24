import Combine
import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
extension RecordingManagerTests {
    func testStopWithoutTranscriptionUsesRealLifecycleCleanup() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockStorage = try XCTUnwrap(mockStorage)

        await manager.startRecording()
        XCTAssertTrue(manager.isRecording)

        await manager.stopRecording(transcribe: false)

        XCTAssertEqual(mockMic.stopRecordingCalledCount, 1)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertNil(manager.currentMeeting)
        XCTAssertNil(manager.currentCapturePurpose)
        let micURL = await manager.getMicAudioURL()
        let systemURL = await manager.getSystemAudioURL()
        XCTAssertNil(micURL)
        XCTAssertNil(systemURL)
        XCTAssertTrue(mockStorage.cleanupTemporaryFilesCalled)
        let activeMode = await RecordingExclusivityCoordinator.shared.activeRecordingMode()
        XCTAssertNil(activeMode)
    }

    func testStartFailureCleansRecorderFilesStateContextAndExclusivity() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)
        let mockStorage = try XCTUnwrap(mockStorage)

        let micURL = FileManager.default.temporaryDirectory.appendingPathComponent("start-failure-mic-\(UUID().uuidString).m4a")
        let systemURL = FileManager.default.temporaryDirectory.appendingPathComponent("start-failure-system-\(UUID().uuidString).m4a")
        let mergedURL = mockStorage.recordingsDirectory.appendingPathComponent("mock_merged.wav")
        try Data([1]).write(to: micURL)
        try Data([2]).write(to: systemURL)
        try FileManager.default.createDirectory(
            at: mockStorage.recordingsDirectory,
            withIntermediateDirectories: true,
        )
        try Data([3]).write(to: mergedURL)
        mockMic.currentRecordingURL = micURL
        mockSystem.currentRecordingURL = systemURL
        mockMic.isRecording = true
        mockSystem.isRecording = true
        mockMic.shouldFailStart = true

        await manager.startRecording()

        XCTAssertEqual(mockMic.stopRecordingCalledCount, 1)
        XCTAssertEqual(mockSystem.stopRecordingCalledCount, 1)
        XCTAssertTrue(mockStorage.cleanupTemporaryFilesCalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: micURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: systemURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mergedURL.path))
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertNil(manager.currentMeeting)
        XCTAssertNil(manager.currentCapturePurpose)
        XCTAssertNil(manager.postProcessingContext)
        XCTAssertTrue(manager.postProcessingContextItems.isEmpty)
        XCTAssertNotNil(manager.lastError)
        guard case .failed = manager.meetingState else {
            return XCTFail("Expected start failure to leave the meeting in a failed state")
        }
        let micURLAfter = await manager.getMicAudioURL()
        let systemURLAfter = await manager.getSystemAudioURL()
        let mergedURLAfter = await manager.getMergedAudioURL()
        let activeMode = await RecordingExclusivityCoordinator.shared.activeRecordingMode()
        XCTAssertNil(micURLAfter)
        XCTAssertNil(systemURLAfter)
        XCTAssertNil(mergedURLAfter)
        XCTAssertNil(activeMode)
    }

    func testCancelRecordingDuringStartupCleansReturnedFilesAndMergedState() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)
        let mockStorage = try XCTUnwrap(mockStorage)

        let micURL = FileManager.default.temporaryDirectory.appendingPathComponent("startup-cancel-mic-\(UUID().uuidString).m4a")
        let systemURL = FileManager.default.temporaryDirectory.appendingPathComponent("startup-cancel-system-\(UUID().uuidString).m4a")
        let mergedURL = FileManager.default.temporaryDirectory.appendingPathComponent("startup-cancel-merged-\(UUID().uuidString).m4a")
        try Data([1]).write(to: micURL)
        try Data([2]).write(to: systemURL)
        try Data([3]).write(to: mergedURL)
        mockMic.currentRecordingURL = micURL
        mockSystem.currentRecordingURL = systemURL
        manager.isStartingRecording = true
        manager.currentCapturePurpose = .dictation
        manager.currentMeeting = Meeting(app: .unknown, capturePurpose: .dictation)
        await manager.recordingActor.setMicAudioURL(micURL)
        await manager.recordingActor.setSystemAudioURL(systemURL)
        await manager.recordingActor.setMergedAudioURL(mergedURL)

        let acquired = await RecordingExclusivityCoordinator.shared.beginRecording(mode: .dictation)
        XCTAssertTrue(acquired)

        await manager.cancelRecording()

        XCTAssertEqual(mockMic.stopRecordingCalledCount, 1)
        XCTAssertEqual(mockSystem.stopRecordingCalledCount, 1)
        XCTAssertTrue(mockStorage.cleanupTemporaryFilesCalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: micURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: systemURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mergedURL.path))
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertNil(manager.currentMeeting)
        XCTAssertNil(manager.currentCapturePurpose)
        XCTAssertEqual(manager.meetingState, .idle)
        let micURLAfter = await manager.getMicAudioURL()
        let systemURLAfter = await manager.getSystemAudioURL()
        let mergedURLAfter = await manager.getMergedAudioURL()
        XCTAssertNil(micURLAfter)
        XCTAssertNil(systemURLAfter)
        XCTAssertNil(mergedURLAfter)
        let activeMode = await RecordingExclusivityCoordinator.shared.activeRecordingMode()
        XCTAssertNil(activeMode)
    }

    func testRecorderActivityDuringStartupDoesNotPublishRecordingState() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)

        manager.currentCapturePurpose = .dictation
        manager.isStartingRecording = true
        var recorderActivitySubscription: AnyCancellable?
        defer {
            recorderActivitySubscription?.cancel()
            manager.isStartingRecording = false
            manager.currentCapturePurpose = nil
            mockMic.isRecording = false
        }

        let recorderActivity = expectation(description: "Recorder reports activity during startup")
        recorderActivitySubscription = mockMic.$isRecording.sink { isRecording in
            if isRecording {
                recorderActivity.fulfill()
            }
        }
        mockMic.isRecording = true

        await fulfillment(of: [recorderActivity], timeout: 1)

        XCTAssertFalse(manager.isRecording)
        XCTAssertTrue(manager.isStartingRecording)
    }

    func testLateRecorderStopAfterCaptureEndsDoesNotMutateLifecycle() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)

        manager.isRecording = false
        manager.isStartingRecording = false
        manager.currentCapturePurpose = nil
        mockMic.isRecording = true
        mockMic.isRecording = false

        for _ in 0..<5 {
            await Task.yield()
        }

        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertEqual(mockMic.stopRecordingCalledCount, 0)
    }

    func testStaleRecorderActivityAfterCaptureEndsDoesNotResurrectRecording() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)

        manager.currentCapturePurpose = .dictation
        manager.isRecording = false
        manager.isStartingRecording = false
        var recorderActivitySubscription: AnyCancellable?
        defer {
            recorderActivitySubscription?.cancel()
            manager.currentCapturePurpose = nil
            mockMic.isRecording = false
        }

        let recorderActivity = expectation(description: "Recorder reports stale activity")
        recorderActivitySubscription = mockMic.$isRecording.sink { isRecording in
            if isRecording {
                recorderActivity.fulfill()
            }
        }
        mockMic.isRecording = true

        await fulfillment(of: [recorderActivity], timeout: 1)

        XCTAssertFalse(manager.isRecording)
    }

    func testCancelRecordingWhileStartOperationIsInFlightPreventsCommitBeforeStartupState() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)
        let mockStorage = try XCTUnwrap(mockStorage)

        var beginExclusivityContinuation: CheckedContinuation<Bool, Never>?
        var commitCalled = false
        manager.isStartOperationInFlight = true
        defer { manager.isStartOperationInFlight = false }

        let exclusivityStarted = expectation(description: "Start is awaiting exclusivity")
        let startTask = Task { @MainActor in
            await manager.lifecycleCoordinator.start(
                isRecording: false,
                actions: .init(
                    beginExclusivity: {
                        let shouldContinue = await withCheckedContinuation { continuation in
                            beginExclusivityContinuation = continuation
                            exclusivityStarted.fulfill()
                        }
                        guard shouldContinue else { return false }
                        return true
                    },
                    beginState: {
                        manager.currentMeeting = Meeting(
                            app: .unknown,
                            capturePurpose: .dictation,
                            state: .idle,
                        )
                        manager.currentCapturePurpose = .dictation
                        manager.isStartingRecording = true
                    },
                    prepare: {
                        XCTAssertEqual(manager.currentMeeting?.state, .idle)
                        return URL(fileURLWithPath: "/tmp/start-before-state-cancel.wav")
                    },
                    commit: { _ in
                        commitCalled = true
                    },
                ),
                operations: manager.lifecycleOperations,
                handleFailure: { _ in
                    XCTFail("Unexpected start failure")
                },
            )
            manager.isStartOperationInFlight = false
        }

        await fulfillment(of: [exclusivityStarted], timeout: 1)
        XCTAssertFalse(manager.isStartingRecording)

        await manager.cancelRecording()

        beginExclusivityContinuation?.resume(returning: true)
        await startTask.value

        XCTAssertFalse(commitCalled)
        XCTAssertEqual(mockMic.stopRecordingCalledCount, 1)
        XCTAssertEqual(mockSystem.stopRecordingCalledCount, 1)
        XCTAssertTrue(mockStorage.cleanupTemporaryFilesCalled)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertEqual(manager.meetingState, .idle)
    }

    func testResetDuringStartupCancelsBeforeCommitThenClearsState() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)
        let mockStorage = try XCTUnwrap(mockStorage)

        let micURL = FileManager.default.temporaryDirectory.appendingPathComponent("reset-startup-mic-\(UUID().uuidString).m4a")
        let systemURL = FileManager.default.temporaryDirectory.appendingPathComponent("reset-startup-system-\(UUID().uuidString).m4a")
        let mergedURL = FileManager.default.temporaryDirectory.appendingPathComponent("reset-startup-merged-\(UUID().uuidString).m4a")
        try Data([1]).write(to: micURL)
        try Data([2]).write(to: systemURL)
        try Data([3]).write(to: mergedURL)
        mockMic.currentRecordingURL = micURL
        mockSystem.currentRecordingURL = systemURL
        await manager.recordingActor.setMergedAudioURL(mergedURL)

        let state = ResetStartupTestState(
            exclusivityStarted: expectation(description: "Startup is awaiting exclusivity"),
            prepareStarted: expectation(description: "Startup is awaiting preparation"),
            micURL: micURL,
            systemURL: systemURL,
            mergedURL: mergedURL,
        )
        manager.isStartOperationInFlight = true
        defer { manager.isStartOperationInFlight = false }

        let startTask = makeResetStartupTask(manager: manager, state: state)

        await fulfillment(of: [state.exclusivityStarted], timeout: 1)
        let resetTask = Task { @MainActor in
            await manager.reset()
        }
        for _ in 0..<5 {
            await Task.yield()
        }

        state.beginExclusivityContinuation?.resume(returning: true)
        await fulfillment(of: [state.prepareStarted], timeout: 1)
        state.prepareContinuation?.resume(returning: URL(fileURLWithPath: "/tmp/reset-startup-prepared.wav"))
        await startTask.value
        await resetTask.value

        XCTAssertFalse(state.commitCalled)
        await assertResetCleared(
            manager: manager,
            mockMic: mockMic,
            mockSystem: mockSystem,
            mockStorage: mockStorage,
            state: state,
        )
    }

    func testStopRecordingFinalizationFailureRetainsAudioForRetry() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)
        let mockStorage = try XCTUnwrap(mockStorage)

        let settings = AppSettingsStore.shared
        let originalMergeSetting = settings.shouldMergeAudioFiles
        settings.shouldMergeAudioFiles = false
        defer { settings.shouldMergeAudioFiles = originalMergeSetting }

        let acquired = await RecordingExclusivityCoordinator.shared.beginRecording(mode: .dictation)
        XCTAssertTrue(acquired)
        manager.isRecording = true
        manager.currentCapturePurpose = .dictation
        manager.currentMeeting = Meeting(app: .unknown, capturePurpose: .dictation)

        let mergedURL = FileManager.default.temporaryDirectory.appendingPathComponent("finalization-merged-\(UUID().uuidString).m4a")
        let systemURL = FileManager.default.temporaryDirectory.appendingPathComponent("finalization-system-\(UUID().uuidString).m4a")
        defer {
            try? FileManager.default.removeItem(at: mergedURL)
            try? FileManager.default.removeItem(at: systemURL)
        }
        try Data([1]).write(to: mergedURL)
        try Data([2]).write(to: systemURL)
        mockMic.currentRecordingURL = nil
        mockSystem.currentRecordingURL = systemURL
        await manager.recordingActor.setMergedAudioURL(mergedURL)

        await manager.stopRecording(transcribe: true)

        XCTAssertEqual(mockMic.stopRecordingCalledCount, 1)
        XCTAssertEqual(mockSystem.stopRecordingCalledCount, 1)
        XCTAssertFalse(mockStorage.cleanupTemporaryFilesCalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: systemURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: mergedURL.path))
        XCTAssertTrue(mockStorage.saveTranscriptionCalled)
        let failedTranscription = try XCTUnwrap(mockStorage.savedTranscriptions.last)
        XCTAssertEqual(failedTranscription.lifecycleState, .failed)
        XCTAssertEqual(failedTranscription.meeting.audioFilePath, systemURL.path)
        XCTAssertEqual(manager.resolveRetryAudioURL(for: failedTranscription), systemURL)
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertNil(manager.currentMeeting)
        XCTAssertNil(manager.currentCapturePurpose)
        let activeMode = await RecordingExclusivityCoordinator.shared.activeRecordingMode()
        XCTAssertNil(activeMode)
    }

    func testCancelRecordingCleansReturnedFilesWhenActorHasNoRecorderURLs() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)
        let mockStorage = try XCTUnwrap(mockStorage)

        let acquired = await RecordingExclusivityCoordinator.shared.beginRecording(mode: .dictation)
        XCTAssertTrue(acquired)
        manager.isRecording = true
        manager.currentCapturePurpose = .dictation
        manager.currentMeeting = Meeting(app: .unknown, capturePurpose: .dictation)
        let micURL = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-mic-\(UUID().uuidString).m4a")
        let systemURL = FileManager.default.temporaryDirectory.appendingPathComponent("cancel-system-\(UUID().uuidString).m4a")
        try Data([1]).write(to: micURL)
        try Data([2]).write(to: systemURL)
        mockMic.isRecording = true
        mockMic.currentRecordingURL = micURL
        mockSystem.isRecording = true
        mockSystem.currentRecordingURL = systemURL

        await manager.cancelRecording()

        XCTAssertEqual(mockMic.stopRecordingCalledCount, 1)
        XCTAssertEqual(mockSystem.stopRecordingCalledCount, 1)
        XCTAssertTrue(mockStorage.cleanupTemporaryFilesCalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: micURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: systemURL.path))
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertNil(manager.currentMeeting)
        XCTAssertNil(manager.currentCapturePurpose)
        XCTAssertEqual(manager.meetingState, .idle)
        let activeMode = await RecordingExclusivityCoordinator.shared.activeRecordingMode()
        XCTAssertNil(activeMode)
    }

    func testUnexpectedRecorderFailureThroughManagerCleansReturnedFilesStateAndExclusivity() async throws {
        let manager = try XCTUnwrap(manager)
        let mockMic = try XCTUnwrap(mockMic)
        let mockSystem = try XCTUnwrap(mockSystem)
        let mockStorage = try XCTUnwrap(mockStorage)

        let acquired = await RecordingExclusivityCoordinator.shared.beginRecording(mode: .dictation)
        XCTAssertTrue(acquired)
        manager.isRecording = true
        manager.currentCapturePurpose = .dictation
        manager.currentMeeting = Meeting(app: .unknown, capturePurpose: .dictation)
        let mergedURL = FileManager.default.temporaryDirectory.appendingPathComponent("lifecycle-merged-\(UUID().uuidString).m4a")
        let micURL = FileManager.default.temporaryDirectory.appendingPathComponent("lifecycle-mic-\(UUID().uuidString).m4a")
        let systemURL = FileManager.default.temporaryDirectory.appendingPathComponent("lifecycle-system-\(UUID().uuidString).m4a")
        try Data([1]).write(to: mergedURL)
        try Data([2]).write(to: micURL)
        try Data([3]).write(to: systemURL)
        mockMic.isRecording = true
        mockMic.currentRecordingURL = micURL
        mockSystem.isRecording = true
        mockSystem.currentRecordingURL = systemURL
        await manager.recordingActor.setMergedAudioURL(mergedURL)

        await manager.lifecycleCoordinator.recorderDidFail(
            NSError(domain: "RecordingManagerTests", code: 1),
            isRecording: true,
            isStarting: false,
            operations: manager.lifecycleOperations,
        )

        XCTAssertEqual(mockMic.stopRecordingCalledCount, 1)
        XCTAssertEqual(mockSystem.stopRecordingCalledCount, 1)
        XCTAssertTrue(mockStorage.cleanupTemporaryFilesCalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: micURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: systemURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: mergedURL.path))
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertNil(manager.currentMeeting)
        XCTAssertNil(manager.currentCapturePurpose)
        let micURLAfter = await manager.getMicAudioURL()
        let systemURLAfter = await manager.getSystemAudioURL()
        let mergedURLAfter = await manager.getMergedAudioURL()
        let activeMode = await RecordingExclusivityCoordinator.shared.activeRecordingMode()
        XCTAssertNil(micURLAfter)
        XCTAssertNil(systemURLAfter)
        XCTAssertNil(mergedURLAfter)
        XCTAssertNil(activeMode)
    }
}

@MainActor
private final class ResetStartupTestState {
    let exclusivityStarted: XCTestExpectation
    let prepareStarted: XCTestExpectation
    let micURL: URL
    let systemURL: URL
    let mergedURL: URL
    var beginExclusivityContinuation: CheckedContinuation<Bool, Never>?
    var prepareContinuation: CheckedContinuation<URL, Error>?
    var commitCalled = false

    init(
        exclusivityStarted: XCTestExpectation,
        prepareStarted: XCTestExpectation,
        micURL: URL,
        systemURL: URL,
        mergedURL: URL,
    ) {
        self.exclusivityStarted = exclusivityStarted
        self.prepareStarted = prepareStarted
        self.micURL = micURL
        self.systemURL = systemURL
        self.mergedURL = mergedURL
    }
}

@MainActor
private extension RecordingManagerTests {
    func makeResetStartupTask(
        manager: RecordingManager,
        state: ResetStartupTestState,
    ) -> Task<Void, Never> {
        Task { @MainActor in
            await manager.lifecycleCoordinator.start(
                isRecording: false,
                actions: .init(
                    beginExclusivity: {
                        let shouldContinue = await withCheckedContinuation { continuation in
                            state.beginExclusivityContinuation = continuation
                            state.exclusivityStarted.fulfill()
                        }
                        guard shouldContinue else { return false }
                        return await RecordingExclusivityCoordinator.shared.beginRecording(mode: .dictation)
                    },
                    beginState: {
                        manager.currentMeeting = Meeting(
                            app: .unknown,
                            capturePurpose: .dictation,
                            state: .idle,
                        )
                        manager.currentCapturePurpose = .dictation
                        manager.isStartingRecording = true
                    },
                    prepare: {
                        XCTAssertEqual(manager.currentMeeting?.state, .idle)
                        return try await withCheckedThrowingContinuation { continuation in
                            state.prepareContinuation = continuation
                            state.prepareStarted.fulfill()
                        }
                    },
                    commit: { _ in
                        state.commitCalled = true
                    },
                ),
                operations: manager.lifecycleOperations,
                handleFailure: { _ in
                    XCTFail("Unexpected start failure")
                },
            )
            manager.isStartOperationInFlight = false
        }
    }

    func assertResetCleared(
        manager: RecordingManager,
        mockMic: MockAudioRecorder,
        mockSystem: MockAudioRecorder,
        mockStorage: MockStorageService,
        state: ResetStartupTestState,
    ) async {
        XCTAssertEqual(mockMic.stopRecordingCalledCount, 1)
        XCTAssertEqual(mockSystem.stopRecordingCalledCount, 1)
        XCTAssertTrue(mockStorage.cleanupTemporaryFilesCalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.micURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.systemURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: state.mergedURL.path))
        XCTAssertFalse(manager.isRecording)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertFalse(manager.isStartOperationInFlight)
        XCTAssertEqual(manager.meetingState, .idle)
        XCTAssertNil(manager.currentMeeting)
        XCTAssertNil(manager.currentCapturePurpose)
        XCTAssertNil(manager.postProcessingContext)
        XCTAssertTrue(manager.postProcessingContextItems.isEmpty)
        let micURLAfter = await manager.getMicAudioURL()
        let systemURLAfter = await manager.getSystemAudioURL()
        let mergedURLAfter = await manager.getMergedAudioURL()
        let activeMode = await RecordingExclusivityCoordinator.shared.activeRecordingMode()
        XCTAssertNil(micURLAfter)
        XCTAssertNil(systemURLAfter)
        XCTAssertNil(mergedURLAfter)
        XCTAssertNil(activeMode)
    }
}
