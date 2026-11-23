@testable import VerbiCore
import XCTest

@MainActor
class AppSettingsStoreTestCase: XCTestCase {
    var settings: AppSettingsStore!

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
}
