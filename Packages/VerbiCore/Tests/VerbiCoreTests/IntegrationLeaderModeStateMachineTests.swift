@testable import VerbiCoreInfrastructure
import XCTest

final class IntegrationLeaderModeStateMachineTests: XCTestCase {
    func testLeaderModeStateMachineTransitionsFromIdleToWaitingForAction() {
        var machine = IntegrationLeaderModeStateMachine()
        let integrationID = UUID()

        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.activeIntegrationID)

        let transition = machine.leaderPressed(for: integrationID)

        XCTAssertTrue(transition.isValid)
        XCTAssertEqual(transition.from, .idle)
        XCTAssertEqual(transition.to, .waitingForAction)
        XCTAssertEqual(machine.state, .waitingForAction)
        XCTAssertEqual(machine.activeIntegrationID, integrationID)
    }

    func testLeaderModeStateMachineTransitionsFromWaitingToActionTriggered() {
        var machine = IntegrationLeaderModeStateMachine()
        let integrationID = UUID()

        _ = machine.leaderPressed(for: integrationID)
        XCTAssertEqual(machine.state, .waitingForAction)

        let transition = machine.actionKeyPressed()

        XCTAssertTrue(transition.isValid)
        XCTAssertEqual(transition.from, .waitingForAction)
        XCTAssertEqual(transition.to, .actionTriggered)
        XCTAssertEqual(machine.state, .actionTriggered)
    }

    func testLeaderModeStateMachineTransitionsToTimedOut() {
        var machine = IntegrationLeaderModeStateMachine()
        let integrationID = UUID()

        _ = machine.leaderPressed(for: integrationID)
        XCTAssertEqual(machine.state, .waitingForAction)

        let transition = machine.timeoutElapsed()

        XCTAssertTrue(transition.isValid)
        XCTAssertEqual(transition.from, .waitingForAction)
        XCTAssertEqual(transition.to, .timedOut)
        XCTAssertEqual(machine.state, .timedOut)
    }

    func testLeaderModeStateMachineTransitionsToCancelled() {
        var machine = IntegrationLeaderModeStateMachine()
        let integrationID = UUID()

        _ = machine.leaderPressed(for: integrationID)
        XCTAssertEqual(machine.state, .waitingForAction)

        let transition = machine.cancelledByEscapeOrBlur()

        XCTAssertTrue(transition.isValid)
        XCTAssertEqual(transition.from, .waitingForAction)
        XCTAssertEqual(transition.to, .cancelled)
        XCTAssertEqual(machine.state, .cancelled)
    }

    func testLeaderModeStateMachineDisarmsFromWaitingForAction() {
        var machine = IntegrationLeaderModeStateMachine()
        let integrationID = UUID()

        _ = machine.leaderPressed(for: integrationID)
        XCTAssertEqual(machine.state, .waitingForAction)
        XCTAssertEqual(machine.activeIntegrationID, integrationID)

        let transition = machine.disarmedExplicitly()

        XCTAssertTrue(transition.isValid)
        XCTAssertEqual(transition.from, .waitingForAction)
        XCTAssertEqual(transition.to, .idle)
        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.activeIntegrationID)
    }

    func testLeaderModeStateMachineRejectsActionKeyFromIdle() {
        var machine = IntegrationLeaderModeStateMachine()

        XCTAssertEqual(machine.state, .idle)

        let transition = machine.actionKeyPressed()

        XCTAssertFalse(transition.isValid)
        XCTAssertEqual(machine.state, .idle)
    }

    func testLeaderModeStateMachineRejectsTimeoutFromIdle() {
        var machine = IntegrationLeaderModeStateMachine()

        XCTAssertEqual(machine.state, .idle)

        let transition = machine.timeoutElapsed()

        XCTAssertFalse(transition.isValid)
        XCTAssertEqual(machine.state, .idle)
    }

    func testLeaderModeStateMachineResetClearsState() {
        var machine = IntegrationLeaderModeStateMachine()
        let integrationID = UUID()

        _ = machine.leaderPressed(for: integrationID)
        XCTAssertEqual(machine.state, .waitingForAction)
        XCTAssertEqual(machine.activeIntegrationID, integrationID)

        machine.reset()

        XCTAssertEqual(machine.state, .idle)
        XCTAssertNil(machine.activeIntegrationID)
    }

    func testLeaderModeStateMachineIgnoresCancellationFromIdle() {
        var machine = IntegrationLeaderModeStateMachine()

        XCTAssertEqual(machine.state, .idle)

        let transition = machine.cancelledByEscapeOrBlur()

        XCTAssertFalse(transition.isValid)
        XCTAssertEqual(machine.state, .idle)
    }

    func testLeaderModeStateMachineIgnoresCancellationFromTimedOut() {
        var machine = IntegrationLeaderModeStateMachine()

        _ = machine.leaderPressed(for: UUID())
        _ = machine.timeoutElapsed()
        XCTAssertEqual(machine.state, .timedOut)

        let transition = machine.cancelledByEscapeOrBlur()

        XCTAssertFalse(transition.isValid)
        XCTAssertEqual(machine.state, .timedOut)
    }

    func testLeaderModeStateMachineIsWaitingForActionProperty() {
        var machine = IntegrationLeaderModeStateMachine()

        XCTAssertFalse(machine.isWaitingForAction)

        _ = machine.leaderPressed(for: UUID())

        XCTAssertTrue(machine.isWaitingForAction)

        _ = machine.actionKeyPressed()

        XCTAssertFalse(machine.isWaitingForAction)
    }

    func testLeaderModeStateMachineHasActionTriggeredProperty() {
        var machine = IntegrationLeaderModeStateMachine()

        XCTAssertFalse(machine.hasActionTriggered)

        _ = machine.leaderPressed(for: UUID())
        XCTAssertFalse(machine.hasActionTriggered)

        _ = machine.actionKeyPressed()

        XCTAssertTrue(machine.hasActionTriggered)
    }

    func testLeaderModeStateMachineIsTerminalStateProperty() {
        var machine = IntegrationLeaderModeStateMachine()

        // Idle is not terminal
        XCTAssertFalse(machine.isTerminalState)

        _ = machine.leaderPressed(for: UUID())
        XCTAssertFalse(machine.isTerminalState)

        _ = machine.actionKeyPressed()
        XCTAssertTrue(machine.isTerminalState)

        machine.reset()
        machine.leaderPressed(for: UUID())
        machine.timeoutElapsed()
        XCTAssertTrue(machine.isTerminalState)

        machine.reset()
        machine.leaderPressed(for: UUID())
        machine.cancelledByEscapeOrBlur()
        XCTAssertTrue(machine.isTerminalState)
    }

    func testLeaderModeStateMachineCustomTimeout() {
        let machine = IntegrationLeaderModeStateMachine(actionTimeoutSeconds: 5.0)

        XCTAssertEqual(machine.actionTimeoutSeconds, 5.0)
        XCTAssertEqual(machine.actionTimeoutNanoseconds, 5_000_000_000)
    }

    func testLeaderModeStateMachineDefaultTimeout() {
        let machine = IntegrationLeaderModeStateMachine()

        XCTAssertEqual(machine.actionTimeoutSeconds, 2.0)
        XCTAssertEqual(machine.actionTimeoutNanoseconds, 2_000_000_000)
    }
}
