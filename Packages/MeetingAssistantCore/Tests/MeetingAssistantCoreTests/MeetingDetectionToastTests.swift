import AppKit
import Foundation
@testable import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreInfrastructure
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class MeetingDetectionToastTests: XCTestCase {
    private var controller: MeetingDetectionToastController!

    override func setUp() async throws {
        try await super.setUp()
        controller = MeetingDetectionToastController()
    }

    override func tearDown() async throws {
        controller.hide()
        controller = nil
        try await super.tearDown()
    }

    // MARK: - State Tests

    func testToastStateDetectedProperties() {
        let state = MeetingDetectionToastState.detected(
            app: .zoom,
            appName: "Zoom",
            context: nil
        )

        XCTAssertEqual(state.app, .zoom)
        XCTAssertEqual(state.appName, "Zoom")

        if case .detected(let app, let appName, let context) = state {
            XCTAssertEqual(app, .zoom)
            XCTAssertEqual(appName, "Zoom")
            XCTAssertNil(context)
        } else {
            XCTFail("Expected .detected state")
        }
    }

    func testToastStateRecordingProperties() {
        let startedAt = Date()
        let state = MeetingDetectionToastState.recording(
            app: .googleMeet,
            appName: "Google Meet",
            startedAt: startedAt
        )

        XCTAssertEqual(state.app, .googleMeet)
        XCTAssertEqual(state.appName, "Google Meet")

        if case .recording(let app, let appName, let start) = state {
            XCTAssertEqual(app, .googleMeet)
            XCTAssertEqual(appName, "Google Meet")
            XCTAssertEqual(start, startedAt)
        } else {
            XCTFail("Expected .recording state")
        }
    }

    func testToastStateEndedProperties() {
        let state = MeetingDetectionToastState.ended(
            app: .microsoftTeams,
            appName: "Microsoft Teams",
            countdownSeconds: 10,
            totalCountdownSeconds: 30
        )

        XCTAssertEqual(state.app, .microsoftTeams)
        XCTAssertEqual(state.appName, "Microsoft Teams")

        if case .ended(let app, let appName, let countdown, let total) = state {
            XCTAssertEqual(app, .microsoftTeams)
            XCTAssertEqual(appName, "Microsoft Teams")
            XCTAssertEqual(countdown, 10)
            XCTAssertEqual(total, 30)
        } else {
            XCTFail("Expected .ended state")
        }
    }

    // MARK: - Controller Panel Configuration Tests

    func testToastControllerPanelConfiguration() {
        let panel = controller.ensurePanel()

        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .statusBar)
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.stationary))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertEqual(panel.backgroundColor, .clear)
        XCTAssertTrue(panel.hasShadow)
        XCTAssertFalse(panel.ignoresMouseEvents)
    }

    // MARK: - Presentation and Dismissal Tests

    func testToastControllerShowDetectedAndHide() {
        XCTAssertFalse(controller.isVisible)
        XCTAssertNil(controller.currentState)

        controller.show(
            state: .detected(app: .zoom, appName: "Zoom", context: nil)
        )

        XCTAssertTrue(controller.isVisible)
        XCTAssertNotNil(controller.currentState)
        XCTAssertEqual(controller.currentState?.appName, "Zoom")

        controller.hide()

        XCTAssertFalse(controller.isVisible)
        XCTAssertNil(controller.currentState)
    }

    // MARK: - Rapid Transition Tests

    func testToastControllerRapidTransitionDetectedToRecording() {
        controller.show(
            state: .detected(app: .googleMeet, appName: "Google Meet", context: nil)
        )
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.currentState?.appName, "Google Meet")

        let startTime = Date()
        controller.update(
            state: .recording(app: .googleMeet, appName: "Google Meet", startedAt: startTime)
        )

        XCTAssertTrue(controller.isVisible)
        if case .recording(_, _, let startedAt) = controller.currentState {
            XCTAssertEqual(startedAt, startTime)
        } else {
            XCTFail("Expected rapid transition to update currentState to .recording")
        }
    }

    // MARK: - Callback Wiring Tests

    func testToastControllerCallbacksTriggered() {
        var recordCalled = false
        var chooseTemplateCalled = false
        var recordWithoutSummaryCalled = false
        var stopCalled = false
        var continueCalled = false
        var dismissCalled = false

        controller.onRecord = { recordCalled = true }
        controller.onChooseTemplate = { chooseTemplateCalled = true }
        controller.onRecordWithoutSummary = { recordWithoutSummaryCalled = true }
        controller.onStop = { stopCalled = true }
        controller.onContinue = { continueCalled = true }
        controller.onDismiss = { dismissCalled = true }

        controller.onRecord?()
        controller.onChooseTemplate?()
        controller.onRecordWithoutSummary?()
        controller.onStop?()
        controller.onContinue?()
        controller.onDismiss?()

        XCTAssertTrue(recordCalled)
        XCTAssertTrue(chooseTemplateCalled)
        XCTAssertTrue(recordWithoutSummaryCalled)
        XCTAssertTrue(stopCalled)
        XCTAssertTrue(continueCalled)
        XCTAssertTrue(dismissCalled)
    }

    // MARK: - Reposition Tests

    func testToastControllerRepositionPlacesPanelBelowMenuBar() {
        let panel = controller.ensurePanel()
        controller.reposition(panel: panel)

        let frame = panel.frame
        XCTAssertEqual(frame.width, MeetingDetectionToastController.Constants.toastWidth)
        XCTAssertEqual(frame.height, MeetingDetectionToastController.Constants.toastHeight)

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visibleFrame = screen.visibleFrame
            let expectedTop = visibleFrame.maxY - MeetingDetectionToastController.Constants.topMargin
            let actualTop = frame.maxY
            XCTAssertEqual(actualTop, expectedTop, accuracy: 2.0)
        }
    }
}
