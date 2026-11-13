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
        XCTAssertTrue(manager.isRecording)
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
        try createRecordingAudioFiles()
        try await manager.setMergedAudioURL(XCTUnwrap(microphone.currentRecordingURL))
        loseSignal()
        await scheduler.advance(by: 15)
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

    func testUserStopDuringCountdownCancelsTimersAndDoesNotStopTwice() async {
        await startMeetingRecording()
        loseSignal()
        XCTAssertNotNil(manager.meetingEndPromptGraceTask)
        await scheduler.advance(by: 15)
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
        if mode != .off {
            resolver.detectedMeetingCandidate = context
            media.callOwners = ["us.zoom.xos"]
            manager.applyMeetingDetectionMode(mode)
        } else {
            manager.applyMeetingDetectionMode(mode)
        }
        let acquired = await RecordingExclusivityCoordinator.shared.beginRecording(mode: purpose.captureMode)
        XCTAssertTrue(acquired)
        manager.currentMeeting = CaptureSession(app: .zoom, capturePurpose: purpose, startTime: clock.now)
        manager.currentCapturePurpose = purpose
        manager.currentMeeting?.state = .recording
        manager.meetingState = .recording
        manager.isRecording = true
        manager.meetingEndPromptContext = context
        manager.meetingEndPromptStartedAt = clock.now
        MeetingDetectionToastController.shared.show(
            state: .recording(app: .zoom, appName: "Zoom", startedAt: clock.now)
        )
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

    private func createRecordingAudioFiles() throws {
        AppSettingsStore.shared.shouldMergeAudioFiles = false
        AppSettingsStore.shared.removeSilenceBeforeProcessing = false
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = buffer.frameCapacity
        for recorder in [microphone, systemAudio] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-end-\(UUID().uuidString).wav")
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: buffer)
            recorder?.currentRecordingURL = url
        }
        manager.currentMeeting?.audioFilePath = microphone.currentRecordingURL?.path
    }
}

@MainActor
private final class MeetingEndPromptTestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor
private final class MeetingEndPromptTestScheduler: MeetingEndPromptScheduling {
    private final class Entry: @unchecked Sendable {
        let deadline: Date
        let action: @MainActor () async -> Void
        private let lock = NSLock()
        private var cancelled = false

        init(deadline: Date, action: @escaping @MainActor () async -> Void) {
            self.deadline = deadline
            self.action = action
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    private let clock: MeetingEndPromptTestClock
    private var entries: [Entry] = []
    private(set) var firedCount = 0

    var pendingCount: Int {
        entries.filter { !$0.isCancelled }.count
    }

    init(clock: MeetingEndPromptTestClock) {
        self.clock = clock
    }

    func schedule(after interval: TimeInterval, action: @escaping @MainActor () async -> Void) -> AnyCancellable {
        let entry = Entry(deadline: clock.now.addingTimeInterval(interval), action: action)
        entries.append(entry)
        return AnyCancellable { entry.cancel() }
    }

    func advance(by interval: TimeInterval) async {
        clock.now = clock.now.addingTimeInterval(interval)
        while let index = entries.firstIndex(where: { !$0.isCancelled && $0.deadline <= clock.now }) {
            let entry = entries.remove(at: index)
            firedCount += 1
            await entry.action()
        }
        entries.removeAll(where: \.isCancelled)
    }
}

@MainActor
private final class MeetingEndPromptMediaProvider: MeetingMediaActivityProviding {
    var callOwners: [String] = []

    func currentActivity() -> MeetingMediaActivity {
        MeetingMediaActivity(
            microphoneInUseByAnotherApplication: !callOwners.isEmpty,
            signals: MeetingDetectionSignals(
                microphoneOwnerBundleIdentifier: callOwners.first,
                attribution: callOwners.isEmpty ? .unavailable : .resolved,
                activeCallBundleIdentifiers: callOwners
            )
        )
    }
}
