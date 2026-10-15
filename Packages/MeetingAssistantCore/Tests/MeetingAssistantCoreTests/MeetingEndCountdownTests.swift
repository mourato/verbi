import Foundation
@testable import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class MeetingEndCountdownTests: XCTestCase {
    // MARK: - CallControlSignalProvider Tests

    func testCallControlCustomInspectorInCall() async {
        let provider = AccessibilityCallControlProvider { _, _ in
            .inCall
        }
        let state = await provider.evaluateCallState(for: 1234, app: .zoom)
        XCTAssertEqual(state, .inCall)
    }

    func testCallControlCustomInspectorEnded() async {
        let provider = AccessibilityCallControlProvider { _, _ in
            .ended
        }
        let state = await provider.evaluateCallState(for: 1234, app: .microsoftTeams)
        XCTAssertEqual(state, .ended)
    }

    func testCallControlCustomInspectorInconclusive() async {
        let provider = AccessibilityCallControlProvider { _, _ in
            .inconclusive
        }
        let state = await provider.evaluateCallState(for: 1234, app: .googleMeet)
        XCTAssertEqual(state, .inconclusive)
    }

    // MARK: - MeetingEndCountdownCoordinator Tests

    func testCoordinatorInitialState() {
        let coordinator = MeetingEndCountdownCoordinator()
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testCoordinatorStartMonitoringSetsActiveCall() {
        let coordinator = MeetingEndCountdownCoordinator()
        coordinator.startMonitoring(pid: 123, app: .zoom)
        XCTAssertEqual(coordinator.state, .activeCall)
    }

    func testCoordinatorSilenceTrackingAndResume() {
        let coordinator = MeetingEndCountdownCoordinator()
        coordinator.startMonitoring(pid: 123, app: .zoom)

        coordinator.reportAudioOwnershipActivity(hasAudio: false)
        guard case .silenceTracking = coordinator.state else {
            XCTFail("Expected silenceTracking state")
            return
        }

        coordinator.reportAudioOwnershipActivity(hasAudio: true)
        XCTAssertEqual(coordinator.state, .activeCall)
    }

    func testCoordinatorDirectEndTriggers10sCountdown() {
        let coordinator = MeetingEndCountdownCoordinator()
        coordinator.startMonitoring(pid: 123, app: .zoom)

        var lastRemaining = 0
        var lastTotal = 0
        coordinator.onCountdownTick = { remaining, total in
            lastRemaining = remaining
            lastTotal = total
        }

        coordinator.triggerDirectEnd()

        guard case let .countingDown(remaining, total) = coordinator.state else {
            XCTFail("Expected countingDown state")
            return
        }

        XCTAssertEqual(remaining, 10)
        XCTAssertEqual(total, 10)
        XCTAssertEqual(lastRemaining, 10)
        XCTAssertEqual(lastTotal, 10)
    }

    func testCoordinatorCheckCallControlAfterSilenceEnded() async {
        let provider = AccessibilityCallControlProvider { _, _ in
            .ended
        }
        let coordinator = MeetingEndCountdownCoordinator(callControlProvider: provider)
        coordinator.startMonitoring(pid: 123, app: .zoom)

        await coordinator.checkCallControlAfterSilence()

        guard case let .countingDown(remaining, total) = coordinator.state else {
            XCTFail("Expected countingDown state")
            return
        }

        XCTAssertEqual(remaining, 10)
        XCTAssertEqual(total, 10)
    }

    func testCoordinatorCheckCallControlAfterSilenceInconclusive() async {
        let provider = AccessibilityCallControlProvider { _, _ in
            .inconclusive
        }
        let coordinator = MeetingEndCountdownCoordinator(callControlProvider: provider)
        coordinator.startMonitoring(pid: 123, app: .zoom)

        await coordinator.checkCallControlAfterSilence()

        guard case let .countingDown(remaining, total) = coordinator.state else {
            XCTFail("Expected countingDown state with 30s grace period")
            return
        }

        XCTAssertEqual(remaining, 30)
        XCTAssertEqual(total, 30)
    }

    func testCoordinatorCheckCallControlAfterSilenceInCallKeepsActive() async {
        let provider = AccessibilityCallControlProvider { _, _ in
            .inCall
        }
        let coordinator = MeetingEndCountdownCoordinator(callControlProvider: provider)
        coordinator.startMonitoring(pid: 123, app: .zoom)

        await coordinator.checkCallControlAfterSilence()

        XCTAssertEqual(coordinator.state, .activeCall)
    }

    func testCoordinatorContinueRecordingCancelsCountdown() {
        let coordinator = MeetingEndCountdownCoordinator()
        coordinator.startMonitoring(pid: 123, app: .zoom)
        coordinator.triggerDirectEnd()

        var continueCalled = false
        coordinator.onContinueRecording = {
            continueCalled = true
        }

        coordinator.continueRecording()

        XCTAssertEqual(coordinator.state, .cancelled)
        XCTAssertTrue(continueCalled)
    }
}
