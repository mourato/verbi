import AppKit
import Foundation
import os.log
import ScriptingBridge
import VerbiCoreCommon

@MainActor
public protocol MediaPlaybackControlling: AnyObject {
    func pausePlaybackIfNeeded() -> MediaPlaybackPauseOutcome
    func schedulePausePlaybackIfNeeded(onComplete: @escaping @MainActor (MediaPlaybackPauseOutcome) -> Void)
    func resumePlayback(from session: MediaPlaybackResumeSession)
}

public enum MediaPlaybackTarget: String, Equatable, Sendable {
    case music
    case spotify
}

public struct MediaPlaybackResumeSession: Equatable, Sendable {
    public let target: MediaPlaybackTarget

    public init(target: MediaPlaybackTarget) {
        self.target = target
    }
}

public enum MediaPlaybackPauseOutcome: Equatable, Sendable {
    case paused(MediaPlaybackResumeSession)
    case noActivePlayback
    case unsupported
    case failed
}

@MainActor
public final class MediaPlaybackController: MediaPlaybackControlling {
    public static let shared = MediaPlaybackController()

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "MediaPlaybackController")
    private let players: [any MediaPlaybackAutomating]

    init(players: [any MediaPlaybackAutomating] = [
        MusicMediaPlaybackAutomation(),
        SpotifyMediaPlaybackAutomation()
    ]) {
        self.players = players
    }

    public func pausePlaybackIfNeeded() -> MediaPlaybackPauseOutcome {
        var sawUnsupported = false
        var sawFailure = false

        for player in players {
            switch player.pauseIfPlaying(logger: logger) {
            case let .paused(session):
                return .paused(session)
            case .notRunning, .notPlaying:
                continue
            case .unsupported:
                sawUnsupported = true
            case .failed:
                sawFailure = true
            }
        }

        if sawFailure {
            return .failed
        }

        if sawUnsupported {
            return .unsupported
        }

        return .noActivePlayback
    }

    public func schedulePausePlaybackIfNeeded(onComplete: @escaping @MainActor (MediaPlaybackPauseOutcome) -> Void) {
        let bridges = players.map { player in
            MediaPlayerBridge(
                target: player.target,
                applicationName: player.applicationName,
                bundleIdentifier: player.bundleIdentifier
            )
        }
        let logger = logger

        Thread.detachNewThread {
            let outcome = MediaPlaybackController.pauseUsingBridges(bridges, logger: logger)
            DispatchQueue.main.async {
                onComplete(outcome)
            }
        }
    }

    public func resumePlayback(from session: MediaPlaybackResumeSession) {
        guard let player = players.first(where: { $0.target == session.target }) else { return }
        player.resume(logger: logger)
    }

    private nonisolated static func pauseUsingBridges(
        _ bridges: [MediaPlayerBridge],
        logger: Logger
    ) -> MediaPlaybackPauseOutcome {
        var sawUnsupported = false
        var sawFailure = false

        for bridge in bridges {
            switch bridge.pauseIfPlaying(logger: logger) {
            case let .paused(session):
                return .paused(session)
            case .notRunning, .notPlaying:
                continue
            case .unsupported:
                sawUnsupported = true
            case .failed:
                sawFailure = true
            }
        }

        if sawFailure {
            return .failed
        }

        if sawUnsupported {
            return .unsupported
        }

        return .noActivePlayback
    }
}

enum MediaPlaybackPlayerResult {
    case paused(MediaPlaybackResumeSession)
    case notRunning
    case notPlaying
    case unsupported
    case failed
}

@MainActor
protocol MediaPlaybackAutomating {
    var target: MediaPlaybackTarget { get }
    var applicationName: String { get }
    var bundleIdentifier: String { get }

    func pauseIfPlaying(logger: Logger) -> MediaPlaybackPlayerResult
    func resume(logger: Logger)
}

private extension MediaPlaybackAutomating {
    func pauseIfPlaying(logger: Logger) -> MediaPlaybackPlayerResult {
        ScriptingBridgeMediaPlayer.pauseIfPlaying(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            target: target,
            logger: logger
        )
    }

    func resume(logger: Logger) {
        ScriptingBridgeMediaPlayer.resume(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            logger: logger
        )
    }
}

private struct MediaPlayerBridge: Sendable {
    let target: MediaPlaybackTarget
    let applicationName: String
    let bundleIdentifier: String

