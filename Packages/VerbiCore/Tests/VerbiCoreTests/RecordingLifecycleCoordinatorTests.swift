import Foundation
@testable import VerbiCoreUI
import XCTest

@MainActor
final class RecordingLifecycleCoordinatorTests: XCTestCase {
    func testCancellationDuringStartupCleansStateAndExclusivity() async {
        let state = RecordingLifecycleTestState()
        state.captureActive = true
        state.exclusive = true
        state.temporaryFilesExist = true
        state.temporaryTaskActive = true
        state.mergedAudioExists = true

        await RecordingLifecycleCoordinator().cancel(
            isRecording: false,
            isStarting: true,
            operations: makeOperations(state),
        )

        XCTAssertTrue(state.reset)
        XCTAssertFalse(state.captureActive)
        XCTAssertFalse(state.exclusive)
        XCTAssertFalse(state.temporaryFilesExist)
        XCTAssertFalse(state.temporaryTaskActive)
        XCTAssertFalse(state.mergedAudioExists)
        XCTAssertEqual(state.events, ["stopRecorders", "cancelIncremental", "cancelPostStartTasks", "cleanupTemporaryFiles", "removeMergedAudio", "resetState", "endExclusivity"])
    }

    func testCancellationDuringRecordingCleansStateAndFiles() async {
        let state = RecordingLifecycleTestState()
        state.captureActive = true
        state.exclusive = true
        state.incrementalActive = true
        state.temporaryFilesExist = true
        state.mergedAudioExists = true

        await RecordingLifecycleCoordinator().cancel(
            isRecording: true,
            isStarting: false,
            operations: makeOperations(state),
        )

        XCTAssertTrue(state.reset)
        XCTAssertFalse(state.captureActive)
        XCTAssertFalse(state.exclusive)
        XCTAssertFalse(state.temporaryFilesExist)
        XCTAssertFalse(state.mergedAudioExists)
        XCTAssertFalse(state.incrementalActive)
    }

    func testStopWithoutTranscriptionCancelsIncrementalBeforeReset() async {
        let state = RecordingLifecycleTestState()
        state.captureActive = true
        state.exclusive = true
        state.incrementalActive = true

        await RecordingLifecycleCoordinator().stop(
            isRecording: true,
            transcribe: false,
            operations: makeOperations(state),
            actions: .init(
                beforeRelease: { _ in state.events.append("beforeRelease") },
                finalize: { _ in state.events.append("finalize") },
                handleFailure: { _, _ in XCTFail("Unexpected finalization failure") },
            ),
        )

        XCTAssertFalse(state.incrementalActive)
        XCTAssertTrue(state.reset)
        XCTAssertEqual(state.events, ["cancelPostStartTasks", "stopRecorders", "beforeRelease", "endExclusivity", "finalize", "cancelIncremental", "resetState"])
    }

    func testStopWithTranscriptionPreservesFullFileHandoff() async {
        let state = RecordingLifecycleTestState()
        state.captureActive = true
        state.exclusive = true

        await RecordingLifecycleCoordinator().stop(
            isRecording: true,
            transcribe: true,
            operations: makeOperations(state),
            actions: .init(
                beforeRelease: { _ in state.events.append("beforeRelease") },
                finalize: { _ in state.events.append("fullFileHandoff") },
                handleFailure: { _, _ in XCTFail("Unexpected finalization failure") },
            ),
        )

        XCTAssertTrue(state.events.contains("fullFileHandoff"))
        XCTAssertFalse(state.reset)
        XCTAssertFalse(state.events.contains("cancelIncremental"))
        XCTAssertFalse(state.exclusive)
    }

    func testFinalizationFailureResetsStateAndReleasesExclusivity() async {
        let state = RecordingLifecycleTestState()
        state.captureActive = true
        state.exclusive = true

        await RecordingLifecycleCoordinator().stop(
            isRecording: true,
            transcribe: true,
            operations: makeOperations(state),
            actions: .init(
                beforeRelease: { _ in state.events.append("beforeRelease") },
                finalize: { _ in throw RecordingLifecycleTestError.finalizationFailed },
                handleFailure: { _, _ in
                    state.events.append("handleFailure")
                    state.captureActive = false
                    state.reset = true
                },
            ),
        )

        XCTAssertTrue(state.reset)
        XCTAssertFalse(state.captureActive)
        XCTAssertFalse(state.exclusive)
        XCTAssertTrue(state.events.contains("handleFailure"))
    }

