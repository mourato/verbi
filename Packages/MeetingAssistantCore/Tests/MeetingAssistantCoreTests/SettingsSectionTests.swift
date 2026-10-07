@testable import MeetingAssistantCoreUI
import XCTest

final class SettingsSectionTests: XCTestCase {
    func testVisibleSections_OrderMatchesProductConcepts() {
        XCTAssertEqual(
            SettingsSection.visibleSections,
            [.activity, .history, .dictionary, .modes, .meetings, .models, .audio, .shortcuts, .system],
        )
    }

    func testLegacyRedirect_MetricsAndTranscriptionsMapToVisibleDestinations() {
        XCTAssertEqual(SettingsSection.metrics.visibleSection, .activity)
        XCTAssertEqual(SettingsSection.transcriptions.visibleSection, .history)
        XCTAssertTrue(SettingsSection.metrics.isLegacyRedirect)
        XCTAssertTrue(SettingsSection.transcriptions.isLegacyRedirect)
    }

    func testLegacyRedirect_IntelligenceEnhancementsVocabularyMapToNewHomes() {
        XCTAssertEqual(SettingsSection.intelligence.visibleSection, .models)
        XCTAssertEqual(SettingsSection.enhancements.visibleSection, .modes)
        XCTAssertEqual(SettingsSection.vocabulary.visibleSection, .dictionary)
        XCTAssertTrue(SettingsSection.intelligence.isLegacyRedirect)
        XCTAssertTrue(SettingsSection.enhancements.isLegacyRedirect)
        XCTAssertTrue(SettingsSection.vocabulary.isLegacyRedirect)
    }

    func testLegacyRedirect_PermissionsAndGeneralMapToSystem() {
        XCTAssertEqual(SettingsSection.permissions.visibleSection, .system)
        XCTAssertEqual(SettingsSection.general.visibleSection, .system)
        XCTAssertTrue(SettingsSection.permissions.isLegacyRedirect)
        XCTAssertTrue(SettingsSection.general.isLegacyRedirect)
    }

    func testVisibleSections_AreNotLegacyRedirects() {
        for section in SettingsSection.visibleSections {
            XCTAssertFalse(section.isLegacyRedirect, "\(section) should not be a legacy redirect")
        }
    }

    func testVisibleSections_UseFilledSidebarIconsWhenSelected() {
        XCTAssertEqual(SettingsSection.activity.icon, "chart.pie")
        XCTAssertEqual(SettingsSection.activity.selectedSidebarIcon, "chart.pie.fill")
        XCTAssertEqual(SettingsSection.modes.icon, "mic")
        XCTAssertEqual(SettingsSection.modes.selectedSidebarIcon, "mic.fill")
        XCTAssertEqual(SettingsSection.meetings.icon, "bubble.left.and.bubble.right")
        XCTAssertEqual(SettingsSection.meetings.selectedSidebarIcon, "bubble.left.and.bubble.right.fill")
        XCTAssertEqual(SettingsSection.history.icon, "clock")
        XCTAssertEqual(SettingsSection.history.selectedSidebarIcon, "clock.fill")
        XCTAssertEqual(SettingsSection.dictionary.icon, "character.book.closed")
        XCTAssertEqual(SettingsSection.dictionary.selectedSidebarIcon, "character.book.closed.fill")
        XCTAssertEqual(SettingsSection.system.icon, "gearshape.2")
        XCTAssertEqual(SettingsSection.system.selectedSidebarIcon, "gearshape.2.fill")
    }

