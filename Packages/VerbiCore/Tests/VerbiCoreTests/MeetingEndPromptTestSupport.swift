import Combine
import Foundation
@testable import VerbiCore
@testable import VerbiCoreInfrastructure

@MainActor
final class MeetingEndPromptTestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
final class MeetingEndPromptTestScheduler: MeetingEndPromptScheduling {
    private final class Entry: @unchecked Sendable {
        let deadline: Date
        let action: @MainActor () async -> Void
        private let lock = NSLock()
        private var cancelled = false
        private var fired = false
        private var task: Task<Void, Never>?

        init(deadline: Date, action: @escaping @MainActor () async -> Void) {
            self.deadline = deadline
            self.action = action
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        var isFired: Bool {
            lock.lock()
            defer { lock.unlock() }
            return fired
        }

        var isTaskCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return task?.isCancelled ?? false
        }

        func markFired() {
            lock.lock()
            fired = true
            lock.unlock()
        }

        func install(task: Task<Void, Never>) {
            lock.lock()
            self.task = task
            let shouldCancel = cancelled
            lock.unlock()
            if shouldCancel {
                task.cancel()
            }
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let task = task
            lock.unlock()
            task?.cancel()
        }
    }

    private let clock: MeetingEndPromptTestClock
    private var entries: [Entry] = []
    private(set) var firedCount = 0
    private(set) var lastFiredActionWasCancelled = false

    var entryCount: Int {
        entries.count
    }

    var pendingCount: Int {
        entries.filter { !$0.isCancelled && !$0.isFired }.count
    }

    init(clock: MeetingEndPromptTestClock) {
        self.clock = clock
    }

    func schedule(after interval: TimeInterval, action: @escaping @MainActor () async -> Void) -> AnyCancellable {
        let entry = Entry(deadline: clock.now.addingTimeInterval(interval), action: action)
        entries.append(entry)
        return AnyCancellable { entry.cancel() }
    }

    func advance(by interval: TimeInterval) async {
        let target = clock.now.addingTimeInterval(interval)
        while let index = entries.firstIndex(where: { !$0.isCancelled && !$0.isFired && $0.deadline <= target }) {
            clock.now = max(clock.now, entries[index].deadline)
            await runAction(at: index)
        }
        clock.now = target
    }

    func runAction(at index: Int) async {
        let entry = entries[index]
        guard !entry.isCancelled, !entry.isFired else { return }
        entry.markFired()
        firedCount += 1
        let task = Task { @MainActor in await entry.action() }
        entry.install(task: task)
        await task.value
        lastFiredActionWasCancelled = entry.isTaskCancelled
    }

    func runActionIgnoringCancellation(at index: Int) async {
        let entry = entries[index]
        let task = Task { @MainActor in await entry.action() }
        await task.value
    }
}

@MainActor
final class MeetingEndPromptMediaProvider: MeetingMediaActivityProviding {
    var callOwners: [String] = []

    func currentActivity() -> MeetingMediaActivity {
        MeetingMediaActivity(
            microphoneInUseByAnotherApplication: !callOwners.isEmpty,
            signals: MeetingDetectionSignals(
                microphoneOwnerBundleIdentifier: callOwners.first,
                attribution: callOwners.isEmpty ? .unavailable : .resolved,
                activeCallBundleIdentifiers: callOwners
            )
        )
    }
}
