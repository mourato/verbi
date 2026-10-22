import Foundation

public struct DoubleEscapePressDetector: Sendable {
    private let interval: TimeInterval
    private var pendingPressAt: Date?
    private var pendingToken: String?

    public init(interval: TimeInterval = 1.0) {
        self.interval = interval
    }

    public mutating func registerPress(at now: Date = Date(), token: String) -> Bool {
        guard let pendingPressAt, let pendingToken else {
            pendingPressAt = now
            pendingToken = token
            return false
        }

        let elapsed = now.timeIntervalSince(pendingPressAt)
        guard elapsed <= interval, pendingToken == token else {
            self.pendingPressAt = now
            self.pendingToken = token
            return false
        }

        reset()
        return true
    }

    public mutating func reset() {
        pendingPressAt = nil
        pendingToken = nil
    }
}
