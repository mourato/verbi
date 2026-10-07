@testable import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class NavigationServiceTests: XCTestCase {
    private func resetNavigationService() {
        NavigationService.shared.registerOpenSettingsHandler {}
        NavigationService.shared.registerOpenOnboardingHandler {}
        NavigationService.shared.requestedSettingsSection = nil
        NavigationService.shared.setSettingsSidebarVisible(true)
    }

    func testOpenSettingsUsesRegisteredHandler() {
        resetNavigationService()
        let expectation = XCTestExpectation(description: "open settings handler invoked")

        NavigationService.shared.registerOpenSettingsHandler {
            expectation.fulfill()
        }

        NavigationService.shared.openSettings()
        wait(for: [expectation], timeout: 1)
    }

    func testOpenOnboardingUsesRegisteredHandler() {
        resetNavigationService()
        let expectation = XCTestExpectation(description: "open onboarding handler invoked")

        NavigationService.shared.registerOpenOnboardingHandler {
            expectation.fulfill()
        }

        NavigationService.shared.openOnboarding()
        wait(for: [expectation], timeout: 1)
    }

    func testRequestSettingsSidebarToggleIncrementsRequestID() {
        resetNavigationService()
        let initialValue = NavigationService.shared.settingsSidebarToggleRequestID

        NavigationService.shared.requestSettingsSidebarToggle()

        XCTAssertEqual(NavigationService.shared.settingsSidebarToggleRequestID, initialValue + 1)
    }

    func testSetSettingsSidebarVisibleUpdatesCurrentState() {
        resetNavigationService()
        NavigationService.shared.setSettingsSidebarVisible(false)

        XCTAssertFalse(NavigationService.shared.isSettingsSidebarVisible)
    }

    func testOpenHistoryRequestsHistorySection() {
        resetNavigationService()

        NavigationService.shared.openHistory()

        XCTAssertEqual(NavigationService.shared.requestedSettingsSection, "history")
    }

    func testOpenSettingsSectionRequestsGivenSection() {
        resetNavigationService()

        NavigationService.shared.openSettings(section: "history")

        XCTAssertEqual(NavigationService.shared.requestedSettingsSection, "history")
    }
}
