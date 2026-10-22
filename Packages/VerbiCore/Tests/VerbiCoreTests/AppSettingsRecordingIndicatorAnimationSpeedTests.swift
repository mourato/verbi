@testable import VerbiCore
import XCTest

@MainActor
final class RecordingIndicatorAnimationSpeedTests: XCTestCase {
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

    func testRecordingIndicatorAnimationSpeed_DefaultIsNormalAfterReset() {
        settings.recordingIndicatorAnimationSpeed = .fast

        settings.resetToDefaults()

        XCTAssertEqual(settings.recordingIndicatorAnimationSpeed, .normal)
    }

    func testRecordingIndicatorAnimationSpeed_PersistsRawValueInUserDefaults() {
        settings.recordingIndicatorAnimationSpeed = .slow
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "recordingIndicatorAnimationSpeed"),
            RecordingIndicatorAnimationSpeed.slow.rawValue,
        )

        settings.recordingIndicatorAnimationSpeed = .fast
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: "recordingIndicatorAnimationSpeed"),
            RecordingIndicatorAnimationSpeed.fast.rawValue,
        )
    }

    func testRecordingIndicatorAnimationSpeed_ResetToDefaultsRestoresNormal() {
        settings.recordingIndicatorAnimationSpeed = .slow

        settings.resetToDefaults()

        XCTAssertEqual(settings.recordingIndicatorAnimationSpeed, .normal)
    }
}
