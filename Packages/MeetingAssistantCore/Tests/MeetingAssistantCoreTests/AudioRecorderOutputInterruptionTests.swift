import AVFoundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreAudio
@testable import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class AudioRecorderOutputInterruptionTests: XCTestCase {
    func testPauseModePrefersPauseSessionWhenSupported() {
        let session = MediaPlaybackResumeSession(target: .music)

        let plan = AudioRecorder.makeOutputInterruptionPlan(
            mode: .pauseMedia,
            mediaPauseOutcome: .paused(session),
            duckingLevelPercent: 30,
        )

        XCTAssertEqual(plan, .pause(session))
    }

    func testPauseModeFallsBackToDuckingWhenPauseUnsupported() {
        let plan = AudioRecorder.makeOutputInterruptionPlan(
            mode: .pauseMedia,
            mediaPauseOutcome: .unsupported,
            duckingLevelPercent: 25,
        )

        XCTAssertEqual(plan, .duck(25))
    }

    func testPauseModeFallsBackToNoInterruptionWhenDuckingDisabled() {
        let plan = AudioRecorder.makeOutputInterruptionPlan(
            mode: .pauseMedia,
            mediaPauseOutcome: .failed,
            duckingLevelPercent: 100,
        )

        XCTAssertEqual(plan, .none)
    }

    func testDuckModeUsesConfiguredDuckingLevel() {
        let plan = AudioRecorder.makeOutputInterruptionPlan(
            mode: .duckAudio,
            mediaPauseOutcome: .noActivePlayback,
            duckingLevelPercent: 40,
        )

        XCTAssertEqual(plan, .duck(40))
    }

    func testNoneModeLeavesOutputUntouched() {
        let plan = AudioRecorder.makeOutputInterruptionPlan(
            mode: .none,
            mediaPauseOutcome: .paused(.init(target: .spotify)),
            duckingLevelPercent: 0,
        )

        XCTAssertEqual(plan, .none)
    }

    func testResetRecordingStateAfterStopClearsStateForNextRecording() {
        let recorder = AudioRecorder()
        recorder.isRecording = true
        recorder.currentRecordingURL = URL(fileURLWithPath: "/tmp/recording.m4a")
        recorder.currentAveragePower = -12
        recorder.currentPeakPower = -6

        recorder.resetRecordingStateAfterStop()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentRecordingURL)
        XCTAssertEqual(recorder.currentAveragePower, -160)
        XCTAssertEqual(recorder.currentPeakPower, -160)
    }

    func testCleanupAfterFailedStartClearsEngineResourcesForNextRecording() async {
        let recorder = AudioRecorder()
        recorder.audioEngine = AVAudioEngine()

        await recorder.cleanupAfterFailedStart()

        XCTAssertNil(recorder.audioEngine)
        XCTAssertFalse(recorder.hasPendingStartupResources)
    }

    func testStaleValidationTimeoutCannotStopCurrentRecording() async {
        let recorder = AudioRecorder()
        let currentURL = URL(fileURLWithPath: "/tmp/current-recording.m4a")

        recorder.isRecording = true
        recorder.currentRecordingURL = currentURL
        recorder.activeRecordingSource = .microphone
        recorder.activeValidationSessionID = UUID()

        await recorder.handleValidationTimeout(
            url: currentURL,
            source: .microphone,
            retryCount: 0,
            sessionID: UUID(),
        )

        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.currentRecordingURL, currentURL)
    }
}
