import Foundation
@testable import VerbiCoreUI
import XCTest

final class RecordingLifecycleTestState {
    var events: [String] = []
    var captureActive = false
    var exclusive = false
    var incrementalActive = false
    var temporaryFilesExist = false
    var temporaryTaskActive = false
    var mergedAudioExists = false
    var reset = false
}

enum RecordingLifecycleTestError: Error {
    case finalizationFailed
}

func makeOperations(_ state: RecordingLifecycleTestState) -> RecordingLifecycleCoordinator.Operations {
    RecordingLifecycleCoordinator.Operations(
        stopRecorders: {
            state.events.append("stopRecorders")
            state.captureActive = false
            return (URL(fileURLWithPath: "/tmp/mic.m4a"), URL(fileURLWithPath: "/tmp/system.m4a"))
        },
        cancelIncremental: {
            state.events.append("cancelIncremental")
            state.incrementalActive = false
        },
        cancelPostStartTasks: {
            state.events.append("cancelPostStartTasks")
            state.temporaryTaskActive = false
        },
        cleanupTemporaryFiles: { _ in
            state.events.append("cleanupTemporaryFiles")
            state.temporaryFilesExist = false
        },
        removeMergedAudio: {
            state.events.append("removeMergedAudio")
            state.mergedAudioExists = false
        },
        resetState: { _, _ in
            state.events.append("resetState")
            state.captureActive = false
            state.reset = true
        },
        endExclusivity: {
            state.events.append("endExclusivity")
            state.exclusive = false
        },
        playStopSound: {},
        playCancelledSound: {},
    )
}

final class DelayedRecordingLifecycleTestState {
    var stopCalls = 0
    var cleanupCalls = 0
    var resetCalls = 0
    var endExclusivityCalls = 0
    var exclusive = true
    var stopContinuation: CheckedContinuation<(mic: URL?, system: URL?), Never>?
}

func makeDelayedCancellationOperations(
    _ state: DelayedRecordingLifecycleTestState,
    stopStarted: XCTestExpectation,
) -> RecordingLifecycleCoordinator.Operations {
    RecordingLifecycleCoordinator.Operations(
        stopRecorders: {
            state.stopCalls += 1
            stopStarted.fulfill()
            return await withCheckedContinuation { continuation in
                state.stopContinuation = continuation
            }
        },
        cancelIncremental: {},
        cancelPostStartTasks: {},
        cleanupTemporaryFiles: { _ in
            state.cleanupCalls += 1
        },
        removeMergedAudio: {},
        resetState: { _, _ in
            state.resetCalls += 1
        },
        endExclusivity: {
            state.endExclusivityCalls += 1
            state.exclusive = false
        },
        playStopSound: {},
        playCancelledSound: {},
    )
}

final class DelayedStartLifecycleTestState {
    var beginExclusivityCalls = 0
    var beginStateCalls = 0
    var commitCalls = 0
    var handleFailureCalls = 0
    var stopRecordersCalls = 0
    var cleanupCalls = 0
    var removeMergedAudioCalls = 0
    var resetCalls = 0
    var resetError: Error?
    var endExclusivityCalls = 0
    var playCancelledCalls = 0
    var exclusive = true
    var prepareContinuation: CheckedContinuation<URL, Error>?
}

func makeDelayedStartOperations(_ state: DelayedStartLifecycleTestState) -> RecordingLifecycleCoordinator.Operations {
    RecordingLifecycleCoordinator.Operations(
        stopRecorders: {
            state.stopRecordersCalls += 1
            return (
                mic: URL(fileURLWithPath: "/tmp/start-cancel-mic.m4a"),
                system: URL(fileURLWithPath: "/tmp/start-cancel-system.m4a"),
            )
        },
        cancelIncremental: {},
        cancelPostStartTasks: {},
        cleanupTemporaryFiles: { _ in
            state.cleanupCalls += 1
        },
        removeMergedAudio: {
            state.removeMergedAudioCalls += 1
        },
        resetState: { error, _ in
            state.resetCalls += 1
            state.resetError = error
        },
        endExclusivity: {
            state.endExclusivityCalls += 1
            state.exclusive = false
        },
        playStopSound: {},
        playCancelledSound: {
            state.playCancelledCalls += 1
        },
    )
}

final class DelayedFinalizationLifecycleTestState {
    var finalizeContinuation: CheckedContinuation<Void, Never>?
}

func makeDelayedFinalizationOperations(
    _ state: DelayedFinalizationLifecycleTestState,
) -> RecordingLifecycleCoordinator.Operations {
    RecordingLifecycleCoordinator.Operations(
        stopRecorders: { (mic: nil, system: nil) },
        cancelIncremental: {},
        cancelPostStartTasks: {},
        cleanupTemporaryFiles: { _ in },
        removeMergedAudio: {},
        resetState: { _, _ in },
        endExclusivity: {},
        playStopSound: {},
        playCancelledSound: {},
    )
}
