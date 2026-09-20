@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class GeneralSettingsAppearanceTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        try AppSettingsTestIsolationLock.acquire()
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
        AppSettingsTestIsolationLock.release()
    }

    func testAppearanceModeIsPersistedThroughViewModel() {
        let firstViewModel = GeneralSettingsViewModel(settingsStore: settings, deviceManager: GeneralSettingsAudioDeviceTestDouble())
        firstViewModel.appearanceMode = .dark

        let reloadedViewModel = GeneralSettingsViewModel(settingsStore: settings, deviceManager: GeneralSettingsAudioDeviceTestDouble())

        XCTAssertEqual(settings.appearanceMode, .dark)
        XCTAssertEqual(reloadedViewModel.appearanceMode, .dark)
    }

    func testMenuBarVisibilityDefaultsToTrueWhenUnset() {
        UserDefaults.standard.removeObject(forKey: AppSettingsStore.Keys.showInMenuBar)

        XCTAssertTrue(AppSettingsStore.loadUIAndIndicatorSettings().showInMenuBar)
    }

    func testMenuBarVisibilityIsPersistedThroughViewModel() {
        let firstViewModel = GeneralSettingsViewModel(settingsStore: settings, deviceManager: GeneralSettingsAudioDeviceTestDouble())
        firstViewModel.showInMenuBar = false

        let reloadedViewModel = GeneralSettingsViewModel(settingsStore: settings, deviceManager: GeneralSettingsAudioDeviceTestDouble())

        XCTAssertFalse(settings.showInMenuBar)
        XCTAssertFalse(reloadedViewModel.showInMenuBar)
    }
}
