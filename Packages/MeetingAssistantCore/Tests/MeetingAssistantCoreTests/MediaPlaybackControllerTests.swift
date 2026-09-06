import Foundation
@testable import MeetingAssistantCoreInfrastructure
import os.log
import XCTest

@MainActor
final class MediaPlaybackControllerTests: XCTestCase {
    func testPausePlaybackReturnsFirstPausedSession() {
        let controller = MediaPlaybackController(players: [
            MockAppleScriptMediaPlayer(result: .notPlaying),
            MockAppleScriptMediaPlayer(result: .paused(.init(target: .spotify))),
        ])

        let outcome = controller.pausePlaybackIfNeeded()

        XCTAssertEqual(outcome, .paused(.init(target: .spotify)))
    }

    func testPausePlaybackReturnsUnsupportedWhenNoPlayerCanBeControlled() {
        let controller = MediaPlaybackController(players: [
            MockAppleScriptMediaPlayer(result: .unsupported),
            MockAppleScriptMediaPlayer(result: .notRunning),
        ])

        let outcome = controller.pausePlaybackIfNeeded()

        XCTAssertEqual(outcome, .unsupported)
    }

    func testPausePlaybackReturnsFailedWhenKnownPlayerErrors() {
        let controller = MediaPlaybackController(players: [
            MockAppleScriptMediaPlayer(result: .failed),
        ])

        let outcome = controller.pausePlaybackIfNeeded()

        XCTAssertEqual(outcome, .failed)
    }

    func testResumePlaybackOnlyTargetsMatchingPlayer() {
        let music = MockAppleScriptMediaPlayer(target: .music, result: .notPlaying)
        let spotify = MockAppleScriptMediaPlayer(target: .spotify, result: .notPlaying)
        let controller = MediaPlaybackController(players: [music, spotify])

        controller.resumePlayback(from: .init(target: .spotify))

        XCTAssertEqual(music.resumeCallCount, 0)
        XCTAssertEqual(spotify.resumeCallCount, 1)
    }

    func testSchedulePausePlaybackDeliversCompletionOffCriticalPath() async {
        let controller = MediaPlaybackController(players: [
            MockAppleScriptMediaPlayer(result: .paused(.init(target: .music))),
        ])

        let outcome = await withCheckedContinuation { continuation in
            controller.schedulePausePlaybackIfNeeded { result in
                continuation.resume(returning: result)
            }
        }

        // Off-main path uses script snapshots (not mock pauseIfPlaying); empty mock
        // bundle IDs resolve to not-running → noActivePlayback, but completion still fires.
        XCTAssertEqual(outcome, .noActivePlayback)
    }
}

@MainActor
private final class MockAppleScriptMediaPlayer: AppleScriptMediaPlaybackAutomating {
    let target: MediaPlaybackTarget
    let applicationName: String
    let bundleIdentifier: String
    let stateScript = ""
    let pauseScript = ""
    let resumeScript = ""

    var result: AppleScriptMediaPlaybackResult
    var resumeCallCount = 0

    init(
        target: MediaPlaybackTarget = .music,
        result: AppleScriptMediaPlaybackResult,
    ) {
        self.target = target
        applicationName = target.rawValue
        bundleIdentifier = target.rawValue
        self.result = result
    }

    func pauseIfPlaying(logger _: Logger) -> AppleScriptMediaPlaybackResult {
        result
    }

    func resume(logger _: Logger) {
        resumeCallCount += 1
    }
}
