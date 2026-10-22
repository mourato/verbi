@testable import VerbiCoreInfrastructure
import XCTest

@MainActor
final class AppSettingsStoreCapabilityTests: XCTestCase {
    override func tearDown() async throws {
        removeCapabilityDefaults()
        AppSettingsStore.shared.resetToDefaults()
    }

    func testAssistantCapabilityDefaultsOffForNewInstalls() {
        removeCapabilityDefaults()

        let capabilities = AppSettingsStore.loadCapabilitySettings()

        XCTAssertFalse(capabilities.isAssistantEnabled)
    }

    func testAssistantCapabilityDefaultsOnForExistingInstalls() {
        removeCapabilityDefaults()
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        let capabilities = AppSettingsStore.loadCapabilitySettings()

        XCTAssertTrue(capabilities.isAssistantEnabled)
    }

    func testAssistantCapabilityExplicitValuePersists() {
        let settings = AppSettingsStore.shared

        settings.isAssistantEnabled = true
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "isAssistantEnabled"))

        settings.isAssistantEnabled = false
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "isAssistantEnabled"))
    }

    private func removeCapabilityDefaults() {
        [
            "isMeetingTranscriptionEnabled",
            "isAssistantEnabled",
            "isAssistantIntegrationsEnabled",
            "hasCompletedOnboarding",
            "aiConfiguration",
            "assistantIntegrations",
            "dictationSelectedPresetKey",
            "meetingSelectedPresetKey",
        ].forEach(UserDefaults.standard.removeObject)
    }
}
