@testable import VerbiCore
import XCTest

@MainActor
final class AppSettingsStoreAudioInputSelectionTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testMigrateLegacyAudioDevicePriorityToPowerSelection_UsesFirstLegacyUIDForBothStates() {
        settings.audioDevicePriority = ["usb-mic-primary", "usb-mic-backup"]
        settings.microphoneWhenChargingUID = nil
        settings.microphoneOnBatteryUID = nil

        settings.migrateLegacyAudioDevicePriorityToPowerSelectionIfNeeded()

        XCTAssertEqual(settings.microphoneWhenChargingUID, "usb-mic-primary")
        XCTAssertEqual(settings.microphoneOnBatteryUID, "usb-mic-primary")
    }

    func testMigrateLegacyAudioDevicePriorityToPowerSelection_DoesNotOverrideExistingSelection() {
        settings.audioDevicePriority = ["usb-mic-primary", "usb-mic-backup"]
        settings.microphoneWhenChargingUID = "already-selected"
        settings.microphoneOnBatteryUID = nil

        settings.migrateLegacyAudioDevicePriorityToPowerSelectionIfNeeded()

        XCTAssertEqual(settings.microphoneWhenChargingUID, "already-selected")
        XCTAssertNil(settings.microphoneOnBatteryUID)
    }

    func testRemoveRetiredDictionaryQuickAddShortcutClearsOrphanedUserDefaultsKey() {
        let key = "dictionaryQuickAddShortcutDefinition"
        UserDefaults.standard.set(Data([0x01, 0x02]), forKey: key)
        XCTAssertNotNil(UserDefaults.standard.object(forKey: key))

        settings.removeRetiredDictionaryQuickAddShortcutIfNeeded()

        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }
}
