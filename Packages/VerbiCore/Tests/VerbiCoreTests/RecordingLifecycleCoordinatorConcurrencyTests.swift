import Foundation
@testable import VerbiCoreUI
import XCTest

@MainActor
extension RecordingLifecycleCoordinatorTests {
    func testRecorderCallbacksFromPreviousGenerationAreIgnored() async {
        let state = RecordingLifecycleTestState()
        state.captureActive = true
        state.exclusive = true
        let coordinator = RecordingLifecycleCoordinator()
        let staleGeneration = coordinator.currentRecorderCallbackGeneration()

        await coordinator.start(
            isRecording: false,
            actions: .init(
                beginExclusivity: { true },
                beginState: {},
                prepare: { URL(fileURLWithPath: "/tmp/new-session.wav") },
                commit: { _ in state.captureActive = true },
            ),
            operations: makeOperations(state),
            handleFailure: { _ in XCTFail("Unexpected start failure") },
        )

        await coordinator.recorderStateDidChange(
            .init(
                recorderIsRecording: false,
                isRecording: true,
                isStarting: false,
                isStartOperationInFlight: false,
            ),
            generation: staleGeneration,
            operations: makeOperations(state),
        )
        await coordinator.recorderDidFail(
            RecordingLifecycleTestError.finalizationFailed,
            isRecording: true,
            isStarting: false,
            generation: staleGeneration,
            operations: makeOperations(state),
        )

        XCTAssertTrue(state.events.isEmpty)
        XCTAssertTrue(state.captureActive)
        XCTAssertTrue(state.exclusive)
    }

    func testResetWaitsForFinalizationBeforeReturning() async {
        let state = DelayedFinalizationLifecycleTestState()
        let finalizationStarted = expectation(description: "Finalization started")
        let coordinator = RecordingLifecycleCoordinator()
        let stopTask = Task { @MainActor in
            await coordinator.stop(
                isRecording: true,
                transcribe: true,
                operations: makeDelayedFinalizationOperations(state),
                actions: .init(
                    beforeRelease: { _ in },
                    finalize: { _ in
                        finalizationStarted.fulfill()
                        await withCheckedContinuation { continuation in
                            state.finalizeContinuation = continuation
                        }
                    },
                    handleFailure: { _, _ in XCTFail("Unexpected finalization failure") },
                ),
            )
        }

        await fulfillment(of: [finalizationStarted], timeout: 1)
        var resetReturned = false
        let resetTask = Task { @MainActor in
            await coordinator.waitForIdle()
            resetReturned = true
        }
        for _ in 0..<5 {
            await Task.yield()
        }
        XCTAssertFalse(resetReturned)

        state.finalizeContinuation?.resume()
        await stopTask.value
        await resetTask.value
        XCTAssertTrue(resetReturned)
    }

    func testStartCanBeginBeforePreviousFinalizationCompletes() async {
        let state = DelayedFinalizationLifecycleTestState()
        let finalizationStarted = expectation(description: "Finalization started")
        let startCommitted = expectation(description: "New recording committed")
        let coordinator = RecordingLifecycleCoordinator()
        let stopTask = Task { @MainActor in
            await coordinator.stop(
                isRecording: true,
                transcribe: true,
                operations: makeDelayedFinalizationOperations(state),
                actions: .init(
                    beforeRelease: { _ in },
                    finalize: { _ in
                        finalizationStarted.fulfill()
                        await withCheckedContinuation { continuation in
                            state.finalizeContinuation = continuation
                        }
                    },
                    handleFailure: { _, _ in XCTFail("Unexpected finalization failure") },
                ),
            )
        }

        await fulfillment(of: [finalizationStarted], timeout: 1)

        await coordinator.start(
            isRecording: false,
            actions: .init(
                beginExclusivity: { true },
                beginState: {},
                prepare: { URL(fileURLWithPath: "/tmp/next-session.wav") },
                commit: { _ in startCommitted.fulfill() },
            ),
            operations: makeDelayedFinalizationOperations(state),
            handleFailure: { _ in XCTFail("Unexpected start failure") },
        )

        await fulfillment(of: [startCommitted], timeout: 1)
        state.finalizeContinuation?.resume()
        await stopTask.value
    }
}
