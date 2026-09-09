@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

final class SettingsSubpageNavigationStateTests: XCTestCase {
    private enum Route: Hashable {
        case first
        case second
    }

    func testInitialStateStartsAtRoot() {
        let state = SettingsSubpageNavigationState<Route>()

        XCTAssertNil(state.currentRoute)
        XCTAssertFalse(state.canGoBack)
        XCTAssertFalse(state.canGoForward)
    }

    func testOpenMakesDetailRouteCurrent() {
        var state = SettingsSubpageNavigationState<Route>()

        state.open(.first)

        XCTAssertEqual(state.currentRoute, .first)
        XCTAssertTrue(state.canGoBack)
        XCTAssertFalse(state.canGoForward)
    }

    func testBackReturnsToRootAndPreservesForwardRoute() {
        var state = SettingsSubpageNavigationState<Route>(currentRoute: .first)

        _ = state.goBack()

        XCTAssertNil(state.currentRoute)
        XCTAssertFalse(state.canGoBack)
        XCTAssertTrue(state.canGoForward)
        XCTAssertEqual(state.forwardRoute, .first)
    }

    func testForwardRestoresDetailRouteAndClearsForwardRoute() {
        var state = SettingsSubpageNavigationState<Route>(forwardRoute: .second)

        _ = state.goForward()

        XCTAssertEqual(state.currentRoute, .second)
        XCTAssertTrue(state.canGoBack)
        XCTAssertFalse(state.canGoForward)
        XCTAssertNil(state.forwardRoute)
    }

    func testOpeningNewRouteDropsForwardHistory() {
        var state = SettingsSubpageNavigationState<Route>(forwardRoute: .first)

        state.open(.second)

        XCTAssertEqual(state.currentRoute, .second)
        XCTAssertTrue(state.canGoBack)
        XCTAssertFalse(state.canGoForward)
        XCTAssertNil(state.forwardRoute)
    }

    func testDictationStyleRoutesPreserveEditorChildEditorSequence() {
        var state = SettingsSubpageNavigationState<DictationStyleRoute>()
        let styleID = UUID()

        state.open(.editor(styleID: styleID))
        XCTAssertEqual(state.currentRoute, .editor(styleID: styleID))

        state.open(.promptEditor(styleID: styleID))
        XCTAssertEqual(state.currentRoute, .promptEditor(styleID: styleID))

        state.open(.editor(styleID: styleID))
        XCTAssertEqual(state.currentRoute, .editor(styleID: styleID))

        _ = state.goBack()
        XCTAssertNil(state.currentRoute)
    }

    func testClosingEditorAllowsReopeningAnotherMode() {
        var state = SettingsSubpageNavigationState<DictationStyleRoute>()
        let firstStyleID = UUID()
        let secondStyleID = UUID()

        state.open(.editor(styleID: firstStyleID))
        _ = state.goBack()
        state.open(.editor(styleID: secondStyleID))

        XCTAssertEqual(state.currentRoute, .editor(styleID: secondStyleID))
        XCTAssertFalse(state.canGoForward)
    }

    func testRapidRouteChangesLeaveLatestRouteCurrent() {
        var state = SettingsSubpageNavigationState<DictationStyleRoute>()
        let styleID = UUID()

        state.open(.editor(styleID: styleID))
        state.open(.promptEditor(styleID: styleID))
        state.open(.editor(styleID: styleID))

        XCTAssertEqual(state.currentRoute, .editor(styleID: styleID))
        XCTAssertFalse(state.canGoForward)
    }

    func testDictationStyleFocusTargetMapsCreateAndExistingModes() {
        let styleID = UUID()

        XCTAssertEqual(DictationStyleFocusTarget.forStyleID(nil), .addButton)
        XCTAssertEqual(DictationStyleFocusTarget.forStyleID(styleID), .style(styleID))
    }

    func testAssistantAndIntegrationsRoutesDismissToRoot() {
        var state = SettingsSubpageNavigationState<DictationStyleRoute>()

        state.open(.assistant)
        XCTAssertEqual(state.currentRoute, .assistant)
        _ = state.goBack()
        XCTAssertNil(state.currentRoute)
        XCTAssertEqual(state.forwardRoute, .assistant)

        state.open(.integrations)
        XCTAssertEqual(state.currentRoute, .integrations)
        _ = state.goBack()
        XCTAssertNil(state.currentRoute)
        XCTAssertEqual(state.forwardRoute, .integrations)
    }

    func testDictationStyleRouteDismissFocusTargetsMatchDrawerOrigins() {
        let styleID = UUID()

        XCTAssertEqual(DictationStyleRoute.editor(styleID: styleID).dismissFocusTarget, .style(styleID))
        XCTAssertEqual(DictationStyleRoute.editor(styleID: nil).dismissFocusTarget, .addButton)
        XCTAssertEqual(DictationStyleRoute.promptEditor(styleID: styleID).dismissFocusTarget, .style(styleID))
        XCTAssertEqual(DictationStyleRoute.assistant.dismissFocusTarget, .assistant)
        XCTAssertEqual(DictationStyleRoute.integrations.dismissFocusTarget, .integrations)
    }

    func testDictationStyleRouteEscapeReturnsToEditorFromPromptThenDismissesLeaves() {
        let styleID = UUID()

        XCTAssertEqual(
            DictationStyleRoute.promptEditor(styleID: styleID).escapeBehavior,
            .returnToEditor(styleID: styleID),
        )
        XCTAssertEqual(DictationStyleRoute.editor(styleID: styleID).escapeBehavior, .dismissPanel)
        XCTAssertEqual(DictationStyleRoute.assistant.escapeBehavior, .dismissPanel)
        XCTAssertEqual(DictationStyleRoute.integrations.escapeBehavior, .dismissPanel)
    }

    func testSettingsChromeUsesLocalTitleStrip() {
        XCTAssertFalse(SettingsChromeLayoutPolicy.usesLocalTitleStrip)
        XCTAssertEqual(SettingsChromeLayoutPolicy.titlebarClearance, 40)
        XCTAssertEqual(
            SettingsContentSurface.titleStripBoundaryHeight,
            AppDesignSystem.Layout.settingsTitleBarMaterialHeight,
        )
        XCTAssertEqual(SettingsChromeLayoutPolicy.detailTitlebarClearanceHeight(sidebarVisible: true), 0)
        XCTAssertEqual(
            SettingsChromeLayoutPolicy.detailTitlebarClearanceHeight(sidebarVisible: false),
            SettingsChromeLayoutPolicy.titlebarClearance,
        )
    }

    func testSettingsSidePanelWidthNeverExceedsAvailableSpace() {
        XCTAssertEqual(SettingsSidePanelLayout.resolvedWidth(requested: 400, available: 320), 320)
        XCTAssertEqual(SettingsSidePanelLayout.resolvedWidth(requested: 400, available: 640), 400)
        XCTAssertEqual(SettingsSidePanelLayout.resolvedWidth(requested: -1, available: 640), 0)
    }
}
