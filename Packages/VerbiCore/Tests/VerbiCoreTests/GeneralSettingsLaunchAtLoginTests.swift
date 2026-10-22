@testable import VerbiCore
import XCTest

@MainActor
final class GeneralSettingsLaunchAtLoginTests: XCTestCase {
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

    func testRegisterFailureRollsBackAndExposesActionableError() {
        let service = MockLaunchAtLoginService(isEnabled: false)
        service.registerError = TestLaunchAtLoginError()
        let viewModel = GeneralSettingsViewModel(settingsStore: settings, launchAtLoginService: service, deviceManager: GeneralSettingsAudioDeviceTestDouble())

        viewModel.launchAtLogin = true

        XCTAssertFalse(viewModel.launchAtLogin)
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertEqual(viewModel.launchAtLoginError, .registrationFailed)
        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
    }

    func testUnregisterFailureRollsBackAndExposesActionableError() {
        settings.launchAtLogin = true
        let service = MockLaunchAtLoginService(isEnabled: true)
        service.unregisterError = TestLaunchAtLoginError()
        let viewModel = GeneralSettingsViewModel(settingsStore: settings, launchAtLoginService: service, deviceManager: GeneralSettingsAudioDeviceTestDouble())

        viewModel.launchAtLogin = false

        XCTAssertTrue(viewModel.launchAtLogin)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertEqual(viewModel.launchAtLoginError, .unregistrationFailed)
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(service.registerCallCount, 0)
    }

    func testRetryAfterRegisterFailureReappliesRequestedStateAndClearsError() {
        let service = MockLaunchAtLoginService(isEnabled: false)
        service.registerError = TestLaunchAtLoginError()
        let viewModel = GeneralSettingsViewModel(settingsStore: settings, launchAtLoginService: service, deviceManager: GeneralSettingsAudioDeviceTestDouble())

        viewModel.launchAtLogin = true
        service.registerError = nil
        viewModel.retryLaunchAtLogin()

        XCTAssertTrue(viewModel.launchAtLogin)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertNil(viewModel.launchAtLoginError)
        XCTAssertEqual(service.registerCallCount, 2)
    }

    func testSuccessfulRegistrationClearsPreviousError() {
        let service = MockLaunchAtLoginService(isEnabled: false)
        let viewModel = GeneralSettingsViewModel(settingsStore: settings, launchAtLoginService: service, deviceManager: GeneralSettingsAudioDeviceTestDouble())

        viewModel.launchAtLogin = true

        XCTAssertTrue(viewModel.launchAtLogin)
        XCTAssertTrue(settings.launchAtLogin)
        XCTAssertNil(viewModel.launchAtLoginError)
        XCTAssertEqual(service.registerCallCount, 1)
    }
}

@MainActor
private final class MockLaunchAtLoginService: LaunchAtLoginService {
    var isEnabled: Bool
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0

    init(isEnabled: Bool) {
        self.isEnabled = isEnabled
    }

    func register() throws {
        registerCallCount += 1
        if let registerError {
            throw registerError
        }
        isEnabled = true
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let unregisterError {
            throw unregisterError
        }
        isEnabled = false
    }
}

private struct TestLaunchAtLoginError: Error {}
