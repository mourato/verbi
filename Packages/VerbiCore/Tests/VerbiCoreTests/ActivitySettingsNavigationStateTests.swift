@testable import VerbiCoreUI
import XCTest

final class ActivitySettingsNavigationStateTests: XCTestCase {
    func testDefaultStateHasNoPendingSheet() {
        let state = ActivitySettingsNavigationState()

        XCTAssertNil(state.pendingSheet)
    }

    func testPendingPerformanceSheetFlag() {
        var state = ActivitySettingsNavigationState(pendingSheet: .performance)

        XCTAssertEqual(state.pendingSheet, .performance)
    }
}
