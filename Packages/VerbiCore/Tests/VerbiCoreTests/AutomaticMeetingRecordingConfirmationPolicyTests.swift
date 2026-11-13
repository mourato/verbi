@testable import VerbiCore
import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
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
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertFalse(manager.isRecording)
    }

    func testAutomaticStartDoesNotFireWhenSignalIsLostDuringCountdown() async throws {
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsStore.shared.automaticRecordingConfirmationDelay = .seconds3
        let resolver = MockCaptureContextResolver()
        let detector = MeetingDetector(captureContextResolver: resolver, runningApplications: { [] })
        let manager = RecordingManager(
            micRecorder: MockAudioRecorder(),
            systemRecorder: MockAudioRecorder(),
            transcriptionClient: MockTranscriptionClient(),
            postProcessingService: MockPostProcessingService(),
            meetingDetector: detector,
            storage: MockStorageService(),
            activeAppContextProvider: MockActiveAppContextProvider(),
            captureContextResolver: resolver
        )
        defer {
            manager.disableMeetingDetection()
            AppSettingsStore.shared.resetToDefaults()
            AppSettingsTestIsolationLock.release()
        }
        let context = ResolvedCaptureContext(
            purpose: .meeting,
            meetingApp: .zoom,
            appBundleIdentifier: "us.zoom.xos",
            isKnownMeetingCandidate: true
        )
        resolver.detectedMeetingCandidate = context
        manager.applyMeetingDetectionMode(.auto)
        await waitUntil(timeout: .seconds(1)) { manager.automaticMeetingRecordingConfirmation != nil }
        XCTAssertNotNil(manager.automaticMeetingRecordingConfirmation)

        // The signal disappears; the meeting stays shown during its grace period.
        resolver.detectedMeetingCandidate = nil
        detector.checkForMeetings()
        XCTAssertEqual(detector.detectedContext, context)
        XCTAssertFalse(detector.isMeetingSignalPresent)

        await waitUntil(timeout: .seconds(6)) { manager.automaticMeetingRecordingConfirmation == nil }
        XCTAssertNil(manager.automaticMeetingRecordingConfirmation)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertFalse(manager.isRecording)
    }
}
