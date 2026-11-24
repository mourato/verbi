import CoreAudio
import Foundation
import VerbiCoreCommon

final class DefaultInputDeviceWaitHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: DefaultInputDeviceWait?
    private var cancelled = false

    func store(_ waiter: DefaultInputDeviceWait) {
        lock.lock()
        self.waiter = waiter
        let cancelled = cancelled
        lock.unlock()
        if cancelled {
            waiter.cancel()
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let waiter = waiter
        lock.unlock()
        waiter?.cancel()
    }
}

final class DefaultInputDeviceWait: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var listener: AudioObjectPropertyListenerBlock?
    private var finished = false
    private let expectedID: AudioObjectID

    init(expectedID: AudioObjectID, continuation: CheckedContinuation<Void, Error>) {
        self.expectedID = expectedID
        self.continuation = continuation
    }

    func start(timeout: Duration) {
        var address = AudioDeviceManager.defaultInputDeviceAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.defaultInputDidChange()
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            block
        )
        if status == noErr {
            lock.lock()
            let alreadyFinished = finished
            if !alreadyFinished {
                listener = block
            }
            lock.unlock()
            if alreadyFinished {
                Self.removeListener(block)
                return
            }
        } else {
            AppLogger.warning(
                "Unable to observe default input device change. Continuing without waiting.",
                category: .recordingManager,
                extra: ["status": status, "expectedDeviceID": expectedID]
            )
            complete(result: .success(()))
            return
        }
        if AudioDeviceManager.defaultInputDeviceID() == expectedID {
            complete(result: .success(()))
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.completeAsTimedOut()
        }
    }

    func cancel() {
        complete(result: .failure(CancellationError()))
    }

    private func defaultInputDidChange() {
        if AudioDeviceManager.defaultInputDeviceID() == expectedID {
            complete(result: .success(()))
        }
    }

    private func completeAsTimedOut() {
        lock.lock()
        let finished = finished
        lock.unlock()
        if finished {
            return
        }
        AppLogger.warning(
            "Default input device change was not observed. Continuing with current input.",
            category: .recordingManager,
            extra: [
                "expectedDeviceID": expectedID,
                "actualDeviceID": AudioDeviceManager.defaultInputDeviceID() as Any
            ]
        )
        complete(result: .success(()))
    }

    private func complete(result: Result<Void, Error>) {
        lock.lock()
        guard !finished else {
            lock.unlock()
            return
        }
        finished = true
        let pendingContinuation = continuation
        continuation = nil
        let pendingListener = listener
        listener = nil
        lock.unlock()
        if let pendingListener {
            Self.removeListener(pendingListener)
        }
        switch result {
        case .success:
            pendingContinuation?.resume()
        case let .failure(error):
            pendingContinuation?.resume(throwing: error)
        }
    }

    private static func removeListener(_ block: @escaping AudioObjectPropertyListenerBlock) {
        var address = AudioDeviceManager.defaultInputDeviceAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            nil,
            block
        )
    }
}
