@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

@MainActor
final class OnboardingMeetingRecordingTests: XCTestCase {
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

    func testStepOrderIncludesMeetingRecordingBeforeCompletion() {
        XCTAssertEqual(
            OnboardingStep.allCases,
            [.welcome, .permissions, .shortcuts, .downloadModels, .meetingRecording, .completion],
        )
    }

    func testMeetingRecordingStepIsSkippable() {
        XCTAssertTrue(OnboardingStep.meetingRecording.isSkippable)
    }

    func testEnableMeetingRecordingTogglesCapability() {
        let viewModel = OnboardingViewModel()

        XCTAssertFalse(settings.isMeetingTranscriptionEnabled)

        viewModel.enableMeetingRecording()

        XCTAssertTrue(settings.isMeetingTranscriptionEnabled)
    }

    func testCompletionSubtitleUsesMeetingReadyCopyWhenEnabledAndPrerequisitesSatisfied() {
        let readiness = OnboardingMeetingRecordingReadiness(
            microphoneGranted: true,
            screenRecordingGranted: true,
            transcriptionModelReady: true,
            isMeetingRecordingEnabled: true,
            wasSkipped: false,
        )

        XCTAssertEqual(
            readiness.completionSubtitleKey,
            "onboarding.completion.subtitle.meetings_ready",
        )
    }

    func testCompletionSubtitleUsesDictationReadyCopyWhenMeetingRecordingWasSkipped() {
        let readiness = OnboardingMeetingRecordingReadiness(
            microphoneGranted: true,
            screenRecordingGranted: true,
            transcriptionModelReady: true,
            isMeetingRecordingEnabled: true,
            wasSkipped: true,
        )

        XCTAssertEqual(
            readiness.completionSubtitleKey,
            "onboarding.completion.subtitle.dictation_ready",
        )
    }

    func testCompletionSubtitleUsesDictationReadyCopyWhenPrerequisitesAreMissing() {
        let readiness = OnboardingMeetingRecordingReadiness(
            microphoneGranted: true,
            screenRecordingGranted: false,
            transcriptionModelReady: true,
            isMeetingRecordingEnabled: true,
            wasSkipped: false,
        )

        XCTAssertEqual(
            readiness.completionSubtitleKey,
            "onboarding.completion.subtitle.dictation_ready",
        )
    }
}
