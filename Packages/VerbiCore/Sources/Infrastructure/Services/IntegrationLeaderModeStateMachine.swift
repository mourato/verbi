import Foundation

/// State machine for integration leader mode.
/// Manages the flow: leader shortcut → waiting for action → action executed or timeout.
///
/// This extends the base AssistantShortcutLayerStateMachine with integration-specific
/// behavior including configurable timeouts and action key detection.
public struct IntegrationLeaderModeStateMachine: Sendable {
    /// Integration-specific states for leader mode
    public enum IntegrationState: String, CaseIterable, Equatable, Sendable {
        /// No leader mode active
        case idle
        /// Leader shortcut pressed, waiting for action key
        case waitingForAction
        /// Action key matched, integration should be triggered
        case actionTriggered
        /// Timeout elapsed while waiting for action
        case timedOut
        /// Cancelled by ESC or window blur
        case cancelled
    }

    /// Events specific to integration leader mode
    public enum IntegrationEvent: String, Equatable, Sendable {
        /// Leader shortcut was pressed
        case leaderPressed
        /// Action key was pressed (second key in sequence)
        case actionKeyPressed
        /// Timeout elapsed while waiting for action
        case timeoutElapsed
        /// Cancelled by ESC or blur
        case cancelledByEscapeOrBlur
        /// Explicitly disarmed
        case disarmedExplicitly
        /// Reset to idle
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

    /// Current state
    public private(set) var state: IntegrationState

    /// Configurable timeout in seconds (default 2s as per P2.2 requirement)
    public var actionTimeoutSeconds: TimeInterval

    /// The integration ID that is currently in leader mode (if any)
    public private(set) var activeIntegrationID: UUID?

    public init(initialState: IntegrationState = .idle, actionTimeoutSeconds: TimeInterval = 2.0) {
        state = initialState
        self.actionTimeoutSeconds = actionTimeoutSeconds
    }

    /// Timeout in nanoseconds for Task.sleep
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
            // Already idle or in terminal state, ignore
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

        // Clear integration ID when returning to idle
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

    /// Check if we're currently waiting for an action key
    public var isWaitingForAction: Bool {
        state == .waitingForAction
    }

    /// Check if an action was triggered
    public var hasActionTriggered: Bool {
        state == .actionTriggered
    }

    /// Check if the state is terminal (no further action possible without new leader press)
    public var isTerminalState: Bool {
        switch state {
        case .idle, .waitingForAction:
            false
        case .actionTriggered, .timedOut, .cancelled:
            true
        }
    }

    /// Reset to idle state
    public mutating func reset() {
        state = .idle
        activeIntegrationID = nil
    }
}

// MARK: - Convenience Extensions

public extension IntegrationLeaderModeStateMachine {
    /// Creates a transition for leader pressed with the given integration ID
    mutating func leaderPressed(for integrationID: UUID) -> Transition {
        transition(on: .leaderPressed, integrationID: integrationID)
    }

    /// Creates a transition for action key pressed
    mutating func actionKeyPressed() -> Transition {
        transition(on: .actionKeyPressed)
    }

    /// Creates a transition for timeout
    mutating func timeoutElapsed() -> Transition {
        transition(on: .timeoutElapsed)
    }

    /// Creates a transition for cancellation by ESC or blur
    mutating func cancelledByEscapeOrBlur() -> Transition {
        transition(on: .cancelledByEscapeOrBlur)
    }

    /// Creates a transition for explicit disarm
    mutating func disarmedExplicitly() -> Transition {
        transition(on: .disarmedExplicitly)
    }
}
