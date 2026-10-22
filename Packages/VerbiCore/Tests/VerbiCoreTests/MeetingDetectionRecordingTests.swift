import Foundation
@testable import VerbiCore
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class MeetingDetectionRecordingTests: XCTestCase {
    private var manager: RecordingManager?
    private var resolver: MockCaptureContextResolver?

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsStore.shared.isMeetingTranscriptionEnabled = true
        let resolver = MockCaptureContextResolver()
        self.resolver = resolver
        manager = RecordingManager(
            micRecorder: MockAudioRecorder(),
            systemRecorder: MockAudioRecorder(),
            transcriptionClient: MockTranscriptionClient(),
            postProcessingService: MockPostProcessingService(),
            meetingDetector: MeetingDetector(captureContextResolver: resolver),
            storage: MockStorageService(),
            activeAppContextProvider: MockActiveAppContextProvider(),
            captureContextResolver: resolver
        )
    }

    override func tearDown() async throws {
        manager?.disableMeetingDetection()
        await manager?.reset()
        manager = nil
        resolver = nil
        await RecordingExclusivityCoordinator.shared.endRecording()
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testNotifyAtLaunchMonitorsAndHandlesAlreadyActiveCandidateWithoutAutoRecording() async throws {
        let manager = try XCTUnwrap(manager)
        let resolver = try XCTUnwrap(resolver)
        let context = ResolvedCaptureContext(
            purpose: .meeting,
            meetingApp: .zoom,
            appBundleIdentifier: "us.zoom.xos",
            appDisplayName: "Zoom",
            isKnownMeetingCandidate: true
        )
        resolver.detectedMeetingCandidate = context
        manager.meetingDetector.startMonitoring()
        XCTAssertEqual(manager.meetingDetector.detectedContext, context)
        AppSettingsStore.shared.autoStartRecording = true

        manager.applyMeetingDetectionMode(.notify)
        await waitUntil(timeout: .seconds(1)) {
            MeetingDetectionToastController.shared.currentState == .detected(app: .zoom, appName: "Zoom", context: context)
        }

        XCTAssertNotNil(manager.automaticMeetingRecordingCancellable)
        XCTAssertEqual(MeetingDetectionToastController.shared.currentState, .detected(app: .zoom, appName: "Zoom", context: context))
        XCTAssertNil(manager.automaticMeetingRecordingConfirmation)
        XCTAssertFalse(manager.isStartingRecording)
        XCTAssertFalse(manager.isRecording)
        manager.meetingDetector.stopMonitoring()
        await waitUntil(timeout: .seconds(1)) { !MeetingDetectionToastController.shared.isVisible }
        XCTAssertNil(MeetingDetectionToastController.shared.currentState)
    }

    func testTurningDetectionOffDiscardsAlreadyQueuedCandidate() async throws {
        let manager = try XCTUnwrap(manager)
        let resolver = try XCTUnwrap(resolver)
        resolver.detectedMeetingCandidate = ResolvedCaptureContext(purpose: .meeting, meetingApp: .zoom)
        manager.applyMeetingDetectionMode(.auto)
        manager.applyMeetingDetectionMode(.off)
        await Task.yield()

        XCTAssertNil(manager.automaticMeetingRecordingCancellable)
        XCTAssertNil(manager.automaticMeetingRecordingConfirmation)
        XCTAssertNil(MeetingDetectionToastController.shared.currentState)
    }

    func testRecordActionShowsRecordingStateAfterDetectedToastIsHidden() async throws {
        try await assertDetectionStartShowsRecording(mode: .notify, withoutSummary: false)
    }

    func testRecordWithoutSummaryShowsRecordingStateAfterDetectedToastIsHidden() async throws {
        try await assertDetectionStartShowsRecording(mode: .notify, withoutSummary: true)
    }

    func testAutomaticStartShowsRecordingStateOnlyAfterStartCommits() async throws {
        try await assertDetectionStartShowsRecording(mode: .auto, withoutSummary: false)
    }

    private func assertDetectionStartShowsRecording(mode: MeetingDetectionMode, withoutSummary: Bool) async throws {
        let manager = try XCTUnwrap(manager)
        let resolver = try XCTUnwrap(resolver)
        let context = ResolvedCaptureContext(
            purpose: .meeting,
            meetingApp: .zoom,
            appBundleIdentifier: "us.zoom.xos",
            appDisplayName: "Zoom",
            isKnownMeetingCandidate: true
        )
        let previousPromptID = AppSettingsStore.shared.selectedPromptId
        resolver.detectedMeetingCandidate = context
        resolver.resolvedContext = context
        manager.applyMeetingDetectionMode(mode)
        let toast = MeetingDetectionToastController.shared
        await waitUntil(timeout: .seconds(1)) {
            toast.currentState == .detected(app: .zoom, appName: "Zoom", context: context)
        }
        if mode == .notify {
            let action = try XCTUnwrap(withoutSummary ? toast.onRecordWithoutSummary : toast.onRecord)
            action()
            XCTAssertFalse(toast.isVisible)
        }
        await waitUntil(timeout: .seconds(5)) { manager.isRecording }

        XCTAssertTrue(manager.isRecording)
        guard case let .recording(app, appName, _) = toast.currentState else {
            XCTFail("Successful detection start must present recording state")
            return
        }
        XCTAssertEqual(app, .zoom)
        XCTAssertEqual(appName, "Zoom")
        XCTAssertNotNil(toast.onStop)
        XCTAssertNil(toast.onRecord)
        XCTAssertNil(toast.onRecordWithoutSummary)
        XCTAssertNil(toast.onDismiss)
        // A pending confirmation provides an observable acknowledgement that the
        // detection-loss observer has run, without waiting for a grace timer.
        manager.scheduleAutomaticMeetingRecordingConfirmation(for: context)
        manager.meetingDetector.stopMonitoring()
        await waitUntil(timeout: .seconds(1)) { manager.automaticMeetingRecordingConfirmation == nil }
        XCTAssertNil(manager.automaticMeetingRecordingConfirmation)
        XCTAssertNil(manager.automaticMeetingRecordingStopTask, "Detection loss must never queue a recording stop")
        XCTAssertTrue(manager.isRecording)
        if case .recording = toast.currentState {} else {
            XCTFail("Losing the candidate must preserve the recording toast")
        }
        if withoutSummary {
            XCTAssertEqual(AppSettingsStore.shared.selectedPromptId, previousPromptID)
            let meeting = try XCTUnwrap(manager.currentMeeting)
            let session = manager.makeTranscriptionSessionSnapshot(meeting)
            XCTAssertTrue(session.skipPostProcessing)
            XCTAssertEqual(session.useCaseConfig?.applyPostProcessing, false)
        }
        manager.applyMeetingDetectionMode(.off)
        XCTAssertTrue(manager.isRecording, "Disabling detection must preserve an active recording")
        await manager.stopRecording(transcribe: false)
        XCTAssertFalse(manager.isRecording, "Manual stop must remain available after detection loss")
    }
}