    func testUnexpectedRecorderFailureStopsCaptureAndCleansFiles() async {
        let state = RecordingLifecycleTestState()
        state.captureActive = true
        state.exclusive = true
        state.incrementalActive = true
        state.temporaryTaskActive = true
        state.temporaryFilesExist = true
        state.mergedAudioExists = true

        await RecordingLifecycleCoordinator().recorderDidFail(
            RecordingLifecycleTestError.finalizationFailed,
            isRecording: true,
            isStarting: false,
            operations: makeOperations(state),
        )

        XCTAssertTrue(state.reset)
        XCTAssertFalse(state.captureActive)
        XCTAssertFalse(state.exclusive)
        XCTAssertFalse(state.incrementalActive)
        XCTAssertFalse(state.temporaryTaskActive)
        XCTAssertFalse(state.temporaryFilesExist)
        XCTAssertFalse(state.mergedAudioExists)
        XCTAssertEqual(state.events, ["stopRecorders", "cancelPostStartTasks", "cancelIncremental", "cleanupTemporaryFiles", "removeMergedAudio", "resetState", "endExclusivity"])
    }

    func testOverlappingCancellationAllowsOnlyOneTransition() async {
        let state = DelayedRecordingLifecycleTestState()
        let stopStarted = expectation(description: "First cancellation stops recorders")
        let operations = makeDelayedCancellationOperations(state, stopStarted: stopStarted)
        let coordinator = RecordingLifecycleCoordinator()
        let firstCancellation = Task { @MainActor in
            await coordinator.cancel(
                isRecording: true,
                isStarting: false,
                operations: operations,
            )
        }

        await fulfillment(of: [stopStarted], timeout: 1)
        await coordinator.cancel(
            isRecording: true,
            isStarting: false,
            operations: operations,
        )

        XCTAssertEqual(state.stopCalls, 1)
        XCTAssertEqual(state.cleanupCalls, 0)

        state.stopContinuation?.resume(returning: (mic: nil, system: nil))
        await firstCancellation.value

        XCTAssertEqual(state.stopCalls, 1)
        XCTAssertEqual(state.cleanupCalls, 1)
        XCTAssertEqual(state.resetCalls, 1)
        XCTAssertEqual(state.endExclusivityCalls, 1)
        XCTAssertFalse(state.exclusive)
    }

    func testCancellationDuringAwaitedStartPreventsCommitAndCleansOnce() async {
        let state = DelayedStartLifecycleTestState()
        let prepareStarted = expectation(description: "Start preparation is awaiting")
        let operations = makeDelayedStartOperations(state)
        let coordinator = RecordingLifecycleCoordinator()
        let startTask = Task { @MainActor in
            await coordinator.start(
                isRecording: false,
                actions: .init(
                    beginExclusivity: {
                        state.beginExclusivityCalls += 1
                        return true
                    },
                    beginState: {
                        state.beginStateCalls += 1
                    },
                    prepare: {
                        try await withCheckedThrowingContinuation { continuation in
                            state.prepareContinuation = continuation
                            prepareStarted.fulfill()
                        }
                    },
                    commit: { _ in
                        state.commitCalls += 1
                    },
                ),
                operations: operations,
                handleFailure: { _ in
                    state.handleFailureCalls += 1
                },
            )
        }

        await fulfillment(of: [prepareStarted], timeout: 1)
        await coordinator.cancel(
            isRecording: false,
            isStarting: true,
            operations: operations,
        )

        state.prepareContinuation?.resume(returning: URL(fileURLWithPath: "/tmp/prepared.wav"))
        await startTask.value

        XCTAssertEqual(state.beginExclusivityCalls, 1)
        XCTAssertEqual(state.beginStateCalls, 1)
        XCTAssertEqual(state.commitCalls, 0)
        XCTAssertEqual(state.handleFailureCalls, 0)
        XCTAssertEqual(state.stopRecordersCalls, 1)
        XCTAssertEqual(state.cleanupCalls, 1)
        XCTAssertEqual(state.removeMergedAudioCalls, 1)
        XCTAssertEqual(state.resetCalls, 1)
        XCTAssertEqual(state.endExclusivityCalls, 1)
        XCTAssertEqual(state.playCancelledCalls, 1)
        XCTAssertFalse(state.exclusive)
    }

