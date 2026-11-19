import Foundation
@testable import VerbiCore
import XCTest

final class AppIdentityContractTests: XCTestCase {
    func testVisibleBrandAndProtectedIdentifiersFollowBuildConfiguration() {
        #if DEBUG
            XCTAssertEqual(AppIdentity.displayName, "Verbi Dev")
            XCTAssertEqual(AppIdentity.bundleIdentifier, "com.mourato.verbi.dev")
            XCTAssertEqual(AppIdentity.appURLScheme, "verbi-dev")
            XCTAssertEqual(AppIdentity.appSupportDirectoryName, "Verbi Dev")
            XCTAssertEqual(AppIdentity.logDirectoryName, "Verbi Dev")
            XCTAssertEqual(AppIdentity.keychainServiceIdentifier, "com.mourato.verbi.dev")
            XCTAssertEqual(AppIdentity.legacyAppSupportDirectoryNames, [])
            XCTAssertEqual(AppIdentity.legacyLogDirectoryNames, [])
            XCTAssertEqual(AppIdentity.legacyKeychainServiceIdentifiers, [])
            XCTAssertEqual(AppIdentity.legacyUserDefaultsDomains, [])
            XCTAssertEqual(AppIdentity.settingsWindowAutosaveName, "VerbiDevSettingsWindow")
        #else
            XCTAssertEqual(AppIdentity.displayName, "Verbi")
            XCTAssertEqual(AppIdentity.bundleIdentifier, "com.mourato.verbi")
            XCTAssertEqual(AppIdentity.appURLScheme, "verbi")
            XCTAssertEqual(AppIdentity.appSupportDirectoryName, "Verbi")
            XCTAssertEqual(AppIdentity.logDirectoryName, "Verbi")
            XCTAssertEqual(AppIdentity.keychainServiceIdentifier, "com.mourato.verbi")
            XCTAssertEqual(AppIdentity.legacyAppSupportDirectoryNames, ["Prisma", "MeetingAssistant"])
            XCTAssertEqual(AppIdentity.legacyLogDirectoryNames, ["Prisma", "MeetingAssistant"])
            XCTAssertEqual(AppIdentity.legacyKeychainServiceIdentifiers, ["com.mourato.prisma", "com.meeting-assistant"])
            XCTAssertEqual(AppIdentity.legacyUserDefaultsDomains, ["com.mourato.prisma", "com.meetingassistant.app"])
            XCTAssertEqual(AppIdentity.settingsWindowAutosaveName, "MeetingAssistantSettingsWindow")
        #endif

        XCTAssertEqual(AppIdentity.userDefaultsDomainMigrationFlag, "migrations.user_defaults_domain.v2")
        XCTAssertEqual(AppIdentity.hotkeySignatureSeed, "PRH0")
        XCTAssertEqual(AppIdentity.settingsToolbarIdentifier, "MeetingAssistantSettingsToolbar")
    }

    func testManifestUsesPropertyListSections() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/AppIdentity.plist")
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            XCTFail("Manifest must contain a property-list dictionary")
            return
        }
        XCTAssertEqual(Set(plist.keys), ["product", "technical", "persistence", "migration", "internal", "development"])

        guard let migration = plist["migration"] as? [String: Any] else {
            return XCTFail("migration section missing")
        }
        XCTAssertEqual(migration["legacyAppSupportDirectories"] as? [String], ["Prisma", "MeetingAssistant"])
        XCTAssertEqual(migration["legacyLogDirectories"] as? [String], ["Prisma", "MeetingAssistant"])
        XCTAssertEqual(migration["legacyKeychainServices"] as? [String], ["com.mourato.prisma", "com.meeting-assistant"])
        XCTAssertEqual(migration["legacyUserDefaultsDomains"] as? [String], ["com.mourato.prisma", "com.meetingassistant.app"])
    }

    func testDevelopmentIdentityIsSeparateFromReleaseIdentity() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Config/AppIdentity.plist")
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let technical = plist["technical"] as? [String: Any],
              let development = plist["development"] as? [String: Any],
              let persistence = plist["persistence"] as? [String: Any]
        else {
            return XCTFail("identity sections missing")
        }

        XCTAssertEqual(technical["bundleIdentifier"] as? String, "com.mourato.verbi")
        XCTAssertEqual(technical["keychainService"] as? String, "com.mourato.verbi")
        XCTAssertEqual(technical["logSubsystem"] as? String, "com.mourato.verbi")
        XCTAssertEqual(technical["urlScheme"] as? String, "verbi")
        XCTAssertEqual(technical["urlName"] as? String, "com.mourato.verbi.deeplink")
        XCTAssertEqual(persistence["appSupportDirectory"] as? String, "Verbi")
        XCTAssertEqual(persistence["logDirectory"] as? String, "Verbi")

        XCTAssertEqual(development["bundleIdentifier"] as? String, "com.mourato.verbi.dev")
        XCTAssertEqual(development["keychainService"] as? String, "com.mourato.verbi.dev")
        XCTAssertEqual(development["logSubsystem"] as? String, "com.mourato.verbi.dev")
        XCTAssertEqual(development["urlScheme"] as? String, "verbi-dev")
        XCTAssertEqual(development["appSupportDirectory"] as? String, "Verbi Dev")
        XCTAssertEqual(development["logDirectory"] as? String, "Verbi Dev")

        for key in ["bundleIdentifier", "keychainService", "logSubsystem", "urlScheme", "appSupportDirectory", "logDirectory"] {
            XCTAssertNotEqual(technical[key] as? String, development[key] as? String, "\(key) must differ between Release and Debug")
        }
    }
}
