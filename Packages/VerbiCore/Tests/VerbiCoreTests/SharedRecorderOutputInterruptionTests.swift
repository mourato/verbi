import Foundation
@testable import VerbiCoreAudio
@testable import VerbiCoreInfrastructure
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

    func testPauseMediaIsPreparedAndRestoredForBothRecorders() throws {
        AppSettingsStore.shared.recordingMediaHandlingMode = .pauseMedia
        let session = MediaPlaybackResumeSession(target: .music)
        let media = FakeMediaPlaybackController(outcome: .paused(session))
        let mute = FakeOutputDuckingController()
        let recorders: [BaseAudioRecorder] = [
            DictationRecorder(muteController: mute, mediaPlaybackController: media),
            MeetingRecorder(muteController: mute, mediaPlaybackController: media)
        ]

        for recorder in recorders {
            recorder.microphonePermissionValidator = {}
            try recorder.prepareRecordingAttempt(
                outputURL: URL(fileURLWithPath: "/tmp/output-interruption.m4a"),
                source: .microphone
            )

            XCTAssertEqual(recorder.pausedMediaSession, session)

            recorder.restoreOutputInterruptionIfNeeded()

            XCTAssertNil(recorder.pausedMediaSession)
        }

        XCTAssertEqual(media.scheduleCallCount, 2)
        XCTAssertEqual(media.resumedSessions, [session, session])
    }

    func testDuckingIsAppliedAndRestoredForBothRecorders() async {
        let mute = FakeOutputDuckingController()
        let applied = expectation(description: "Ducking applied to both recorders")
        applied.expectedFulfillmentCount = 2
        mute.onApply = { applied.fulfill() }
        let recorders: [BaseAudioRecorder] = [
            DictationRecorder(muteController: mute),
            MeetingRecorder(muteController: mute)
        ]

        for recorder in recorders {
            recorder.isRecording = true
            recorder.outputMuteSession = mute.session
            recorder.outputDuckingLevelPercent = 30
            recorder.scheduleOutputMuteIfNeeded()
        }

        await fulfillment(of: [applied], timeout: 2)

        XCTAssertEqual(mute.appliedLevels, [30, 30])

        for recorder in recorders {
            recorder.restoreOutputInterruptionIfNeeded()
            XCTAssertNil(recorder.outputMuteSession)
            XCTAssertNil(recorder.outputDuckingLevelPercent)
        }

        XCTAssertEqual(mute.restoredSessions.count, 2)
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
    private(set) var appliedLevels: [Int] = []
    private(set) var restoredSessions: [SystemAudioMuteController.OutputMuteSession] = []

    func prepareOutputMuteSession() -> SystemAudioMuteController.OutputMuteSession? {
        session
    }

    func applyDucking(to session: inout SystemAudioMuteController.OutputMuteSession, levelPercent: Int) throws {
        appliedLevels.append(levelPercent)
        onApply?()
    }

    func restoreOutputState(from session: SystemAudioMuteController.OutputMuteSession) {
        restoredSessions.append(session)
    }
}
