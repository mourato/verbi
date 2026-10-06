@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import SwiftUI
import XCTest

final class SettingsSplitViewNavigationTests: XCTestCase {
    func testLibrarySectionsContainExpectedTabs() {
        XCTAssertEqual(SettingsSection.librarySections, [.activity, .history, .dictionary])
    }

    func testSettingsSectionsContainOneConceptPerPage() {
        XCTAssertEqual(
            SettingsSection.settingsSections,
            [.modes, .meetings, .models, .audio, .shortcuts, .system],
        )
    }

    func testAllPrimaryAndSystemSectionsHaveValidDestinations() {
        let allSidebarSections = SettingsSection.visibleSections
        for section in allSidebarSections {
            let destination = section.destination
            XCTAssertEqual(destination.section, section)
            XCTAssertFalse(section.title.isEmpty)
            XCTAssertFalse(section.icon.isEmpty)
            XCTAssertFalse(section.selectedSidebarIcon.isEmpty)
        }
    }

    func testAllSectionsProvideValidBadgeStyling() {
        for section in SettingsSection.allCases {
            _ = section.badgeColor
            _ = section.badgeGradient
        }
    }
}