    func testCancellationDuringAwaitedStartFailureUsesCancellationCleanup() async {
        let state = DelayedStartLifecycleTestState()
        let prepareStarted = expectation(description: "Start preparation is awaiting failure")
        let operations = makeDelayedStartOperations(state)
        let coordinator = RecordingLifecycleCoordinator()
        let startTask = Task { @MainActor in
            await coordinator.start(
                isRecording: false,
                actions: .init(
                    beginExclusivity: {
                        state.beginExclusivityCalls += 1
                        return true
                    },
                    beginState: {
                        state.beginStateCalls += 1
                    },
                    prepare: {
                        try await withCheckedThrowingContinuation { continuation in
                            state.prepareContinuation = continuation
                            prepareStarted.fulfill()
                        }
                    },
                    commit: { _ in
                        state.commitCalls += 1
                    },
                ),
                operations: operations,
                handleFailure: { _ in
                    state.handleFailureCalls += 1
                },
            )
        }

        await fulfillment(of: [prepareStarted], timeout: 1)
        await coordinator.cancel(
            isRecording: false,
            isStarting: true,
            operations: operations,
        )

        state.prepareContinuation?.resume(throwing: RecordingLifecycleTestError.finalizationFailed)
        await startTask.value

        XCTAssertEqual(state.commitCalls, 0)
        XCTAssertEqual(state.handleFailureCalls, 0)
        XCTAssertEqual(state.stopRecordersCalls, 1)
        XCTAssertEqual(state.cleanupCalls, 1)
        XCTAssertEqual(state.removeMergedAudioCalls, 1)
        XCTAssertEqual(state.resetCalls, 1)
        XCTAssertNil(state.resetError)
        XCTAssertEqual(state.endExclusivityCalls, 1)
        XCTAssertEqual(state.playCancelledCalls, 1)
        XCTAssertFalse(state.exclusive)
    }

    func testRecorderFailureDuringAwaitedStartPreventsCommitAndResetsFailure() async {
        let state = DelayedStartLifecycleTestState()
        let prepareStarted = expectation(description: "Start preparation is awaiting recorder failure")
        let operations = makeDelayedStartOperations(state)
        let coordinator = RecordingLifecycleCoordinator()
        let startTask = Task { @MainActor in
            await coordinator.start(
                isRecording: false,
                actions: .init(
                    beginExclusivity: {
                        state.beginExclusivityCalls += 1
                        return true
                    },
                    beginState: {
                        state.beginStateCalls += 1
                    },
                    prepare: {
                        try await withCheckedThrowingContinuation { continuation in
                            state.prepareContinuation = continuation
                            prepareStarted.fulfill()
                        }
                    },
                    commit: { _ in
                        state.commitCalls += 1
                    },
                ),
                operations: operations,
                handleFailure: { _ in
                    state.handleFailureCalls += 1
                },
            )
        }

        await fulfillment(of: [prepareStarted], timeout: 1)
        await coordinator.recorderDidFail(
            RecordingLifecycleTestError.finalizationFailed,
            isRecording: false,
            isStarting: true,
            operations: operations,
        )

        state.prepareContinuation?.resume(returning: URL(fileURLWithPath: "/tmp/recorder-failure-prepared.wav"))
        await startTask.value

        XCTAssertEqual(state.commitCalls, 0)
        XCTAssertEqual(state.handleFailureCalls, 0)
        XCTAssertEqual(state.stopRecordersCalls, 1)
        XCTAssertEqual(state.cleanupCalls, 1)
        XCTAssertEqual(state.removeMergedAudioCalls, 1)
        XCTAssertEqual(state.resetCalls, 1)
        XCTAssertTrue(state.resetError is RecordingLifecycleTestError)
        XCTAssertEqual(state.endExclusivityCalls, 1)
        XCTAssertFalse(state.exclusive)
    }

    func testCancellationThenRecorderFailureDuringAwaitedStartUsesCancellationCleanup() async {
        await assertCancellationWinsDuringAwaitedStart(events: [.cancellation, .recorderFailure])
    }

    func testRecorderFailureThenCancellationDuringAwaitedStartUsesCancellationCleanup() async {
        await assertCancellationWinsDuringAwaitedStart(events: [.recorderFailure, .cancellation])
    }