    func testResolvedVisibleSection_ParsesOldRawValues() {
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "metrics"), .activity)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "transcriptions"), .history)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "models"), .models)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "enhancements"), .modes)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "vocabulary"), .dictionary)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "audio"), .audio)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "permissions"), .system)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "general"), .system)
    }

    func testResolvedDestination_PreservesLegacyDestinations() {
        XCTAssertEqual(
            SettingsSection.resolvedDestination(for: "metrics"),
            SettingsDestination(
                section: .activity,
                activityPendingSheet: .performance,
            ),
        )
        XCTAssertEqual(
            SettingsSection.resolvedDestination(for: "transcriptions"),
            SettingsDestination(section: .history),
        )
    }

    func testResolvedDestination_PreservesSystemSubroutes() {
        XCTAssertEqual(
            SettingsSection.resolvedDestination(for: "general"),
            SettingsDestination(section: .system),
        )
        XCTAssertEqual(
            SettingsSection.resolvedDestination(for: "permissions"),
            SettingsDestination(section: .system),
        )
        XCTAssertEqual(
            SettingsSection.resolvedDestination(for: "audio"),
            SettingsDestination(section: .audio),
        )
        XCTAssertEqual(
            SettingsSection.resolvedDestination(for: "models"),
            SettingsDestination(section: .models),
        )
        XCTAssertEqual(
            SettingsSection.resolvedDestination(for: "vocabulary"),
            SettingsDestination(section: .dictionary),
        )
        XCTAssertEqual(
            SettingsSection.resolvedDestination(for: "dictionary"),
            SettingsDestination(section: .dictionary),
        )
        XCTAssertEqual(
            SettingsSection.resolvedDestination(for: "enhancements"),
            SettingsDestination(section: .modes),
        )
    }

    func testResolvedVisibleSection_ParsesNewRawValues() {
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "activity"), .activity)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "history"), .history)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "dictation"), .modes)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "modes"), .modes)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "assistant"), .modes)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "integrations"), .modes)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "intelligence"), .models)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "system"), .system)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "shortcuts"), .shortcuts)
        XCTAssertEqual(SettingsSection.resolvedVisibleSection(for: "audio"), .audio)
    }

    func testLegacyRedirect_DictationAssistantAndIntegrationsMapToModes() {
        XCTAssertEqual(SettingsSection.dictation.visibleSection, .modes)
        XCTAssertEqual(SettingsSection.assistant.visibleSection, .modes)
        XCTAssertEqual(SettingsSection.integrations.visibleSection, .modes)
        XCTAssertTrue(SettingsSection.dictation.isLegacyRedirect)
        XCTAssertTrue(SettingsSection.assistant.isLegacyRedirect)
        XCTAssertTrue(SettingsSection.integrations.isLegacyRedirect)
    }

    func testResolvedDestination_PreservesModesSubroutes() {
        XCTAssertEqual(
            SettingsSection.resolvedDestination(for: "assistant"),
            SettingsDestination(section: .modes, modesSubroute: .assistant),
        )
        XCTAssertEqual(
            SettingsSection.resolvedDestination(for: "integrations"),
            SettingsDestination(section: .modes, modesSubroute: .integrations),
        )
    }

    func testOldRawValuesStillParseAsSettingsSection() {
        XCTAssertEqual(SettingsSection(rawValue: "metrics"), .metrics)
        XCTAssertEqual(SettingsSection(rawValue: "transcriptions"), .transcriptions)
        XCTAssertEqual(SettingsSection(rawValue: "models"), .models)
        XCTAssertEqual(SettingsSection(rawValue: "enhancements"), .enhancements)
        XCTAssertEqual(SettingsSection(rawValue: "vocabulary"), .vocabulary)
        XCTAssertEqual(SettingsSection(rawValue: "audio"), .audio)
        XCTAssertEqual(SettingsSection(rawValue: "permissions"), .permissions)
        XCTAssertEqual(SettingsSection(rawValue: "general"), .general)
    }

    func testNewRawValuesParse() {
        XCTAssertEqual(SettingsSection(rawValue: "activity"), .activity)
        XCTAssertEqual(SettingsSection(rawValue: "history"), .history)
        XCTAssertEqual(SettingsSection(rawValue: "intelligence"), .intelligence)
        XCTAssertEqual(SettingsSection(rawValue: "system"), .system)
    }
}
