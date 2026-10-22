@testable import VerbiCore
import VerbiCoreDomain
import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class AutoMeetingConfirmationPolicyTests: XCTestCase {
    func testIdleMeetingStartEligibilityRequiresNoActiveRecording() {
        XCTAssertTrue(
            isIdleForAutomaticMeetingStart(
                currentCapturePurpose: nil,
                isRecording: false,
                isStartingRecording: false
            )
        )

        XCTAssertFalse(
            isIdleForAutomaticMeetingStart(
                currentCapturePurpose: .meeting,
                isRecording: true,
                isStartingRecording: false
            )
        )

        XCTAssertFalse(
            isIdleForAutomaticMeetingStart(
                currentCapturePurpose: .meeting,
                isRecording: false,
                isStartingRecording: true
            )
        )

        XCTAssertFalse(
            isIdleForAutomaticMeetingStart(
                currentCapturePurpose: .dictation,
                isRecording: false,
                isStartingRecording: false
            )
        )
    }

    func testLostDetectionCancelsPendingStartWithoutSchedulingStop() async throws {
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
        let resolver = MockCaptureContextResolver()
        let manager = RecordingManager(
            micRecorder: MockAudioRecorder(),
            systemRecorder: MockAudioRecorder(),
            transcriptionClient: MockTranscriptionClient(),
            postProcessingService: MockPostProcessingService(),
            meetingDetector: MeetingDetector(captureContextResolver: resolver),
            storage: MockStorageService(),
            activeAppContextProvider: MockActiveAppContextProvider(),
            captureContextResolver: resolver
        )
        defer {
            manager.disableMeetingDetection()
            AppSettingsStore.shared.resetToDefaults()
            AppSettingsTestIsolationLock.release()
        }
        let context = ResolvedCaptureContext(purpose: .meeting, meetingApp: .googleMeet)
        resolver.detectedMeetingCandidate = context
        manager.applyMeetingDetectionMode(.notify)
        // Drain the candidate event before publishing detection loss.
        await Task.yield()
        manager.scheduleAutomaticMeetingRecordingConfirmation(for: context)
        manager.meetingDetector.stopMonitoring()
        await waitUntil { manager.automaticMeetingRecordingConfirmation == nil }

        XCTAssertNil(manager.automaticMeetingRecordingConfirmation)
        XCTAssertNil(manager.automaticMeetingRecordingConfirmationTask)
        XCTAssertNil(manager.automaticMeetingRecordingStopTask)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertFalse(manager.isRecording)
    }
}
