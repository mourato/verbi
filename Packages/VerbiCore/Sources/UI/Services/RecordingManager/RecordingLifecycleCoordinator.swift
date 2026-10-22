import Foundation
import os.lock

final class RecorderCallbackGeneration: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: UInt64(0))

    var value: UInt64 {
        lock.withLock { $0 }
    }

    func invalidate() {
        lock.withLock { $0 &+= 1 }
    }
}

@MainActor
final class RecordingLifecycleCoordinator {
    typealias Action = () async -> Void
    typealias StopRecorders = () async -> (mic: URL?, system: URL?)
    typealias CleanupTemporaryFiles = (_ recordings: (mic: URL?, system: URL?)) async -> Void

    private enum TransitionPhase: Equatable {
        case starting
        case cancelling
        case stopping
        case recorderFailure
    }

    private var inFlightTransition: TransitionPhase?
    private var finalizationCount = 0
    private var pendingStartCancellation = false
    private var pendingStartFailure: Error?
    let recorderCallbackGeneration = RecorderCallbackGeneration()

    struct StartActions {
        let beginExclusivity: () async -> Bool
        let beginState: () -> Void
        let prepare: () async throws -> URL
        let commit: (_ audioURL: URL) -> Void
    }

    struct StopActions {
        let beforeRelease: (_ recordings: (mic: URL?, system: URL?)) async -> Void
        let finalize: (_ recordings: (mic: URL?, system: URL?)) async throws -> Void
        let handleFailure: (_ error: Error, _ recordings: (mic: URL?, system: URL?)) async -> Void
    }

    struct RecorderState {
        let recorderIsRecording: Bool
        let isRecording: Bool
        let isStarting: Bool
        let isStartOperationInFlight: Bool
    }

    struct Operations {
        let stopRecorders: StopRecorders
        let cancelIncremental: Action
        let cancelPostStartTasks: () -> Void
        let cleanupTemporaryFiles: CleanupTemporaryFiles
        let removeMergedAudio: Action
        let resetState: (_ error: Error?, _ transcriptionID: UUID?) async -> Void
        let endExclusivity: Action
        let playStopSound: () -> Void
        let playCancelledSound: () -> Void
    }

    func start(
        isRecording: Bool,
        actions: StartActions,
        operations: Operations,
        handleFailure: (_ error: Error) async -> Void
    ) async {
        guard beginTransition(.starting) else { return }
        defer {
            inFlightTransition = nil
            pendingStartCancellation = false
            pendingStartFailure = nil
        }

        guard !isRecording else { return }
        guard await actions.beginExclusivity() else { return }

        actions.beginState()
        do {
            let audioURL = try await actions.prepare()
            let shouldCancel = pendingStartCancellation
            let recorderError = pendingStartFailure
            if shouldCancel {
                await performCancellation(operations: operations)
            } else if let recorderError {
                await performRecorderFailure(recorderError, operations: operations)
            } else {
                actions.commit(audioURL)
            }
        } catch {
            let shouldCancel = pendingStartCancellation
            let recorderError = pendingStartFailure
            if shouldCancel {
                await performCancellation(operations: operations)
            } else if let recorderError {
                await performRecorderFailure(recorderError, operations: operations)
            } else {
                let recordings = await operations.stopRecorders()
                operations.cancelPostStartTasks()
                await operations.cancelIncremental()
                await operations.cleanupTemporaryFiles(recordings)
                await operations.removeMergedAudio()
                await operations.resetState(error, nil)
                await operations.endExclusivity()
                await handleFailure(error)
            }
        }
    }

    func cancel(
        isRecording: Bool,
        isStarting: Bool,
        operations: Operations
    ) async {
        if inFlightTransition == .starting {
            pendingStartCancellation = true
            return
        }

        guard beginTransition(.cancelling) else { return }
        defer { inFlightTransition = nil }

        guard isRecording || isStarting else { return }

        await performCancellation(operations: operations)
    }

    nonisolated func currentRecorderCallbackGeneration() -> UInt64 {
        recorderCallbackGeneration.value
    }

    func recorderDidFail(
        _ error: Error,
        isRecording: Bool,
        isStarting: Bool,
        generation: UInt64? = nil,
        operations: Operations
    ) async {
        guard generation == nil || generation == currentRecorderCallbackGeneration() else { return }
        if inFlightTransition == .starting {
            pendingStartFailure = error
            return
        }

        guard beginTransition(.recorderFailure) else { return }
        defer { inFlightTransition = nil }

        guard isRecording || isStarting else { return }

        await performRecorderFailure(error, operations: operations)
    }

    func recorderStateDidChange(
        _ state: RecorderState,
        generation: UInt64? = nil,
        operations: Operations
    ) async {
        guard generation == nil || generation == currentRecorderCallbackGeneration() else { return }
        guard !state.recorderIsRecording,
              state.isRecording,
              !state.isStarting,
              !state.isStartOperationInFlight,
              beginTransition(.recorderFailure)
        else { return }
        defer { inFlightTransition = nil }

        await stopAndClean(operations: operations, resetError: nil)
    }

    func stop(
        isRecording: Bool,
        transcribe: Bool,
        operations: Operations,
        actions: StopActions
    ) async {
        guard beginTransition(.stopping) else { return }
        guard isRecording else {
            inFlightTransition = nil
            return
        }

        operations.cancelPostStartTasks()
        let recordings = await operations.stopRecorders()
        await actions.beforeRelease(recordings)
        await operations.endExclusivity()
        operations.playStopSound()

        // Capture is released before transcription/finalization. A new recording
        // must not wait for post-processing of the previous session.
        finalizationCount += 1
        inFlightTransition = nil
        defer { finalizationCount -= 1 }

        do {
            try await actions.finalize(recordings)
            if !transcribe {
                await operations.cancelIncremental()
                await operations.resetState(nil, nil)
            }
        } catch {
            await actions.handleFailure(error, recordings)
        }
    }

    func waitForIdle() async {
        while inFlightTransition != nil || finalizationCount > 0 {
            await Task.yield()
        }
    }

    private func beginTransition(_ phase: TransitionPhase) -> Bool {
        guard inFlightTransition == nil else { return false }
        inFlightTransition = phase
        recorderCallbackGeneration.invalidate()
        return true
    }

    private func performCancellation(operations: Operations) async {
        let recordings = await operations.stopRecorders()
        await operations.cancelIncremental()
        operations.cancelPostStartTasks()
        await operations.cleanupTemporaryFiles(recordings)
        await operations.removeMergedAudio()
        await operations.resetState(nil, nil)
        await operations.endExclusivity()
        operations.playCancelledSound()
    }

    private func performRecorderFailure(_ error: Error, operations: Operations) async {
        await stopAndClean(operations: operations, resetError: error)
    }

    private func stopAndClean(operations: Operations, resetError: Error?) async {
        let recordings = await operations.stopRecorders()
        operations.cancelPostStartTasks()
        await operations.cancelIncremental()
        await operations.cleanupTemporaryFiles(recordings)
        await operations.removeMergedAudio()
        await operations.resetState(resetError, nil)
        await operations.endExclusivity()
    }
}
