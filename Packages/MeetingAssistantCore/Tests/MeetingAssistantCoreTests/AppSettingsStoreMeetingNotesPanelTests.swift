import Foundation
import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class AppSettingsStoreMeetingNotesPanelTests: XCTestCase {
    override func tearDown() async throws {
        [
            AppSettingsStore.Keys.meetingNotesHotkeyEnabled,
            AppSettingsStore.Keys.meetingNotesShortcutDefinition,
            AppSettingsStore.Keys.meetingNotesTranslucentPanel,
            AppSettingsStore.Keys.meetingNotesShowOnAllSpaces,
            AppSettingsStore.Keys.meetingNotesHideFromScreenCapture,
            AppSettingsStore.Keys.meetingNotesAutoSizeHeight,
            AppSettingsStore.Keys.meetingNotesEditorTheme,
            AppSettingsStore.Keys.meetingNotesTextSize,
            AppSettingsStore.Keys.meetingNotesLastEditedCalendarEventIdentifier,
        ].forEach(UserDefaults.standard.removeObject)
        AppSettingsStore.shared.resetToDefaults()
    }

    func testMeetingNotesPanelDefaultsRoundTrip() {
        removePanelDefaults()
        let meeting = AppSettingsStore.loadMeetingSummarySettings()

        XCTAssertTrue(meeting.meetingNotesHotkeyEnabled)
        XCTAssertEqual(meeting.meetingNotesShortcutDefinition, AppSettingsStore.defaultMeetingNotesShortcutDefinition)
        XCTAssertTrue(meeting.meetingNotesTranslucentPanel)
        XCTAssertTrue(meeting.meetingNotesShowOnAllSpaces)
        XCTAssertFalse(meeting.meetingNotesHideFromScreenCapture)
        XCTAssertTrue(meeting.meetingNotesAutoSizeHeight)
        XCTAssertEqual(meeting.meetingNotesEditorTheme, "")
        XCTAssertEqual(meeting.meetingNotesTextSize, AppSettingsStore.defaultMeetingNotesTextSize)
        XCTAssertNil(meeting.meetingNotesLastEditedCalendarEventIdentifier)
    }

    func testMeetingNotesPanelExplicitValuesPersist() {
        let settings = AppSettingsStore.shared

        settings.meetingNotesHotkeyEnabled = false
        settings.meetingNotesShortcutDefinition = nil
        settings.meetingNotesTranslucentPanel = false
        settings.meetingNotesShowOnAllSpaces = false
        settings.meetingNotesHideFromScreenCapture = true
        settings.meetingNotesAutoSizeHeight = false
        settings.meetingNotesEditorTheme = "dark"
        settings.meetingNotesTextSize = 18
        settings.meetingNotesLastEditedCalendarEventIdentifier = "event-123"

        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingNotesHotkeyEnabled))
        XCTAssertNil(settings.meetingNotesShortcutDefinition)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingNotesTranslucentPanel))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingNotesShowOnAllSpaces))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingNotesHideFromScreenCapture))
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingNotesAutoSizeHeight))
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingNotesEditorTheme), "dark")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: AppSettingsStore.Keys.meetingNotesTextSize), 18)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingNotesLastEditedCalendarEventIdentifier),
            "event-123",
        )
    }

    private func removePanelDefaults() {
        [
            AppSettingsStore.Keys.meetingNotesHotkeyEnabled,
            AppSettingsStore.Keys.meetingNotesShortcutDefinition,
            AppSettingsStore.Keys.meetingNotesTranslucentPanel,
            AppSettingsStore.Keys.meetingNotesShowOnAllSpaces,
            AppSettingsStore.Keys.meetingNotesHideFromScreenCapture,
            AppSettingsStore.Keys.meetingNotesAutoSizeHeight,
            AppSettingsStore.Keys.meetingNotesEditorTheme,
            AppSettingsStore.Keys.meetingNotesTextSize,
            AppSettingsStore.Keys.meetingNotesLastEditedCalendarEventIdentifier,
        ].forEach(UserDefaults.standard.removeObject)
    }
}
