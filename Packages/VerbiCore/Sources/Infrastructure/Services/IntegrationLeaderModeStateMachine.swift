import Foundation

public struct IntegrationLeaderModeStateMachine: Sendable {
    public enum IntegrationState: String, CaseIterable, Equatable, Sendable {
        case idle
        case waitingForAction
        case actionTriggered
        case timedOut
        case cancelled
    }

    public enum IntegrationEvent: String, Equatable, Sendable {
        case leaderPressed
        case actionKeyPressed
        case timeoutElapsed
        case cancelledByEscapeOrBlur
        case disarmedExplicitly
        case reset
    }

    public struct Transition: Equatable, Sendable {
        public let from: IntegrationState
        public let to: IntegrationState
        public let event: IntegrationEvent
        public let isValid: Bool

        public init(from: IntegrationState, to: IntegrationState, event: IntegrationEvent, isValid: Bool) {
            self.from = from
            self.to = to
            self.event = event
            self.isValid = isValid
        }
    }

    public private(set) var state: IntegrationState

    public var actionTimeoutSeconds: TimeInterval

    public private(set) var activeIntegrationID: UUID?

    public init(initialState: IntegrationState = .idle, actionTimeoutSeconds: TimeInterval = 2.0) {
        state = initialState
        self.actionTimeoutSeconds = actionTimeoutSeconds
    }

    public var actionTimeoutNanoseconds: UInt64 {
        UInt64(actionTimeoutSeconds * 1_000_000_000)
    }

    @discardableResult
    public mutating func transition(on event: IntegrationEvent, integrationID: UUID? = nil) -> Transition {
        let currentState = state
        let nextState: IntegrationState?

        switch (currentState, event) {
        case (.idle, .leaderPressed):
            nextState = .waitingForAction
            if let id = integrationID {
                activeIntegrationID = id
            }

        case (.waitingForAction, .actionKeyPressed):
            nextState = .actionTriggered

        case (.waitingForAction, .timeoutElapsed):
            nextState = .timedOut

        case (.waitingForAction, .cancelledByEscapeOrBlur):
            nextState = .cancelled

        case (.idle, .cancelledByEscapeOrBlur),
             (.timedOut, .cancelledByEscapeOrBlur),
             (.cancelled, .cancelledByEscapeOrBlur),
             (.actionTriggered, .cancelledByEscapeOrBlur):
            nextState = nil

        case (.idle, .disarmedExplicitly),
             (.waitingForAction, .disarmedExplicitly),
             (.timedOut, .disarmedExplicitly),
             (.cancelled, .disarmedExplicitly),
             (.actionTriggered, .disarmedExplicitly):
            nextState = .idle

        case (_, .reset):
            nextState = .idle

        default:
            nextState = nil
        }

        guard let nextState else {
            return Transition(
                from: currentState,
                to: currentState,
                event: event,
                isValid: false
            )
        }

        if nextState == .idle {
            activeIntegrationID = nil
        }

        state = nextState
        return Transition(
            from: currentState,
            to: nextState,
            event: event,
            isValid: true
        )
    }

    public var isWaitingForAction: Bool {
        state == .waitingForAction
    }

    public var hasActionTriggered: Bool {
        state == .actionTriggered
    }

    public var isTerminalState: Bool {
        switch state {
        case .idle, .waitingForAction:
            false
        case .actionTriggered, .timedOut, .cancelled:
            true
        }
    }

    public mutating func reset() {
        state = .idle
        activeIntegrationID = nil
    }
}

public extension IntegrationLeaderModeStateMachine {
    mutating func leaderPressed(for integrationID: UUID) -> Transition {
        transition(on: .leaderPressed, integrationID: integrationID)
    }

    mutating func actionKeyPressed() -> Transition {
        transition(on: .actionKeyPressed)
    }

    mutating func timeoutElapsed() -> Transition {
        transition(on: .timeoutElapsed)
    }

    mutating func cancelledByEscapeOrBlur() -> Transition {
        transition(on: .cancelledByEscapeOrBlur)
    }

    mutating func disarmedExplicitly() -> Transition {
        transition(on: .disarmedExplicitly)
    }
}
