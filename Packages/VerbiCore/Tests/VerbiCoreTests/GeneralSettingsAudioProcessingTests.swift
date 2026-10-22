@testable import VerbiCore
import XCTest

@MainActor
final class GeneralSettingsAudioProcessingTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testSilenceRemovalSettingIsPersistedThroughViewModelReload() {
        let firstViewModel = GeneralSettingsViewModel(settingsStore: settings, deviceManager: GeneralSettingsAudioDeviceTestDouble())
        firstViewModel.removeSilenceBeforeProcessing = true

        let reloadedViewModel = GeneralSettingsViewModel(settingsStore: settings, deviceManager: GeneralSettingsAudioDeviceTestDouble())

        XCTAssertTrue(settings.removeSilenceBeforeProcessing)
        XCTAssertTrue(reloadedViewModel.removeSilenceBeforeProcessing)
    }

    func testAudioDuckingSettingsArePersistedThroughViewModelReload() {
        let firstViewModel = GeneralSettingsViewModel(settingsStore: settings, deviceManager: GeneralSettingsAudioDeviceTestDouble())
        firstViewModel.recordingMediaHandlingMode = .pauseMedia
        firstViewModel.audioDuckingLevelPercent = 28

        let reloadedViewModel = GeneralSettingsViewModel(settingsStore: settings, deviceManager: GeneralSettingsAudioDeviceTestDouble())

        XCTAssertEqual(settings.recordingMediaHandlingMode, .pauseMedia)
        XCTAssertEqual(settings.audioDuckingLevelPercent, 28)
        XCTAssertEqual(reloadedViewModel.recordingMediaHandlingMode, .pauseMedia)
        XCTAssertEqual(reloadedViewModel.audioDuckingLevelPercent, 28)
    }
}
