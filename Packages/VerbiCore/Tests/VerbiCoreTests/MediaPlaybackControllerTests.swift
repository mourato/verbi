import Foundation
import os.log
@testable import VerbiCoreInfrastructure
import XCTest

@MainActor
final class MediaPlaybackControllerTests: XCTestCase {
    func testPausePlaybackReturnsFirstPausedSession() {
        let controller = MediaPlaybackController(players: [
            MockMediaPlayer(result: .notPlaying),
            MockMediaPlayer(result: .paused(.init(target: .spotify)))
        ])

        let outcome = controller.pausePlaybackIfNeeded()

        XCTAssertEqual(outcome, .paused(.init(target: .spotify)))
    }

    func testPausePlaybackReturnsUnsupportedWhenNoPlayerCanBeControlled() {
        let controller = MediaPlaybackController(players: [
            MockMediaPlayer(result: .unsupported),
            MockMediaPlayer(result: .notRunning)
        ])

        let outcome = controller.pausePlaybackIfNeeded()

        XCTAssertEqual(outcome, .unsupported)
    }

    func testPausePlaybackReturnsFailedWhenKnownPlayerErrors() {
        let controller = MediaPlaybackController(players: [
            MockMediaPlayer(result: .failed)
        ])

        let outcome = controller.pausePlaybackIfNeeded()

        XCTAssertEqual(outcome, .failed)
    }

    func testResumePlaybackOnlyTargetsMatchingPlayer() {
        let music = MockMediaPlayer(target: .music, result: .notPlaying)
        let spotify = MockMediaPlayer(target: .spotify, result: .notPlaying)
        let controller = MediaPlaybackController(players: [music, spotify])

        controller.resumePlayback(from: .init(target: .spotify))

        XCTAssertEqual(music.resumeCallCount, 0)
        XCTAssertEqual(spotify.resumeCallCount, 1)
    }

    func testSchedulePausePlaybackDeliversCompletionOffCriticalPath() async {
        let controller = MediaPlaybackController(players: [
            MockMediaPlayer(result: .paused(.init(target: .music)))
        ])

        let outcome = await withCheckedContinuation { continuation in
            controller.schedulePausePlaybackIfNeeded { result in
                continuation.resume(returning: result)
            }
        }

        XCTAssertEqual(outcome, .noActivePlayback)
    }
}

@MainActor
private final class MockMediaPlayer: MediaPlaybackAutomating {
    let target: MediaPlaybackTarget
    let applicationName: String
    let bundleIdentifier: String

    var result: MediaPlaybackPlayerResult
    var resumeCallCount = 0

    init(
        target: MediaPlaybackTarget = .music,
        result: MediaPlaybackPlayerResult
    ) {
        self.target = target
        applicationName = target.rawValue
        bundleIdentifier = target.rawValue
        self.result = result
    }

    func pauseIfPlaying(logger _: Logger) -> MediaPlaybackPlayerResult {
        result
    }

    func resume(logger _: Logger) {
        resumeCallCount += 1
    }
}
