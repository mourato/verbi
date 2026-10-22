@testable import VerbiCore
@testable import VerbiCoreInfrastructure
import XCTest

@MainActor
final class AppSettingsAudioDuckingTests: XCTestCase {
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

    func testAudioDuckingSettingsPersistInUserDefaults() {
        settings.recordingMediaHandlingMode = .duckAudio
        settings.audioDuckingLevelPercent = 22

        XCTAssertTrue(UserDefaults.standard.bool(forKey: "audioDuckingEnabled"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "recordingMediaHandlingMode"), "duckAudio")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "audioDuckingLevelPercent"), 22)
    }

    func testAudioDuckingLevelIsClampedInStore() {
        settings.audioDuckingLevelPercent = 120
        XCTAssertEqual(settings.audioDuckingLevelPercent, 100)

        settings.audioDuckingLevelPercent = -5
        XCTAssertEqual(settings.audioDuckingLevelPercent, 0)
    }

    func testLoadAudioAndLanguageSettingsMigratesLegacyMuteWhenNewKeysMissing() {
        UserDefaults.standard.removeObject(forKey: "audioDuckingEnabled")
        UserDefaults.standard.removeObject(forKey: "recordingMediaHandlingMode")
        UserDefaults.standard.removeObject(forKey: "audioDuckingLevelPercent")
        UserDefaults.standard.set(true, forKey: "muteOutputDuringRecording")

        let loaded = AppSettingsStore.loadAudioAndLanguageSettings()

        XCTAssertEqual(loaded.recordingMediaHandlingMode, .duckAudio)
        XCTAssertEqual(loaded.audioDuckingLevelPercent, 0)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "audioDuckingEnabled"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "recordingMediaHandlingMode"), "duckAudio")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "audioDuckingLevelPercent"), 0)
    }

    func testLoadAudioAndLanguageSettingsKeepsExplicitNewValues() {
        UserDefaults.standard.set(AppSettingsStore.RecordingMediaHandlingMode.pauseMedia.rawValue, forKey: "recordingMediaHandlingMode")
        UserDefaults.standard.set(true, forKey: "audioDuckingEnabled")
        UserDefaults.standard.set(44, forKey: "audioDuckingLevelPercent")
        UserDefaults.standard.set(true, forKey: "muteOutputDuringRecording")

        let loaded = AppSettingsStore.loadAudioAndLanguageSettings()

        XCTAssertEqual(loaded.recordingMediaHandlingMode, .pauseMedia)
        XCTAssertEqual(loaded.audioDuckingLevelPercent, 44)
    }

    func testLoadAudioAndLanguageSettingsUsesDefaultsWhenUnsetAndNoLegacyMute() {
        UserDefaults.standard.removeObject(forKey: "audioDuckingEnabled")
        UserDefaults.standard.removeObject(forKey: "recordingMediaHandlingMode")
        UserDefaults.standard.removeObject(forKey: "audioDuckingLevelPercent")
        UserDefaults.standard.set(false, forKey: "muteOutputDuringRecording")

        let loaded = AppSettingsStore.loadAudioAndLanguageSettings()

        XCTAssertEqual(loaded.recordingMediaHandlingMode, .none)
        XCTAssertEqual(loaded.audioDuckingLevelPercent, AppSettingsStore.defaultAudioDuckingLevelPercent)
    }

    func testLegacyAudioDuckingEnabledMigratesToDuckAudioMode() {
        UserDefaults.standard.removeObject(forKey: "recordingMediaHandlingMode")
        UserDefaults.standard.set(true, forKey: "audioDuckingEnabled")

        let loaded = AppSettingsStore.loadAudioAndLanguageSettings()

        XCTAssertEqual(loaded.recordingMediaHandlingMode, .duckAudio)
        XCTAssertEqual(UserDefaults.standard.string(forKey: "recordingMediaHandlingMode"), "duckAudio")
    }
}
