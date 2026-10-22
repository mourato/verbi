import AppKit
@testable import VerbiCore
import XCTest

@MainActor
final class AssistantOverlayLifecycleTests: XCTestCase {
    // Exception: these tests prove the AppKit surface itself. Run explicitly
    // with `make test-appkit`; normal suites skip them and every controller is
    // hidden in defer, including when an assertion or await fails.
    private func skipIfOverlayLifecycleDisabled() throws {
        if ProcessInfo.processInfo.environment["MA_SKIP_OVERLAY_LIFECYCLE_TESTS"] == "1" {
            throw XCTSkip("Overlay lifecycle tests disabled for current runner")
        }
    }

    func testFloatingIndicatorRapidShowHideDoesNotCrash() async throws {
        try skipIfOverlayLifecycleDisabled()

        guard NSScreen.main != nil else {
            throw XCTSkip("No main screen available in current test environment")
        }

        let controller = FloatingRecordingIndicatorController()
        defer { controller.hide() }

        for _ in 0..<20 {
            controller.show(mode: .recording)
            controller.hide()
            controller.show(mode: .processing)
            await Task.yield()
        }

        controller.hide()

        XCTAssertFalse(controller.isVisible)
    }

    func testFloatingIndicatorRenderStateShowUpdateHideDoesNotCrash() async throws {
        try skipIfOverlayLifecycleDisabled()

        guard NSScreen.main != nil else {
            throw XCTSkip("No main screen available in current test environment")
        }

        let controller = FloatingRecordingIndicatorController()
        defer { controller.hide() }
        let meetingState = RecordingIndicatorRenderState(mode: .recording, kind: .meeting, meetingType: .standup)
        let processingState = meetingState.with(mode: .processing)

        controller.show(renderState: meetingState)
        controller.update(renderState: processingState)
        controller.hide()

        XCTAssertFalse(controller.isVisible)
    }

    func testFloatingIndicatorAssistantIntegrationRenderStateShowUpdateHideDoesNotCrash() async throws {
        try skipIfOverlayLifecycleDisabled()

        guard NSScreen.main != nil else {
            throw XCTSkip("No main screen available in current test environment")
        }

        let controller = FloatingRecordingIndicatorController()
        defer { controller.hide() }
        let integrationID = UUID()
        let recordingState = RecordingIndicatorRenderState(
            mode: .recording,
            kind: .assistantIntegration,
            assistantIntegrationID: integrationID,
        )
        let processingState = recordingState.with(mode: .processing)

        controller.show(renderState: recordingState)
        controller.update(renderState: processingState)
        controller.hide()

        XCTAssertFalse(controller.isVisible)
    }

    func testAssistantBorderRapidShowHideDoesNotCrash() async throws {
        try skipIfOverlayLifecycleDisabled()

        guard NSScreen.main != nil else {
            throw XCTSkip("No main screen available in current test environment")
        }

        let controller = AssistantScreenBorderController()
        defer { controller.hide() }

        for _ in 0..<20 {
            controller.show()
            controller.hide()
            controller.show()
            await Task.yield()
        }

        controller.hide()

        XCTAssertFalse(controller.isVisible)
    }
}
