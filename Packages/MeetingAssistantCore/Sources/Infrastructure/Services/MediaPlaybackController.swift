import AppKit
import Foundation
import MeetingAssistantCoreCommon
import os.log

@MainActor
public protocol MediaPlaybackControlling: AnyObject {
    func pausePlaybackIfNeeded() -> MediaPlaybackPauseOutcome
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

    public func resumePlayback(from session: MediaPlaybackResumeSession) {
        guard let player = players.first(where: { $0.target == session.target }) else { return }
        player.resume(logger: logger)
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
        switch executeAppleScriptBounded(scriptSource: scriptSource, logger: logger) {
        case let .success(descriptor):
            descriptor.stringValue
        case .compileFailed, .runtimeFailed, .timedOut:
            nil
        }
    }

    private func execute(scriptSource: String, logger: Logger) -> Bool {
        switch executeAppleScriptBounded(scriptSource: scriptSource, logger: logger) {
        case .success:
            true
        case .compileFailed, .runtimeFailed, .timedOut:
            false
        }
    }

    // ponytail: NSAppleScript can hang; bounded wait; upgrade to async Automation/ScriptingBridge if needed
    private func executeAppleScriptBounded(
        scriptSource: String,
        logger: Logger,
    ) -> BoundedAppleScriptResult {
        let box = AppleScriptExecutionBox()
        let semaphore = DispatchSemaphore(value: 0)

        Thread.detachNewThread {
            guard let script = NSAppleScript(source: scriptSource) else {
                box.compileFailed = true
                semaphore.signal()
                return
            }

            var errorInfo: NSDictionary?
            let result = script.executeAndReturnError(&errorInfo)
            box.descriptor = result
            box.errorInfo = errorInfo
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + Self.appleScriptTimeout)
        if waitResult == .timedOut {
            logger.warning(
                "AppleScript timed out for \(applicationName, privacy: .public)",
            )
            return .timedOut
        }

        if box.compileFailed {
            logger.error("Failed to compile AppleScript for \(applicationName, privacy: .public)")
            return .compileFailed
        }

        if let errorInfo = box.errorInfo {
            logAppleScriptError(errorInfo, logger: logger)
            return .runtimeFailed
        }

        guard let descriptor = box.descriptor else {
            return .runtimeFailed
        }

        return .success(descriptor)
    }

    private static var appleScriptTimeout: TimeInterval {
        0.75
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

private enum BoundedAppleScriptResult {
    case success(NSAppleEventDescriptor)
    case compileFailed
    case runtimeFailed
    case timedOut
}

/// Mutable box for cross-thread AppleScript completion (not Sendable by design).
private final class AppleScriptExecutionBox: @unchecked Sendable {
    var descriptor: NSAppleEventDescriptor?
    var errorInfo: NSDictionary?
    var compileFailed = false
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
