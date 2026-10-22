@testable import VerbiCore
@testable import VerbiCoreInfrastructure
import XCTest

@MainActor
final class AutoMeetingConfirmationSettingsTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        try AppSettingsTestIsolationLock.acquire()
        UserDefaults.standard.removeObject(forKey: "automaticMeetingRecordingConfirmationDelay")
        UserDefaults.standard.removeObject(forKey: "automaticAutomaticMeetingRecordingConfirmationDelay")
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        UserDefaults.standard.removeObject(forKey: "automaticMeetingRecordingConfirmationDelay")
        UserDefaults.standard.removeObject(forKey: "automaticAutomaticMeetingRecordingConfirmationDelay")
        settings = nil
        AppSettingsTestIsolationLock.release()
    }

    func testConfirmationDelayDefaultsToThreeSecondsAfterReset() {
        settings.automaticRecordingConfirmationDelay = .seconds9

        settings.resetToDefaults()

        XCTAssertEqual(settings.automaticRecordingConfirmationDelay, .seconds3)
    }

    func testConfirmationDelayPersistsSupportedRawValues() {
        for delay in AppSettingsStore.AutomaticMeetingRecordingConfirmationDelay.allCases {
            settings.automaticRecordingConfirmationDelay = delay

            XCTAssertEqual(
                UserDefaults.standard.integer(forKey: "automaticMeetingRecordingConfirmationDelay"),
                delay.rawValue,
            )
            XCTAssertEqual(
                UserDefaults.standard.integer(forKey: "automaticAutomaticMeetingRecordingConfirmationDelay"),
                delay.rawValue
            )
        }
    }

    func testConfirmationDelayRejectsUnsupportedPersistedValues() {
        UserDefaults.standard.removeObject(forKey: "automaticMeetingRecordingConfirmationDelay")
        UserDefaults.standard.set(12, forKey: "automaticAutomaticMeetingRecordingConfirmationDelay")

        let loaded = AppSettingsStore.loadUIAndIndicatorSettings()

        XCTAssertEqual(loaded.automaticRecordingConfirmationDelay, .seconds3)
    }

    func testConfirmationDelayMigratesLegacyKeyIdempotently() {
        UserDefaults.standard.removeObject(forKey: "automaticMeetingRecordingConfirmationDelay")
        UserDefaults.standard.set(9, forKey: "automaticAutomaticMeetingRecordingConfirmationDelay")

        let firstLoad = AppSettingsStore.loadUIAndIndicatorSettings()

        XCTAssertEqual(firstLoad.automaticRecordingConfirmationDelay, .seconds9)
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: "automaticMeetingRecordingConfirmationDelay"),
            AppSettingsStore.AutomaticMeetingRecordingConfirmationDelay.seconds9.rawValue
        )
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: "automaticAutomaticMeetingRecordingConfirmationDelay"),
            AppSettingsStore.AutomaticMeetingRecordingConfirmationDelay.seconds9.rawValue
        )

        UserDefaults.standard.set(6, forKey: "automaticMeetingRecordingConfirmationDelay")
        UserDefaults.standard.set(6, forKey: "automaticAutomaticMeetingRecordingConfirmationDelay")
        AppSettingsStore.migrateLegacyAutomaticMeetingRecordingConfirmationDelayIfNeeded()

        XCTAssertEqual(UserDefaults.standard.integer(forKey: "automaticMeetingRecordingConfirmationDelay"), 6)
    }

    func testConfirmationDelayMigrationPrefersLegacyKeyWhenBothKeysExist() {
        UserDefaults.standard.set(6, forKey: "automaticMeetingRecordingConfirmationDelay")
        UserDefaults.standard.set(9, forKey: "automaticAutomaticMeetingRecordingConfirmationDelay")

        let loaded = AppSettingsStore.loadUIAndIndicatorSettings()

        XCTAssertEqual(loaded.automaticRecordingConfirmationDelay, .seconds9)
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: "automaticMeetingRecordingConfirmationDelay"),
            AppSettingsStore.AutomaticMeetingRecordingConfirmationDelay.seconds9.rawValue
        )
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: "automaticAutomaticMeetingRecordingConfirmationDelay"),
            AppSettingsStore.AutomaticMeetingRecordingConfirmationDelay.seconds9.rawValue
        )
    }

    func testConfirmationDelayMigrationSeedsLegacyKeyForRollback() {
        UserDefaults.standard.set(6, forKey: "automaticMeetingRecordingConfirmationDelay")
        UserDefaults.standard.removeObject(forKey: "automaticAutomaticMeetingRecordingConfirmationDelay")

        AppSettingsStore.migrateLegacyAutomaticMeetingRecordingConfirmationDelayIfNeeded()

        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: "automaticAutomaticMeetingRecordingConfirmationDelay"),
            AppSettingsStore.AutomaticMeetingRecordingConfirmationDelay.seconds6.rawValue
        )
    }
}
