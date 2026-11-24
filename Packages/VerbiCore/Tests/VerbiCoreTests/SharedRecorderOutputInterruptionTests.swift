import Foundation
@testable import VerbiCoreAudio
@testable import VerbiCoreInfrastructure
import VerbiCoreDomain
import XCTest

@MainActor
final class SharedRecorderOutputInterruptionTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsStore.shared.autoIncreaseMicrophoneVolume = false
    }

    override func tearDown() async throws {
        AppSettingsStore.shared.resetToDefaults()
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testPauseMediaIsPreparedAndRestoredForDictationRecorder() throws {
        AppSettingsStore.shared.recordingMediaHandlingMode = .pauseMedia
        let session = MediaPlaybackResumeSession(target: .music)
        let media = FakeMediaPlaybackController(outcome: .paused(session))
        let mute = FakeOutputDuckingController()
        let recorder = DictationRecorder(muteController: mute, mediaPlaybackController: media)
        recorder.microphonePermissionValidator = {}

        try recorder.prepareRecordingAttempt(
            outputURL: URL(fileURLWithPath: "/tmp/output-interruption.m4a"),
            source: .microphone
        )

        XCTAssertEqual(recorder.pausedMediaSession, session)

        recorder.restoreOutputInterruptionIfNeeded()

        XCTAssertNil(recorder.pausedMediaSession)
        XCTAssertEqual(media.scheduleCallCount, 1)
        XCTAssertEqual(media.resumedSessions, [session])
    }

    func testMeetingRecorderDoesNotInterruptOutputForProductionSources() throws {
        let modes: [AppSettingsStore.RecordingMediaHandlingMode] = [.pauseMedia, .duckAudio]

        for source in [RecordingSource.all, .system] {
            for mode in modes {
                AppSettingsStore.shared.recordingMediaHandlingMode = mode
                let media = FakeMediaPlaybackController(outcome: .unsupported)
                let mute = FakeOutputDuckingController()
                let recorder = MeetingRecorder(muteController: mute, mediaPlaybackController: media)
                recorder.microphonePermissionValidator = {}

                try recorder.prepareRecordingAttempt(
                    outputURL: URL(fileURLWithPath: "/tmp/meeting-output-interruption.m4a"),
                    source: source
                )

                XCTAssertNil(recorder.pausedMediaSession)
                XCTAssertNil(recorder.outputMuteSession)
                XCTAssertNil(recorder.outputDuckingLevelPercent)
                XCTAssertEqual(media.scheduleCallCount, 0)
                XCTAssertEqual(mute.prepareCallCount, 0)

                recorder.restoreOutputInterruptionIfNeeded()

                XCTAssertTrue(media.resumedSessions.isEmpty)
                XCTAssertTrue(mute.restoredSessions.isEmpty)
            }
        }
    }

    func testDuckingIsAppliedAndRestoredForDictationRecorder() async {
        AppSettingsStore.shared.recordingMediaHandlingMode = .duckAudio
        let mute = FakeOutputDuckingController()
        let applied = expectation(description: "Ducking applied to dictation recorder")
        mute.onApply = { applied.fulfill() }
        let recorder = DictationRecorder(muteController: mute)
        recorder.activeRecordingSource = .microphone
        recorder.isRecording = true
        recorder.outputMuteSession = mute.session
        recorder.outputDuckingLevelPercent = 30

        recorder.scheduleOutputMuteIfNeeded()

        await fulfillment(of: [applied], timeout: 2)

        XCTAssertEqual(mute.appliedLevels, [30])

        recorder.restoreOutputInterruptionIfNeeded()

        XCTAssertNil(recorder.outputMuteSession)
        XCTAssertNil(recorder.outputDuckingLevelPercent)
        XCTAssertEqual(mute.restoredSessions.count, 1)
    }
}

@MainActor
private final class FakeMediaPlaybackController: MediaPlaybackControlling {
    private let outcome: MediaPlaybackPauseOutcome
    private(set) var scheduleCallCount = 0
    private(set) var resumedSessions: [MediaPlaybackResumeSession] = []

    init(outcome: MediaPlaybackPauseOutcome) {
        self.outcome = outcome
    }

    func pausePlaybackIfNeeded() -> MediaPlaybackPauseOutcome {
        outcome
    }

    func schedulePausePlaybackIfNeeded(onComplete: @escaping @MainActor (MediaPlaybackPauseOutcome) -> Void) {
        scheduleCallCount += 1
        onComplete(outcome)
    }

    func resumePlayback(from session: MediaPlaybackResumeSession) {
        resumedSessions.append(session)
    }
}

@MainActor
private final class FakeOutputDuckingController: OutputDuckingControlling {
    let session = SystemAudioMuteController.OutputMuteSession(
        deviceID: 0,
        wasMuted: false,
        volumeState: nil,
        canMute: true,
        appliedStrategy: nil
    )
    var onApply: (() -> Void)?
    private(set) var prepareCallCount = 0
    private(set) var appliedLevels: [Int] = []
    private(set) var restoredSessions: [SystemAudioMuteController.OutputMuteSession] = []

    func prepareOutputMuteSession() -> SystemAudioMuteController.OutputMuteSession? {
        prepareCallCount += 1
        return session
    }

    func applyDucking(to session: inout SystemAudioMuteController.OutputMuteSession, levelPercent: Int) throws {
        appliedLevels.append(levelPercent)
        onApply?()
    }

    func restoreOutputState(from session: SystemAudioMuteController.OutputMuteSession) {
        restoredSessions.append(session)
    }
}
