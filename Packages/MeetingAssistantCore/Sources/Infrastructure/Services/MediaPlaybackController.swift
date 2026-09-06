import AppKit
import Foundation
import MeetingAssistantCoreCommon
import os.log

@MainActor
public protocol MediaPlaybackControlling: AnyObject {
    func pausePlaybackIfNeeded() -> MediaPlaybackPauseOutcome
    /// Runs AppleScript off the calling actor; never blocks the start critical path.
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
    private let players: [any AppleScriptMediaPlaybackAutomating]

    init(players: [any AppleScriptMediaPlaybackAutomating] = [
        MusicMediaPlaybackAutomation(),
        SpotifyMediaPlaybackAutomation(),
    ]) {
        self.players = players
    }

    /// Sync helper for tests/mocks. Production mic start must use `schedulePausePlaybackIfNeeded`.
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

    // ponytail: fire-and-forget AppleScript off MainActor; best-effort pause; upgrade to ScriptingBridge if needed
    public func schedulePausePlaybackIfNeeded(onComplete: @escaping @MainActor (MediaPlaybackPauseOutcome) -> Void) {
        let scripts = players.map { player in
            MediaPlayerScriptSnapshot(
                target: player.target,
                applicationName: player.applicationName,
                bundleIdentifier: player.bundleIdentifier,
                stateScript: player.stateScript,
                pauseScript: player.pauseScript,
            )
        }
        let logger = logger

        Thread.detachNewThread {
            let outcome = MediaPlaybackController.pauseUsingScripts(scripts, logger: logger)
            DispatchQueue.main.async {
                onComplete(outcome)
            }
        }
    }

    public func resumePlayback(from session: MediaPlaybackResumeSession) {
        guard let player = players.first(where: { $0.target == session.target }) else { return }
        player.resume(logger: logger)
    }

    private nonisolated static func pauseUsingScripts(
        _ scripts: [MediaPlayerScriptSnapshot],
        logger: Logger,
    ) -> MediaPlaybackPauseOutcome {
        var sawUnsupported = false
        var sawFailure = false

        for player in scripts {
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
}

enum AppleScriptMediaPlaybackResult {
    case paused(MediaPlaybackResumeSession)
    case notRunning
    case notPlaying
    case unsupported
    case failed
}

@MainActor
protocol AppleScriptMediaPlaybackAutomating {
    var target: MediaPlaybackTarget { get }
    var applicationName: String { get }
    var bundleIdentifier: String { get }
    var stateScript: String { get }
    var pauseScript: String { get }
    var resumeScript: String { get }

    func pauseIfPlaying(logger: Logger) -> AppleScriptMediaPlaybackResult
    func resume(logger: Logger)
}

private extension AppleScriptMediaPlaybackAutomating {
    static var automationPermissionDeniedErrorCode: Int {
        -1_743
    }

    func pauseIfPlaying(logger: Logger) -> AppleScriptMediaPlaybackResult {
        guard isRunning else { return .notRunning }

        guard let state = currentPlaybackState(logger: logger) else {
            return .failed
        }

        guard state == "playing" else {
            return .notPlaying
        }

        guard execute(scriptSource: pauseScript, logger: logger) else {
            return .unsupported
        }

        logger.info("Paused media playback for recording: \(applicationName, privacy: .public)")
        return .paused(MediaPlaybackResumeSession(target: target))
    }

    func resume(logger: Logger) {
        guard isRunning else { return }
        _ = execute(scriptSource: resumeScript, logger: logger)
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private func currentPlaybackState(logger: Logger) -> String? {
        executeString(scriptSource: stateScript, logger: logger)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func executeString(scriptSource: String, logger: Logger) -> String? {
        executeAppleScript(scriptSource: scriptSource, logger: logger)?.stringValue
    }

    private func execute(scriptSource: String, logger: Logger) -> Bool {
        executeAppleScript(scriptSource: scriptSource, logger: logger) != nil
    }

    private func executeAppleScript(scriptSource: String, logger: Logger) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: scriptSource) else {
            logger.error("Failed to compile AppleScript for \(applicationName, privacy: .public)")
            return nil
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            logAppleScriptError(errorInfo, logger: logger)
            return nil
        }

        return result
    }

    private func logAppleScriptError(_ errorInfo: NSDictionary, logger: Logger) {
        let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int
        let errorMessage = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown"
        if errorNumber == Self.automationPermissionDeniedErrorCode {
            logger.warning(
                "AppleScript automation permission denied for \(applicationName, privacy: .public): \(errorMessage, privacy: .public)",
            )
        } else {
            logger.debug(
                "AppleScript error for \(applicationName, privacy: .public) [\(errorNumber ?? 0)]: \(errorMessage, privacy: .public)",
            )
        }
    }
}

private struct MediaPlayerScriptSnapshot: Sendable {
    let target: MediaPlaybackTarget
    let applicationName: String
    let bundleIdentifier: String
    let stateScript: String
    let pauseScript: String

    func pauseIfPlaying(logger: Logger) -> AppleScriptMediaPlaybackResult {
        guard isRunning else { return .notRunning }

        guard let state = currentPlaybackState(logger: logger) else {
            return .failed
        }

        guard state == "playing" else {
            return .notPlaying
        }

        guard execute(scriptSource: pauseScript, logger: logger) else {
            return .unsupported
        }

        logger.info("Paused media playback for recording: \(applicationName, privacy: .public)")
        return .paused(MediaPlaybackResumeSession(target: target))
    }

    private var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private func currentPlaybackState(logger: Logger) -> String? {
        executeString(scriptSource: stateScript, logger: logger)?.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func executeString(scriptSource: String, logger: Logger) -> String? {
        executeAppleScript(scriptSource: scriptSource, logger: logger)?.stringValue
    }

    private func execute(scriptSource: String, logger: Logger) -> Bool {
        executeAppleScript(scriptSource: scriptSource, logger: logger) != nil
    }

    private func executeAppleScript(scriptSource: String, logger: Logger) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: scriptSource) else {
            logger.error("Failed to compile AppleScript for \(applicationName, privacy: .public)")
            return nil
        }

        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            logAppleScriptError(errorInfo, logger: logger)
            return nil
        }

        return result
    }

    private func logAppleScriptError(_ errorInfo: NSDictionary, logger: Logger) {
        let errorNumber = errorInfo[NSAppleScript.errorNumber] as? Int
        let errorMessage = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown"
        if errorNumber == -1_743 {
            logger.warning(
                "AppleScript automation permission denied for \(applicationName, privacy: .public): \(errorMessage, privacy: .public)",
            )
        } else {
            logger.debug(
                "AppleScript error for \(applicationName, privacy: .public) [\(errorNumber ?? 0)]: \(errorMessage, privacy: .public)",
            )
        }
    }
}

private struct MusicMediaPlaybackAutomation: AppleScriptMediaPlaybackAutomating {
    let target: MediaPlaybackTarget = .music
    let applicationName = "Music"
    let bundleIdentifier = "com.apple.Music"
    let stateScript = "tell application \"Music\" to get player state as string"
    let pauseScript = "tell application \"Music\" to pause"
    let resumeScript = "tell application \"Music\" to play"
}

private struct SpotifyMediaPlaybackAutomation: AppleScriptMediaPlaybackAutomating {
    let target: MediaPlaybackTarget = .spotify
    let applicationName = "Spotify"
    let bundleIdentifier = "com.spotify.client"
    let stateScript = "tell application \"Spotify\" to get player state as string"
    let pauseScript = "tell application \"Spotify\" to pause"
    let resumeScript = "tell application \"Spotify\" to play"
}
