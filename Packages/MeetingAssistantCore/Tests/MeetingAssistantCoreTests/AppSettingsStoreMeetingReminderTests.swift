import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class AppSettingsStoreMeetingReminderTests: XCTestCase {
    override func tearDown() async throws {
        [
            AppSettingsStore.Keys.meetingDetectionMode,
            AppSettingsStore.Keys.meetingDetectionModeMigrated,
            AppSettingsStore.Keys.autoStartRecording,
            AppSettingsStore.Keys.isMeetingTranscriptionEnabled,
            AppSettingsStore.Keys.meetingRemindersEnabled,
            AppSettingsStore.Keys.meetingReminderLeadMinutes,
            AppSettingsStore.Keys.meetingReminderOverlayLeadSeconds,
            AppSettingsStore.Keys.meetingReminderOverlayEnabled,
            AppSettingsStore.Keys.meetingReminderAlertSoundEnabled,
            AppSettingsStore.Keys.meetingReminderMirrorAllScreens,
            AppSettingsStore.Keys.meetingReminderDismissedEventKeys,
        ].forEach(UserDefaults.standard.removeObject)
        AppSettingsStore.shared.resetToDefaults()
    }

    func testMeetingReminderDefaultsRoundTrip() {
        removeReminderDefaults()
        let meeting = AppSettingsStore.loadMeetingSummarySettings()

        XCTAssertEqual(meeting.meetingDetectionMode, .notify)
        XCTAssertTrue(meeting.meetingRemindersEnabled)
        XCTAssertEqual(meeting.meetingReminderLeadMinutes, 15)
        XCTAssertEqual(meeting.meetingReminderOverlayLeadSeconds, 0)
        XCTAssertTrue(meeting.meetingReminderOverlayEnabled)
        XCTAssertFalse(meeting.meetingReminderAlertSoundEnabled)
        XCTAssertFalse(meeting.meetingReminderMirrorAllScreens)
    }

    func testMeetingReminderExplicitValuesPersist() {
        let settings = AppSettingsStore.shared

        settings.meetingRemindersEnabled = false
        settings.meetingReminderLeadMinutes = 5
        settings.meetingReminderOverlayLeadSeconds = 30
        settings.meetingReminderOverlayEnabled = false
        settings.meetingReminderAlertSoundEnabled = true
        settings.meetingReminderMirrorAllScreens = true

        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingRemindersEnabled))
        XCTAssertEqual(UserDefaults.standard.integer(forKey: AppSettingsStore.Keys.meetingReminderLeadMinutes), 5)
        XCTAssertEqual(UserDefaults.standard.integer(forKey: AppSettingsStore.Keys.meetingReminderOverlayLeadSeconds), 30)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingReminderOverlayEnabled))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingReminderAlertSoundEnabled))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingReminderMirrorAllScreens))
    }

    func testDismissedOccurrenceKeyIsStable() {
        let event = MeetingCalendarEventSnapshot(
            eventIdentifier: "abc",
            title: "Standup",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_000_900)
        )

        let key = AppSettingsStore.meetingReminderOccurrenceKey(for: event)
        XCTAssertEqual(key, "abc-1700000000.0")

        AppSettingsStore.shared.dismissMeetingReminderOccurrence(for: event)
        XCTAssertTrue(AppSettingsStore.shared.meetingReminderDismissedOccurrenceKeys().contains(key))
    }

    // MARK: - Slice B: MeetingDetectionMode Migration and Persistence Tests

    func testMeetingDetectionModeFreshInstallDefaultsToNotify() {
        removeReminderDefaults()
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.meetingDetectionMode)
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.meetingDetectionModeMigrated)
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.autoStartRecording)
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.isMeetingTranscriptionEnabled)

        let mode = AppSettingsStore.migrateMeetingDetectionModeIfNeeded()

        XCTAssertEqual(mode, .notify)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingDetectionMode), "notify")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingDetectionModeMigrated))
    }

    func testMeetingDetectionModeMigrationFromAutoStartAndTranscription() {
        removeReminderDefaults()
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.meetingDetectionMode)
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.meetingDetectionModeMigrated)
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.autoStartRecording)
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.isMeetingTranscriptionEnabled)
        UserDefaults.standard.set(false, forKey: AppSettingsStore.Keys.meetingRemindersEnabled)

        let mode = AppSettingsStore.migrateMeetingDetectionModeIfNeeded()

        XCTAssertEqual(mode, .auto)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingDetectionMode), "auto")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingDetectionModeMigrated))
    }

    func testMeetingDetectionModeMigrationFromRemindersOnly() {
        removeReminderDefaults()
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.meetingDetectionMode)
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.meetingDetectionModeMigrated)
        UserDefaults.standard.set(false, forKey: AppSettingsStore.Keys.autoStartRecording)
        UserDefaults.standard.set(false, forKey: AppSettingsStore.Keys.isMeetingTranscriptionEnabled)
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.meetingRemindersEnabled)

        let mode = AppSettingsStore.migrateMeetingDetectionModeIfNeeded()

        XCTAssertEqual(mode, .notify)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingDetectionMode), "notify")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingDetectionModeMigrated))
    }

    func testMeetingDetectionModeMigrationWhenRemindersDisabled() {
        removeReminderDefaults()
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.meetingDetectionMode)
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.meetingDetectionModeMigrated)
        UserDefaults.standard.set(false, forKey: AppSettingsStore.Keys.autoStartRecording)
        UserDefaults.standard.set(false, forKey: AppSettingsStore.Keys.isMeetingTranscriptionEnabled)
        UserDefaults.standard.set(false, forKey: AppSettingsStore.Keys.meetingRemindersEnabled)

        let mode = AppSettingsStore.migrateMeetingDetectionModeIfNeeded()

        XCTAssertEqual(mode, .off)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingDetectionMode), "off")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: AppSettingsStore.Keys.meetingDetectionModeMigrated))
    }

    func testMeetingDetectionModeMigrationWhenAutoStartWithoutTranscription() {
        removeReminderDefaults()
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.meetingDetectionMode)
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.meetingDetectionModeMigrated)
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.autoStartRecording)
        UserDefaults.standard.set(false, forKey: AppSettingsStore.Keys.isMeetingTranscriptionEnabled)
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.meetingRemindersEnabled)

        let mode = AppSettingsStore.migrateMeetingDetectionModeIfNeeded()

        XCTAssertEqual(mode, .notify)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingDetectionMode), "notify")
    }

    func testMeetingDetectionModeMigrationIsIdempotentWhenAlreadyMigrated() {
        removeReminderDefaults()
        UserDefaults.standard.set("off", forKey: AppSettingsStore.Keys.meetingDetectionMode)
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.meetingDetectionModeMigrated)
        // Legacy keys say auto, but migration flag is already true
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.autoStartRecording)
        UserDefaults.standard.set(true, forKey: AppSettingsStore.Keys.isMeetingTranscriptionEnabled)

        let mode = AppSettingsStore.migrateMeetingDetectionModeIfNeeded()

        XCTAssertEqual(mode, .off)
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingDetectionMode), "off")
    }

    func testMeetingDetectionModeSettingPersistsAndSyncsDerivedProperties() {
        let settings = AppSettingsStore.shared

        settings.meetingDetectionMode = .off
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingDetectionMode), "off")
        XCTAssertFalse(settings.meetingRemindersEnabled)
        XCTAssertFalse(settings.autoStartRecording)

        settings.meetingDetectionMode = .notify
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingDetectionMode), "notify")
        XCTAssertTrue(settings.meetingRemindersEnabled)
        XCTAssertFalse(settings.autoStartRecording)

        settings.meetingDetectionMode = .auto
        XCTAssertEqual(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingDetectionMode), "auto")
        XCTAssertTrue(settings.meetingRemindersEnabled)
        XCTAssertTrue(settings.autoStartRecording)
    }

    func testMeetingDetectionModeResetsToDefaults() {
        let settings = AppSettingsStore.shared
        settings.meetingDetectionMode = .off

        settings.resetMeetingReminderDefaults()

        XCTAssertEqual(settings.meetingDetectionMode, .notify)
        XCTAssertNil(UserDefaults.standard.string(forKey: AppSettingsStore.Keys.meetingDetectionMode))
        XCTAssertNil(UserDefaults.standard.object(forKey: AppSettingsStore.Keys.meetingDetectionModeMigrated))
    }

    private func removeReminderDefaults() {
        [
            AppSettingsStore.Keys.meetingDetectionMode,
            AppSettingsStore.Keys.meetingDetectionModeMigrated,
            AppSettingsStore.Keys.autoStartRecording,
            AppSettingsStore.Keys.isMeetingTranscriptionEnabled,
            AppSettingsStore.Keys.meetingRemindersEnabled,
            AppSettingsStore.Keys.meetingReminderLeadMinutes,
            AppSettingsStore.Keys.meetingReminderOverlayLeadSeconds,
            AppSettingsStore.Keys.meetingReminderOverlayEnabled,
            AppSettingsStore.Keys.meetingReminderAlertSoundEnabled,
            AppSettingsStore.Keys.meetingReminderMirrorAllScreens,
        ].forEach(UserDefaults.standard.removeObject)
    }
}
