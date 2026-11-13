import AVFoundation
@testable import VerbiCore
@testable import VerbiCoreAudio
@testable import VerbiCoreInfrastructure
import XCTest

@MainActor
final class AudioRecorderOutputInterruptionTests: XCTestCase {
    func testPauseModePrefersPauseSessionWhenSupported() {
        let session = MediaPlaybackResumeSession(target: .music)

        let plan = AudioRecorder.makeOutputInterruptionPlan(
            mode: .pauseMedia,
            mediaPauseOutcome: .paused(session),
            duckingLevelPercent: 30
        )

        XCTAssertEqual(plan, .pause(session))
    }

    func testPauseModeFallsBackToDuckingWhenPauseUnsupported() {
        let plan = AudioRecorder.makeOutputInterruptionPlan(
            mode: .pauseMedia,
            mediaPauseOutcome: .unsupported,
            duckingLevelPercent: 25
        )

        XCTAssertEqual(plan, .duck(25))
    }

    func testPauseModeFallsBackToNoInterruptionWhenDuckingDisabled() {
        let plan = AudioRecorder.makeOutputInterruptionPlan(
            mode: .pauseMedia,
            mediaPauseOutcome: .failed,
            duckingLevelPercent: 100
        )

        XCTAssertEqual(plan, .none)
    }

    func testDuckModeUsesConfiguredDuckingLevel() {
        let plan = AudioRecorder.makeOutputInterruptionPlan(
            mode: .duckAudio,
            mediaPauseOutcome: .noActivePlayback,
            duckingLevelPercent: 40
        )

        XCTAssertEqual(plan, .duck(40))
    }

    func testNoneModeLeavesOutputUntouched() {
        let plan = AudioRecorder.makeOutputInterruptionPlan(
            mode: .none,
            mediaPauseOutcome: .paused(.init(target: .spotify)),
            duckingLevelPercent: 0
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
            sessionID: UUID()
        )

        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.currentRecordingURL, currentURL)
    }

    func testCaptureRestartDoesNotPublishRecordingStop() {
        let recorder = AudioRecorder()
        var published: [Bool] = []
        let cancellable = recorder.isRecordingPublisher.sink { published.append($0) }
        defer { cancellable.cancel() }

        recorder.isRecording = true
        recorder.restartingCaptureURL = URL(fileURLWithPath: "/tmp/meeting.m4a")
        recorder.isRecording = false
        recorder.isRecording = true
        recorder.restartingCaptureURL = nil

        XCTAssertEqual(published, [false, true])
    }

    func testStopDuringValidationRestartKeepsSessionUntilStopAndNeverRestarts() async {
        let recorder = AudioRecorder()
        let sessionURL = URL(fileURLWithPath: "/tmp/meeting-restart.m4a")
        let sessionID = UUID()
        let reportedError = LockedErrorBox()
        recorder.onRecordingError = { reportedError.set($0) }
        recorder.isRecording = true
        recorder.currentRecordingURL = sessionURL
        recorder.activeRecordingSource = .all
        recorder.activeValidationSessionID = sessionID
        var published: [Bool] = []
        let cancellable = recorder.isRecordingPublisher.sink { published.append($0) }
        defer { cancellable.cancel() }

        let restart = Task {
            await recorder.handleValidationTimeout(
                url: sessionURL,
                source: .all,
                retryCount: 0,
                sessionID: sessionID,
                allowsRestart: true
            )
        }
        // Stop once the restart has begun; the retry delay is 500 ms, far beyond these yields.
        for _ in 0 ..< 1_000 where recorder.restartingCaptureURL == nil {
            await Task.yield()
        }
        XCTAssertEqual(recorder.restartingCaptureURL, sessionURL)
        XCTAssertEqual(published, [true])

        let stoppedURL = await recorder.stopRecording()
        await restart.value

        XCTAssertEqual(stoppedURL, sessionURL)
        XCTAssertEqual(published, [true, false])
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.audioEngine)
        XCTAssertNil(recorder.fallbackRecorder)
        XCTAssertNil(recorder.restartingCaptureURL)
        XCTAssertNil(reportedError.value)
    }

    func testStopDuringCaptureRestartCancelsRestartAndReturnsItsFile() async {
        let recorder = AudioRecorder()
        let restartURL = URL(fileURLWithPath: "/tmp/meeting.m4a")
        let restartSessionID = UUID()
        recorder.activeValidationSessionID = restartSessionID
        recorder.restartingCaptureURL = restartURL

        let stoppedURL = await recorder.stopRecording()

        XCTAssertEqual(stoppedURL, restartURL)
        XCTAssertNil(recorder.restartingCaptureURL)
        XCTAssertNotEqual(recorder.activeValidationSessionID, restartSessionID)
    }

    func testValidationFailureAfterGraphRecoveryReportsErrorWithoutRestart() async {
        let recorder = AudioRecorder()
        let sessionURL = URL(fileURLWithPath: "/tmp/meeting-in-progress.m4a")
        let sessionID = UUID()
        let reportedError = LockedErrorBox()
        recorder.onRecordingError = { reportedError.set($0) }

        recorder.isRecording = true
        recorder.currentRecordingURL = sessionURL
        recorder.activeRecordingSource = .all
        recorder.activeValidationSessionID = sessionID

        await recorder.handleValidationTimeout(
            url: sessionURL,
            source: .all,
            retryCount: 0,
            sessionID: sessionID,
            allowsRestart: false
        )

        XCTAssertTrue(recorder.isRecording)
        XCTAssertEqual(recorder.currentRecordingURL, sessionURL)
        XCTAssertNil(recorder.restartingCaptureURL)
        guard case .recordingValidationFailed? = reportedError.value as? AudioRecorderError else {
            return XCTFail("Expected recordingValidationFailed, got \(String(describing: reportedError.value))")
        }
    }
}

private final class LockedErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedError: Error?

    var value: Error? {
        lock.withLock { storedError }
    }

    func set(_ error: Error) {
        lock.withLock { storedError = error }
    }
}
