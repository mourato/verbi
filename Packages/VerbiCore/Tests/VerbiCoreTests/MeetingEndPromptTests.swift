import AppKit
import AVFoundation
import Combine
import Foundation
@testable import VerbiCore
@testable import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class MeetingEndPromptTests: XCTestCase {
    private let clock = MeetingEndPromptTestClock()
    private var scheduler: MeetingEndPromptTestScheduler!
    private let resolver = MockCaptureContextResolver()
    private let media = MeetingEndPromptMediaProvider()
    private let context = ResolvedCaptureContext(
        purpose: .meeting,
        meetingApp: .zoom,
        appBundleIdentifier: "us.zoom.xos",
        appDisplayName: "Zoom",
        isKnownMeetingCandidate: true
    )
    private var manager: RecordingManager!
    private var microphone: MockAudioRecorder!
    private var systemAudio: MockAudioRecorder!
    private var transcription: MockTranscriptionClient!
    private var storage: MockStorageService!

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsStore.shared.isMeetingTranscriptionEnabled = true
        scheduler = MeetingEndPromptTestScheduler(clock: clock)
        let detector = MeetingDetector(
            captureContextResolver: resolver,
            mediaActivityProvider: media,
            detectionLossGracePeriod: 30,
            now: { [clock] in clock.now },
            runningApplications: { [] }
        )
        microphone = MockAudioRecorder()
        systemAudio = MockAudioRecorder()
        transcription = MockTranscriptionClient()
        storage = MockStorageService()
        storage.recordingsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting-end-prompt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storage.recordingsDirectory, withIntermediateDirectories: true)
        AppSettingsStore.shared.shouldMergeAudioFiles = false
        AppSettingsStore.shared.removeSilenceBeforeProcessing = false
        manager = RecordingManager(
            micRecorder: microphone,
            systemRecorder: systemAudio,
            transcriptionClient: transcription,
            postProcessingService: MockPostProcessingService(),
            meetingDetector: detector,
            meetingEndPromptScheduler: scheduler,
            now: { [clock] in clock.now },
            storage: storage,
            activeAppContextProvider: MockActiveAppContextProvider(),
            captureContextResolver: resolver
        )
    }

    override func tearDown() async throws {
        manager.disableMeetingDetection()
        await manager.reset()
        manager = nil
        await RecordingExclusivityCoordinator.shared.endRecording()
        AppSettingsStore.shared.resetToDefaults()
        if let recordingsDirectory = storage?.recordingsDirectory {
            try? FileManager.default.removeItem(at: recordingsDirectory)
        }
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testSignalLostFor15SecondsWhileRecordingShowsPrompt() async {
        await startMeetingRecording()
        XCTAssertTrue(manager.isMeetingEndPromptEligible)
        loseSignal()
        XCTAssertNotNil(manager.meetingEndPromptGraceTask)
        XCTAssertEqual(scheduler.pendingCount, 1)

        await scheduler.advance(by: 14)
        XCTAssertFalse(isPromptVisible)
        await scheduler.advance(by: 1)

        XCTAssertEqual(scheduler.firedCount, 1)
        XCTAssertTrue(
            manager.isRecording,
            "Recording unexpectedly ended: meeting=\(String(describing: manager.currentMeeting?.state)), prompt=\(String(describing: manager.meetingEndPromptDeadline)), micStops=\(microphone.stopRecordingCalledCount)"
        )
        XCTAssertEqual(manager.currentMeeting?.capturePurpose, .meeting)
        XCTAssertNotEqual(AppSettingsStore.shared.meetingDetectionMode, .off)
        XCTAssertTrue(AppSettingsStore.shared.isMeetingTranscriptionEnabled)
        XCTAssertTrue(manager.isMeetingEndPromptEligible)
        XCTAssertTrue(isPromptVisible)
        XCTAssertEqual(manager.meetingEndPromptDeadline, clock.now.addingTimeInterval(30))
    }

    func testSignalReturnsBefore15SecondsDoesNotShowPrompt() async {
        await startMeetingRecording()
        loseSignal()
        XCTAssertNotNil(manager.meetingEndPromptGraceTask)
        await scheduler.advance(by: 14)
        returnSignal()
        await scheduler.advance(by: 15)

        XCTAssertFalse(isPromptVisible)
        XCTAssertNil(manager.meetingEndPromptDeadline)
    }

    func testSignalLostBeforeRecordingMustReturnOnceBeforePromptCanArm() async {
        resolver.detectedMeetingCandidate = context
        resolver.resolvedContext = context
        media.callOwners = ["us.zoom.xos"]
        manager.applyMeetingDetectionMode(.notify)
        XCTAssertTrue(manager.meetingDetector.isMeetingSignalPresent, "The test must begin from a live meeting signal.")
        loseSignal()
        await manager.startCapture(
            purpose: .meeting,
            source: .all,
            requestedAt: clock.now,
            triggerLabel: "test.meeting_end_prompt_grace_start"
        )
        XCTAssertFalse(manager.meetingDetector.isMeetingSignalPresent)
        XCTAssertFalse(manager.meetingEndPromptSignalWasPresent)

        await scheduler.advance(by: 60)
        XCTAssertFalse(isPromptVisible)
        XCTAssertFalse(manager.meetingEndPromptSignalWasPresent)

        returnSignal()
        loseSignal()
        await scheduler.advance(by: 15)

        XCTAssertTrue(isPromptVisible)
    }

    func testSignalReturnsDuringCountdownCancelsPromptAndRestoresRecordingToast() async {
        await startMeetingRecording()
        loseSignal()
        XCTAssertNotNil(manager.meetingEndPromptGraceTask)
        await scheduler.advance(by: 15)
        XCTAssertTrue(isPromptVisible)

        returnSignal()

        XCTAssertFalse(isPromptVisible)
        XCTAssertTrue(manager.isRecording)
        guard case .recording = MeetingDetectionToastController.shared.currentState else {
            return XCTFail("Signal return must restore the recording toast")
        }
    }

    func testCountdownEndStopsOnceAndTranscribes() async throws {
        await startMeetingRecording()
        try await createRecordingAudioFiles()
        loseSignal()
        XCTAssertEqual(
            scheduler.pendingCount,
            1,
            "Signal loss should schedule grace; eligible=\(manager.isMeetingEndPromptEligible), recording=\(manager.isRecording), purpose=\(String(describing: manager.currentMeeting?.capturePurpose)), mode=\(AppSettingsStore.shared.meetingDetectionMode), transcription=\(AppSettingsStore.shared.isMeetingTranscriptionEnabled), session=\(String(describing: manager.meetingEndPromptSessionID))/\(String(describing: manager.currentMeeting?.id)), context=\(String(describing: manager.meetingEndPromptContext)), signalWasPresent=\(manager.meetingEndPromptSignalWasPresent)"
        )
        await scheduler.advance(by: 15)
        XCTAssertTrue(isPromptVisible, "The grace callback should present the prompt before countdown time advances.")
        await scheduler.advance(by: 30)
        XCTAssertEqual(scheduler.firedCount, 2, "The grace and countdown callbacks should both fire")
        XCTAssertFalse(manager.meetingDetector.isMeetingSignalPresent, "The meeting signal should remain lost")
        XCTAssertNil(manager.meetingEndPromptDeadline, "The countdown callback should clear its deadline")
        await waitUntil(timeout: .seconds(2)) {
            transcription.fileTranscribeCallCount == 1 && !manager.isRecording
        }

        XCTAssertEqual(microphone.stopRecordingCalledCount, 1)
        XCTAssertEqual(systemAudio.stopRecordingCalledCount, 1)
        XCTAssertEqual(transcription.fileTranscribeCallCount, 1)
        XCTAssertFalse(manager.isRecording)
        XCTAssertTrue(scheduler.lastFiredActionWasCancelled, "The scheduler task should be cancelled while stop runs in its unstructured task.")
    }

    func testKeepRecordingDoesNotPromptAgainUntilSignalReturnsAndIsLostAgain() async {
        await startMeetingRecording()
        loseSignal()
        XCTAssertNotNil(manager.meetingEndPromptGraceTask)
        await scheduler.advance(by: 15)
        MeetingDetectionToastController.shared.onKeepRecording?()
        XCTAssertFalse(isPromptVisible)

        await scheduler.advance(by: 60)
        XCTAssertFalse(isPromptVisible)
        returnSignal()
        loseSignal()
        await scheduler.advance(by: 15)

        XCTAssertTrue(isPromptVisible)
    }

    func testUserStopDuringCountdownCancelsTimersAndDoesNotStopTwice() async throws {
        await startMeetingRecording()
        loseSignal()
        XCTAssertNotNil(manager.meetingEndPromptGraceTask)
        await scheduler.advance(by: 15)
        try await createRecordingAudioFiles()
        await manager.stopRecording(transcribe: false)
        await scheduler.advance(by: 30)

        XCTAssertEqual(microphone.stopRecordingCalledCount, 1)
        XCTAssertEqual(systemAudio.stopRecordingCalledCount, 1)
        XCTAssertFalse(manager.isRecording)
    }

    func testDetectionOffNeverPrompts() async {
        await startMeetingRecording(mode: .off)
        loseSignal()
        await scheduler.advance(by: 60)

        XCTAssertFalse(isPromptVisible)
    }

    func testDictationCaptureNeverPrompts() async {
        await startCapture(purpose: .dictation)
        loseSignal()
        await scheduler.advance(by: 60)

        XCTAssertFalse(isPromptVisible)
    }

    func testRecorderFailureResetsPromptStateAndSuppressionForNextSession() async {
        await startMeetingRecording()
        loseSignal()
        await scheduler.advance(by: 15)
        MeetingDetectionToastController.shared.onKeepRecording?()
        XCTAssertTrue(manager.meetingEndPromptIgnoredForLoss)

        await manager.lifecycleCoordinator.recorderStateDidChange(
            .init(recorderIsRecording: false, isRecording: true, isStarting: false, isStartOperationInFlight: false),
            operations: manager.lifecycleOperations
        )

        XCTAssertFalse(manager.isRecording)
        XCTAssertNil(manager.currentMeeting)
        assertMeetingEndPromptStateIsReset()

        returnSignal()
        await startMeetingRecording()
        loseSignal()
        await scheduler.advance(by: 15)

        XCTAssertTrue(manager.isRecording)
        XCTAssertTrue(isPromptVisible, "A new session must not inherit Keep recording suppression.")
    }

    func testStaleCountdownCannotStopNextSessionAfterCommit() async {
        await startMeetingRecording()
        loseSignal()
        await scheduler.advance(by: 15)
        let oldStopEntryIndex = scheduler.entryCount - 1
        let oldSessionID = manager.currentMeeting?.id

        await manager.cancelRecording()
        returnSignal()
        await startMeetingRecording()
        XCTAssertNotEqual(manager.currentMeeting?.id, oldSessionID)
        loseSignal()
        let newGraceEntryIndex = scheduler.entryCount - 1
        await scheduler.runAction(at: newGraceEntryIndex)
        XCTAssertTrue(isPromptVisible)

        await scheduler.runActionIgnoringCancellation(at: oldStopEntryIndex)

        XCTAssertTrue(manager.isRecording, "The previous session's countdown must not stop the new session.")
        XCTAssertEqual(microphone.stopRecordingCalledCount, 1, "Only cancellation of the previous session should stop the recorder.")
    }

    func testReturnAndEscapeInvokeStopAndKeepRecordingActions() throws {
        let toast = MeetingDetectionToastController.shared
        var stopCount = 0
        var keepCount = 0
        toast.show(
            state: .endPrompt(app: .zoom, appName: "Zoom", startedAt: clock.now, deadline: clock.now.addingTimeInterval(30)),
            onStop: { stopCount += 1 },
            onKeepRecording: { keepCount += 1 }
        )
        let panel = try XCTUnwrap(toast.panel)

        let returnEvent = try keyEvent(keyCode: 36, characters: "\r")
        panel.keyDown(with: returnEvent)
        XCTAssertEqual(stopCount, 1)

        let escapeEvent = try keyEvent(keyCode: 53, characters: "\u{1b}")
        panel.keyDown(with: escapeEvent)
        XCTAssertEqual(keepCount, 1)
        toast.update(state: .recording(app: .zoom, appName: "Zoom", startedAt: clock.now))
        XCTAssertFalse(panel.isKeyWindow, "Leaving the prompt must release key focus.")
        toast.hide()
    }

    func testStopNowRacingCountdownStopsAndTranscribesOnce() async throws {
        await startMeetingRecording()
        try await createRecordingAudioFiles()
        loseSignal()
        await scheduler.advance(by: 15)
        let oldStopEntryIndex = scheduler.entryCount - 1
        let stopNow = try XCTUnwrap(MeetingDetectionToastController.shared.onStop)

        let userStopTask = Task { @MainActor in stopNow() }
        let countdownTask = Task { @MainActor in await scheduler.runActionIgnoringCancellation(at: oldStopEntryIndex) }
        await userStopTask.value
        await countdownTask.value
        await waitUntil(timeout: .seconds(2)) {
            transcription.fileTranscribeCallCount == 1 && !manager.isRecording
        }

        XCTAssertEqual(microphone.stopRecordingCalledCount, 1)
        XCTAssertEqual(systemAudio.stopRecordingCalledCount, 1)
        XCTAssertEqual(transcription.fileTranscribeCallCount, 1)
    }

    private var isPromptVisible: Bool {
        if case .endPrompt = MeetingDetectionToastController.shared.currentState {
            return true
        }
        return false
    }

    private func startMeetingRecording(mode: MeetingDetectionMode = .notify) async {
        await startCapture(mode: mode, purpose: .meeting)
    }

    private func startCapture(mode: MeetingDetectionMode = .notify, purpose: CapturePurpose) async {
        AppSettingsStore.shared.meetingDetectionMode = mode
        resolver.resolvedContext = context
        if mode != .off {
            resolver.detectedMeetingCandidate = context
            media.callOwners = ["us.zoom.xos"]
            manager.applyMeetingDetectionMode(mode)
        } else {
            manager.applyMeetingDetectionMode(mode)
        }
        if mode != .off {
            XCTAssertTrue(manager.meetingDetector.isMeetingSignalPresent, "The fixture must present a live signal before recording starts.")
        }
        await manager.startCapture(
            purpose: purpose,
            source: purpose == .meeting ? .all : .microphone,
            requestedAt: clock.now,
            triggerLabel: "test.meeting_end_prompt"
        )
        XCTAssertTrue(manager.isRecording)
        if purpose == .meeting, mode != .off {
            XCTAssertTrue(manager.meetingEndPromptSignalWasPresent, "The session must remember its initial live signal.")
        }
    }

    private func loseSignal() {
        resolver.detectedMeetingCandidate = nil
        media.callOwners = []
        manager.meetingDetector.checkForMeetings()
        XCTAssertFalse(manager.meetingDetector.isMeetingSignalPresent)
    }

    private func returnSignal() {
        resolver.detectedMeetingCandidate = context
        media.callOwners = ["us.zoom.xos"]
        manager.meetingDetector.checkForMeetings()
    }

    private func createRecordingAudioFiles() async throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = buffer.frameCapacity
        let url = try XCTUnwrap(microphone.currentRecordingURL)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        manager.currentMeeting?.audioFilePath = url.path
        await manager.setMergedAudioURL(url)
    }

    private func assertMeetingEndPromptStateIsReset(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(manager.meetingEndPromptGraceTask, file: file, line: line)
        XCTAssertNil(manager.meetingEndPromptStopTask, file: file, line: line)
        XCTAssertNil(manager.meetingEndPromptDeadline, file: file, line: line)
        XCTAssertFalse(manager.meetingEndPromptIgnoredForLoss, file: file, line: line)
        XCTAssertNil(manager.meetingEndPromptContext, file: file, line: line)
        XCTAssertNil(manager.meetingEndPromptStartedAt, file: file, line: line)
        XCTAssertNil(manager.meetingEndPromptSessionID, file: file, line: line)
        XCTAssertFalse(manager.meetingEndPromptSignalWasPresent, file: file, line: line)
    }

    private func keyEvent(keyCode: UInt16, characters: String) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: MeetingDetectionToastController.shared.panel?.windowNumber ?? 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}
