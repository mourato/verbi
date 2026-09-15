import Foundation
import MeetingAssistantCoreDomain

public struct TextContextFailureEvent: Sendable, Equatable {
    public let bundleIdentifier: String
    public let reason: ContextAcquisitionError
    public let timestamp: Date

    public init(bundleIdentifier: String, reason: ContextAcquisitionError, timestamp: Date) {
        self.bundleIdentifier = bundleIdentifier
        self.reason = reason
        self.timestamp = timestamp
    }
}

@MainActor
public final class TextContextFailureTracker {
    private let maxEvents: Int
    private var events: [TextContextFailureEvent] = []

    public init(maxEvents: Int = 200) {
        self.maxEvents = maxEvents
    }

    public func recordFailure(
        bundleIdentifier: String,
        reason: ContextAcquisitionError,
        timestamp: Date = Date()
    ) {
        events.append(TextContextFailureEvent(bundleIdentifier: bundleIdentifier, reason: reason, timestamp: timestamp))
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    public func aggregatedFailuresByApp() -> [String: Int] {
        var counts: [String: Int] = [:]
        for event in events {
            counts[event.bundleIdentifier, default: 0] += 1
        }
        return counts
    }

    public func recentFailures(for bundleIdentifier: String, limit: Int = 10) -> [TextContextFailureEvent] {
        events
            .filter { $0.bundleIdentifier == bundleIdentifier }
            .suffix(limit)
    }
}
