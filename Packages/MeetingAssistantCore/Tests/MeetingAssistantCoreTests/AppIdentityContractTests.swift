import Foundation
@testable import MeetingAssistantCore
import XCTest

final class AppIdentityContractTests: XCTestCase {
    func testVisibleBrandAndProtectedIdentifiers() {
        XCTAssertEqual(AppIdentity.displayName, "Verbi")
        XCTAssertEqual(AppIdentity.bundleIdentifier, "com.mourato.verbi")
        XCTAssertEqual(AppIdentity.xpcServiceName, "com.mourato.verbi.ai-service")
        XCTAssertEqual(AppIdentity.appSupportDirectoryName, "Verbi")
        XCTAssertEqual(AppIdentity.logDirectoryName, "Verbi")
        XCTAssertEqual(AppIdentity.keychainServiceIdentifier, "com.mourato.verbi")
        XCTAssertEqual(AppIdentity.legacyAppSupportDirectoryNames, ["Prisma", "MeetingAssistant"])
        XCTAssertEqual(AppIdentity.legacyLogDirectoryNames, ["Prisma", "MeetingAssistant"])
        XCTAssertEqual(AppIdentity.legacyKeychainServiceIdentifiers, ["com.mourato.prisma", "com.meeting-assistant"])
        XCTAssertEqual(AppIdentity.legacyUserDefaultsDomains, ["com.mourato.prisma", "com.meetingassistant.app"])
        XCTAssertEqual(AppIdentity.userDefaultsDomainMigrationFlag, "migrations.user_defaults_domain.v2")
        XCTAssertEqual(AppIdentity.hotkeySignatureSeed, "PRH0")
        XCTAssertEqual(AppIdentity.settingsToolbarIdentifier, "MeetingAssistantSettingsToolbar")
        XCTAssertEqual(AppIdentity.settingsWindowAutosaveName, "MeetingAssistantSettingsWindow")
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
        XCTAssertEqual(Set(plist.keys), ["product", "technical", "persistence", "migration", "internal"])

        guard let migration = plist["migration"] as? [String: Any] else {
            return XCTFail("migration section missing")
        }
        XCTAssertEqual(migration["legacyAppSupportDirectories"] as? [String], ["Prisma", "MeetingAssistant"])
        XCTAssertEqual(migration["legacyLogDirectories"] as? [String], ["Prisma", "MeetingAssistant"])
        XCTAssertEqual(migration["legacyKeychainServices"] as? [String], ["com.mourato.prisma", "com.meeting-assistant"])
        XCTAssertEqual(migration["legacyUserDefaultsDomains"] as? [String], ["com.mourato.prisma", "com.meetingassistant.app"])
    }
}
