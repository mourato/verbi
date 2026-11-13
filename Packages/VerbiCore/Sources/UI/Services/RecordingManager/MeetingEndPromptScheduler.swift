import Combine
import Foundation

@MainActor
public protocol MeetingEndPromptScheduling {
    func schedule(after interval: TimeInterval, action: @escaping @MainActor () async -> Void) -> AnyCancellable
}

@MainActor
public struct TaskMeetingEndPromptScheduler: MeetingEndPromptScheduling {
    public init() {}

    public func schedule(after interval: TimeInterval, action: @escaping @MainActor () async -> Void) -> AnyCancellable {
        let task = Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(max(0, interval)))
                guard !Task.isCancelled else { return }
                await action()
            } catch {
                // Cancellation ends the scheduled action.
            }
        }
        return AnyCancellable { task.cancel() }
    }
}
