import AppKit
@testable import MeetingAssistantCore
import XCTest

final class SettingsWindowLayoutStateEvaluatorTests: XCTestCase {
    private let visibleScreenFrames = [CGRect(x: 0, y: 0, width: 1_512, height: 948)]
    private let defaultContentSize = CGSize(width: 900, height: 700)
    private let sidebarWidthRange: ClosedRange<CGFloat> = 215...215

    func testValidSavedWindowFramePreservesPersistedState() {
        let evaluation = SettingsWindowLayoutStateEvaluator.evaluate(
            autosaveWindowFrameString: "263 132 900 692 0 0 1512 948 ",
            legacyWindowFrameString: nil,
            splitViewFrameStrings: [],
            visibleScreenFrames: visibleScreenFrames,
            defaultContentSize: defaultContentSize,
            sidebarWidthRange: sidebarWidthRange,
        )

        XCTAssertFalse(evaluation.shouldResetPersistedLayout)
        XCTAssertFalse(evaluation.shouldCenterWindow)
        XCTAssertTrue(evaluation.requiresFrameClamp)
    }

    func testSavedWindowFrameShiftedPastRightEdgeRequestsReset() {
        let evaluation = SettingsWindowLayoutStateEvaluator.evaluate(
            autosaveWindowFrameString: "1180 132 900 692 0 0 1512 948 ",
            legacyWindowFrameString: nil,
            splitViewFrameStrings: [],
            visibleScreenFrames: visibleScreenFrames,
            defaultContentSize: defaultContentSize,
            sidebarWidthRange: sidebarWidthRange,
        )

        XCTAssertEqual(
            evaluation.keysToReset,
            [SettingsWindowLayoutStateEvaluator.autosaveWindowFrameDefaultsKey],
        )
        XCTAssertTrue(evaluation.shouldCenterWindow)
        XCTAssertFalse(evaluation.requiresFrameClamp)
    }

    func testSavedWindowFrameFromDisconnectedMonitorRequestsReset() {
        let evaluation = SettingsWindowLayoutStateEvaluator.evaluate(
            autosaveWindowFrameString: "1800 132 900 692 0 0 2560 1409 ",
            legacyWindowFrameString: nil,
            splitViewFrameStrings: [],
            visibleScreenFrames: visibleScreenFrames,
            defaultContentSize: defaultContentSize,
            sidebarWidthRange: sidebarWidthRange,
        )

        XCTAssertEqual(
            evaluation.keysToReset,
            [SettingsWindowLayoutStateEvaluator.autosaveWindowFrameDefaultsKey],
        )
        XCTAssertTrue(evaluation.shouldCenterWindow)
        XCTAssertFalse(evaluation.requiresFrameClamp)
    }

    func testMissingFrameWithStaleSplitWidthsResetsSplitLayoutOnly() {
        let evaluation = SettingsWindowLayoutStateEvaluator.evaluate(
            autosaveWindowFrameString: nil,
            legacyWindowFrameString: nil,
            splitViewFrameStrings: [
                "0.000000, 0.000000, 420.000000, 450.000000, NO, NO",
                "0.000000, 0.000000, 900.000000, 450.000000, NO, NO",
            ],
            visibleScreenFrames: visibleScreenFrames,
            defaultContentSize: defaultContentSize,
            sidebarWidthRange: sidebarWidthRange,
        )

        XCTAssertEqual(
            evaluation.keysToReset,
            [SettingsWindowLayoutStateEvaluator.splitViewFramesDefaultsKey],
        )
        XCTAssertTrue(evaluation.shouldCenterWindow)
        XCTAssertFalse(evaluation.requiresFrameClamp)
    }

    func testSplitViewWidthsInconsistentWithWindowWidthResetSplitLayout() {
        let evaluation = SettingsWindowLayoutStateEvaluator.evaluate(
            autosaveWindowFrameString: "263 132 900 692 0 0 1512 948 ",
            legacyWindowFrameString: nil,
            splitViewFrameStrings: [
                "0.000000, 0.000000, 208.000000, 450.000000, NO, NO",
                "0.000000, 0.000000, 760.000000, 450.000000, NO, NO",
            ],
            visibleScreenFrames: visibleScreenFrames,
            defaultContentSize: defaultContentSize,
            sidebarWidthRange: sidebarWidthRange,
        )

        XCTAssertEqual(
            evaluation.keysToReset,
            [SettingsWindowLayoutStateEvaluator.splitViewFramesDefaultsKey],
        )
        XCTAssertFalse(evaluation.shouldCenterWindow)
        XCTAssertTrue(evaluation.requiresFrameClamp)
    }

    func testSidebarWidthFarOutsideConfiguredRangeResetsSplitLayout() {
        let evaluation = SettingsWindowLayoutStateEvaluator.evaluate(
            autosaveWindowFrameString: "263 132 900 692 0 0 1512 948 ",
            legacyWindowFrameString: nil,
            splitViewFrameStrings: [
                "0.000000, 0.000000, 80.000000, 450.000000, NO, NO",
                "0.000000, 0.000000, 900.000000, 450.000000, NO, NO",
            ],
            visibleScreenFrames: visibleScreenFrames,
            defaultContentSize: defaultContentSize,
            sidebarWidthRange: sidebarWidthRange,
        )

        XCTAssertEqual(
            evaluation.keysToReset,
            [SettingsWindowLayoutStateEvaluator.splitViewFramesDefaultsKey],
        )
        XCTAssertFalse(evaluation.shouldCenterWindow)
        XCTAssertTrue(evaluation.requiresFrameClamp)
    }

    func testEmptyDefaultsCentersWindowWithoutReset() {
        let evaluation = SettingsWindowLayoutStateEvaluator.evaluate(
            autosaveWindowFrameString: nil,
            legacyWindowFrameString: nil,
            splitViewFrameStrings: [],
            visibleScreenFrames: visibleScreenFrames,
            defaultContentSize: defaultContentSize,
            sidebarWidthRange: sidebarWidthRange,
        )

        XCTAssertFalse(evaluation.shouldResetPersistedLayout)
        XCTAssertTrue(evaluation.shouldCenterWindow)
        XCTAssertFalse(evaluation.requiresFrameClamp)
    }
}