    func testUnexpectedRecorderStopCleansActiveCapture() async {
        let state = RecordingLifecycleTestState()
        state.captureActive = true
        state.exclusive = true
        state.incrementalActive = true
        state.temporaryTaskActive = true
        state.temporaryFilesExist = true
        state.mergedAudioExists = true

        await RecordingLifecycleCoordinator().recorderStateDidChange(
            .init(
                recorderIsRecording: false,
                isRecording: true,
                isStarting: false,
                isStartOperationInFlight: false,
            ),
            operations: makeOperations(state),
        )

        XCTAssertTrue(state.reset)
        XCTAssertFalse(state.captureActive)
        XCTAssertFalse(state.exclusive)
        XCTAssertFalse(state.incrementalActive)
        XCTAssertFalse(state.temporaryTaskActive)
        XCTAssertFalse(state.temporaryFilesExist)
        XCTAssertFalse(state.mergedAudioExists)
        XCTAssertEqual(state.events, [
            "stopRecorders",
            "cancelPostStartTasks",
            "cancelIncremental",
            "cleanupTemporaryFiles",
            "removeMergedAudio",
            "resetState",
            "endExclusivity",
        ])
    }

    func testUnexpectedRecorderStopDuringCancellationDoesNotStartAnotherTransition() async {
        let state = DelayedRecordingLifecycleTestState()
        let stopStarted = expectation(description: "Cancellation stops recorders")
        let operations = makeDelayedCancellationOperations(state, stopStarted: stopStarted)
        let coordinator = RecordingLifecycleCoordinator()
        let cancellationTask = Task { @MainActor in
            await coordinator.cancel(
                isRecording: true,
                isStarting: false,
                operations: operations,
            )
        }

        await fulfillment(of: [stopStarted], timeout: 1)
        await coordinator.recorderStateDidChange(
            .init(
                recorderIsRecording: false,
                isRecording: true,
                isStarting: false,
                isStartOperationInFlight: false,
            ),
            operations: operations,
        )

        XCTAssertEqual(state.stopCalls, 1)
        XCTAssertEqual(state.cleanupCalls, 0)

        state.stopContinuation?.resume(returning: (mic: nil, system: nil))
        await cancellationTask.value

        XCTAssertEqual(state.stopCalls, 1)
        XCTAssertEqual(state.cleanupCalls, 1)
        XCTAssertEqual(state.resetCalls, 1)
        XCTAssertEqual(state.endExclusivityCalls, 1)
    }

}

private extension RecordingLifecycleCoordinatorTests {
    enum PendingStartEvent {
        case cancellation
        case recorderFailure
    }

    func sendPendingStartEvents(
        _ events: [PendingStartEvent],
        coordinator: RecordingLifecycleCoordinator,
        operations: RecordingLifecycleCoordinator.Operations,
    ) async {
        for event in events {
            switch event {
            case .cancellation:
                await coordinator.cancel(
                    isRecording: false,
                    isStarting: true,
                    operations: operations,
                )
            case .recorderFailure:
                await coordinator.recorderDidFail(
                    RecordingLifecycleTestError.finalizationFailed,
                    isRecording: false,
                    isStarting: true,
                    operations: operations,
                )
            }
        }
    }

    func assertCancellationWinsDuringAwaitedStart(events: [PendingStartEvent]) async {
        let state = DelayedStartLifecycleTestState()
        let prepareStarted = expectation(description: "Start preparation is awaiting pending events")
        let operations = makeDelayedStartOperations(state)
        let coordinator = RecordingLifecycleCoordinator()
        let startTask = Task { @MainActor in
            await coordinator.start(
                isRecording: false,
                actions: .init(
                    beginExclusivity: {
                        state.beginExclusivityCalls += 1
                        return true
                    },
                    beginState: {
                        state.beginStateCalls += 1
                    },
                    prepare: {
                        try await withCheckedThrowingContinuation { continuation in
                            state.prepareContinuation = continuation
                            prepareStarted.fulfill()
                        }
                    },
                    commit: { _ in
                        state.commitCalls += 1
                    },
                ),
                operations: operations,
                handleFailure: { _ in
                    state.handleFailureCalls += 1
                },
            )
        }

        await fulfillment(of: [prepareStarted], timeout: 1)
        await sendPendingStartEvents(events, coordinator: coordinator, operations: operations)

        state.prepareContinuation?.resume(returning: URL(fileURLWithPath: "/tmp/pending-events-prepared.wav"))
        await startTask.value

        XCTAssertEqual(state.commitCalls, 0)
        XCTAssertEqual(state.handleFailureCalls, 0)
        XCTAssertEqual(state.stopRecordersCalls, 1)
        XCTAssertEqual(state.cleanupCalls, 1)
        XCTAssertEqual(state.removeMergedAudioCalls, 1)
        XCTAssertEqual(state.resetCalls, 1)
        XCTAssertNil(state.resetError)
        XCTAssertEqual(state.endExclusivityCalls, 1)
        XCTAssertEqual(state.playCancelledCalls, 1)
        XCTAssertFalse(state.exclusive)
    }
}