    func pauseIfPlaying(logger: Logger) -> MediaPlaybackPlayerResult {
        ScriptingBridgeMediaPlayer.pauseIfPlaying(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            target: target,
            logger: logger
        )
    }
}

private enum ScriptingBridgeMediaPlayer {
    static let automationPermissionDeniedErrorCode = -1743
    static let playingPlayerStateCode: OSType = fourCharCode("kPSP")

    static func pauseIfPlaying(
        bundleIdentifier: String,
        applicationName: String,
        target: MediaPlaybackTarget,
        logger: Logger
    ) -> MediaPlaybackPlayerResult {
        guard isApplicationRunning(bundleIdentifier: bundleIdentifier) else { return .notRunning }

        guard let state = playerStateCode(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            logger: logger
        ) else {
            return .failed
        }

        guard state == playingPlayerStateCode else { return .notPlaying }

        guard sendPause(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            logger: logger
        ) else {
            return .unsupported
        }

        logger.info("Paused media playback for recording: \(applicationName, privacy: .public)")
        return .paused(MediaPlaybackResumeSession(target: target))
    }

    static func resume(bundleIdentifier: String, applicationName: String, logger: Logger) {
        guard isApplicationRunning(bundleIdentifier: bundleIdentifier) else { return }
        _ = sendPlay(bundleIdentifier: bundleIdentifier, applicationName: applicationName, logger: logger)
    }

    private static func isApplicationRunning(bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private static func playerStateCode(
        bundleIdentifier: String,
        applicationName: String,
        logger: Logger
    ) -> OSType? {
        guard let application = SBApplication(bundleIdentifier: bundleIdentifier) else { return nil }
        let capture = ScriptingErrorCapture()
        application.delegate = capture
        let scriptable: ScriptableMediaApplication = application
        let state = scriptable.playerState
        if let error = capture.error {
            logScriptingError(error, applicationName: applicationName, logger: logger)
            return nil
        }
        return state
    }

    private static func sendPause(
        bundleIdentifier: String,
        applicationName: String,
        logger: Logger
    ) -> Bool {
        guard let application = SBApplication(bundleIdentifier: bundleIdentifier) else { return false }
        let capture = ScriptingErrorCapture()
        application.delegate = capture
        let scriptable: ScriptableMediaApplication = application
        scriptable.pause?()
        if let error = capture.error {
            logScriptingError(error, applicationName: applicationName, logger: logger)
            return false
        }
        return true
    }

    private static func sendPlay(bundleIdentifier: String, applicationName: String, logger: Logger) -> Bool {
        guard let application = SBApplication(bundleIdentifier: bundleIdentifier) else { return false }
        let capture = ScriptingErrorCapture()
        application.delegate = capture
        let scriptable: ScriptableMediaApplication = application
        scriptable.play?()
        if let error = capture.error {
            logScriptingError(error, applicationName: applicationName, logger: logger)
            return false
        }
        return true
    }

    private static func logScriptingError(_ error: NSError, applicationName: String, logger: Logger) {
        let message = error.localizedDescription
        if error.code == automationPermissionDeniedErrorCode {
            logger.warning(
                "ScriptingBridge automation permission denied for \(applicationName, privacy: .public): \(message, privacy: .public)"
            )
        } else {
            logger.debug(
                "ScriptingBridge error for \(applicationName, privacy: .public) [\(error.code)]: \(message, privacy: .public)"
            )
        }
    }

    private static func fourCharCode(_ string: String) -> OSType {
        var code: OSType = 0
        for unit in string.utf8 {
            code = (code << 8) | OSType(unit)
        }
        return code
    }
}

@objc protocol ScriptableMediaApplication {
    @objc optional var playerState: OSType { get }
    @objc optional func pause()
    @objc optional func play()
}

extension SBApplication: ScriptableMediaApplication {}

private final class ScriptingErrorCapture: NSObject, SBApplicationDelegate {
    var error: NSError?

    func eventDidFail(_: UnsafePointer<AppleEvent>, withError error: any Error) -> Any? {
        self.error = error as NSError
        return nil
    }
}

private struct MusicMediaPlaybackAutomation: MediaPlaybackAutomating {
    let target: MediaPlaybackTarget = .music
    let applicationName = "Music"
    let bundleIdentifier = "com.apple.Music"
}

private struct SpotifyMediaPlaybackAutomation: MediaPlaybackAutomating {
    let target: MediaPlaybackTarget = .spotify
    let applicationName = "Spotify"
    let bundleIdentifier = "com.spotify.client"
}
