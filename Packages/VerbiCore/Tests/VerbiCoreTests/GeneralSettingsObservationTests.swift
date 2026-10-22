import Observation
@testable import VerbiCore
import XCTest

@MainActor
final class GeneralSettingsObservationTests: XCTestCase {
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

    func testAppearanceModeChangesNotifyObservationTracking() {
        let viewModel = GeneralSettingsViewModel(settingsStore: settings, deviceManager: GeneralSettingsAudioDeviceTestDouble())
        let expectation = XCTestExpectation(description: "appearance mode change observed")

        withObservationTracking {
            _ = viewModel.appearanceMode
        } onChange: {
            expectation.fulfill()
        }

        viewModel.appearanceMode = .dark

        wait(for: [expectation], timeout: 1)
    }
}
