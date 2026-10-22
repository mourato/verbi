@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

@MainActor
final class RecordingIndicatorPPWarningTests: XCTestCase {
    func testMessageKey_ForMissingModel() {
        let descriptor = RecordingPostProcessingWarningDescriptor(
            issue: .missingModel,
            mode: .meeting,
        )

        XCTAssertEqual(descriptor.messageKey, "recording_indicator.post_processing_warning.missing_model")
        XCTAssertEqual(descriptor.settingsSection, SettingsSection.intelligence.rawValue)
    }

    func testMessageKey_ForMissingAPIKey() {
        let descriptor = RecordingPostProcessingWarningDescriptor(
            issue: .missingAPIKey,
            mode: .dictation,
        )

        XCTAssertEqual(descriptor.messageKey, "recording_indicator.post_processing_warning.missing_api_key")
    }

    func testMessageKey_ForInvalidBaseURL() {
        let descriptor = RecordingPostProcessingWarningDescriptor(
            issue: .invalidBaseURL,
            mode: .assistant,
        )

        XCTAssertEqual(descriptor.messageKey, "recording_indicator.post_processing_warning.invalid_base_url")
    }

    func testOpenSettings_UsesIntelligenceSection() {
        let descriptor = RecordingPostProcessingWarningDescriptor(
            issue: .missingModel,
            mode: .meeting,
        )
        var capturedSection: String?

        descriptor.openSettings { section in
            capturedSection = section
        }

        XCTAssertEqual(capturedSection, SettingsSection.intelligence.rawValue)
    }
}
