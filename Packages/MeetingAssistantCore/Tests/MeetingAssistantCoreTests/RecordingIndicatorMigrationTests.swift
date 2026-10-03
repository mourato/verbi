import Foundation
@testable import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class RecordingIndicatorMigrationTests: XCTestCase {
    func testLegacyNoneDisablesIndicatorAndRetiresStyleKey() throws {
        try verifyMigration(style: "none", enabled: true, expectedEnabled: false)
    }

    func testLegacySuperPreservesEnabledPreferenceAndRetiresStyleKey() throws {
        try verifyMigration(style: "super", enabled: true, expectedEnabled: true)
        try verifyMigration(style: "super", enabled: false, expectedEnabled: false)
    }

    private func verifyMigration(style: String, enabled: Bool, expectedEnabled: Bool) throws {
        try AppSettingsTestIsolationLock.acquire()
        defer { AppSettingsTestIsolationLock.release() }
        let defaults = UserDefaults.standard
        let keys = ["recordingIndicatorStyle", "recordingIndicatorEnabled"]
        let originalValues = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, originalValues) {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        defaults.set(style, forKey: keys[0])
        defaults.set(enabled, forKey: keys[1])

        let loaded = AppSettingsStore.loadUIAndIndicatorSettings()

        XCTAssertEqual(loaded.recordingIndicatorEnabled, expectedEnabled)
        XCTAssertEqual(defaults.bool(forKey: keys[1]), expectedEnabled)
        XCTAssertNil(defaults.object(forKey: keys[0]))
        // Subsequent loads cannot reapply the legacy value.
        defaults.set(true, forKey: keys[1])
        XCTAssertTrue(AppSettingsStore.loadUIAndIndicatorSettings().recordingIndicatorEnabled)
    }
}
