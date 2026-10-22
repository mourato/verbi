@testable import VerbiCore
import XCTest

final class AssistantShortcutSuppressionPolicyTests: XCTestCase {
    func testShouldSuppressEnterStopWhileRecordingRequiresToggleAndRecording() {
        XCTAssertFalse(
            AssistantShortcutSuppressionPolicy.shouldSuppressEnterStopWhileRecording(
                assistantUseEnterToStopRecording: false,
                isAssistantRecording: false,
            ),
        )
        XCTAssertFalse(
            AssistantShortcutSuppressionPolicy.shouldSuppressEnterStopWhileRecording(
                assistantUseEnterToStopRecording: false,
                isAssistantRecording: true,
            ),
        )
        XCTAssertFalse(
            AssistantShortcutSuppressionPolicy.shouldSuppressEnterStopWhileRecording(
                assistantUseEnterToStopRecording: true,
                isAssistantRecording: false,
            ),
        )
        XCTAssertTrue(
            AssistantShortcutSuppressionPolicy.shouldSuppressEnterStopWhileRecording(
                assistantUseEnterToStopRecording: true,
                isAssistantRecording: true,
            ),
        )
    }

    func testShouldSuppressKeyDownEventsSuppressesWhenShortcutLayerIsArmed() {
        XCTAssertTrue(
            AssistantShortcutSuppressionPolicy.shouldSuppressKeyDownEvents(
                shouldUseAssistantShortcutLayer: true,
                isShortcutLayerArmed: true,
                shouldSuppressEnterStopWhileRecording: false,
            ),
        )
    }

    func testShouldSuppressKeyDownEventsSuppressesWhenEnterStopWindowIsActive() {
        XCTAssertTrue(
            AssistantShortcutSuppressionPolicy.shouldSuppressKeyDownEvents(
                shouldUseAssistantShortcutLayer: false,
                isShortcutLayerArmed: false,
                shouldSuppressEnterStopWhileRecording: true,
            ),
        )
    }

    func testShouldSuppressKeyDownEventsReturnsFalseWhenNoSafetyWindowIsActive() {
        XCTAssertFalse(
            AssistantShortcutSuppressionPolicy.shouldSuppressKeyDownEvents(
                shouldUseAssistantShortcutLayer: false,
                isShortcutLayerArmed: false,
                shouldSuppressEnterStopWhileRecording: false,
            ),
        )
    }
}
