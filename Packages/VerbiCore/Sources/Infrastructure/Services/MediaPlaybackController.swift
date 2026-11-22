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
        MediaPlayerBridge(target: .music, applicationName: "Music", bundleIdentifier: "com.apple.Music"),
        MediaPlayerBridge(target: .spotify, applicationName: "Spotify", bundleIdentifier: "com.spotify.client")
    ]) {
        self.players = players
    }

    public func pausePlaybackIfNeeded() -> MediaPlaybackPauseOutcome {
        let logger = logger
        return Self.pauseFirstPlaying(players.map { player in { player.pauseIfPlaying(logger: logger) } })
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
            let outcome = MediaPlaybackController.pauseFirstPlaying(
                bridges.map { bridge in { bridge.pauseIfPlaying(logger: logger) } }
            )
            DispatchQueue.main.async {
                onComplete(outcome)
            }
        }
    }

    public func resumePlayback(from session: MediaPlaybackResumeSession) {
        guard let player = players.first(where: { $0.target == session.target }) else { return }
        player.resume(logger: logger)
    }

    private nonisolated static func pauseFirstPlaying(
        _ attempts: [() -> MediaPlaybackPlayerResult]
    ) -> MediaPlaybackPauseOutcome {
        var sawUnsupported = false
        var sawFailure = false

        for attempt in attempts {
            switch attempt() {
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

enum MediaPlaybackResumeCommand: Equatable {
    case play
    case playOnce

    init(target: MediaPlaybackTarget) {
        switch target {
        case .music:
            self = .playOnce
        case .spotify:
            self = .play
        }
    }

    var selector: Selector {
        switch self {
        case .play:
            #selector(ScriptableMediaApplication.play)
        case .playOnce:
            #selector(ScriptableMediaApplication.playOnce(_:))
        }
    }
}

struct MediaPlayerBridge: MediaPlaybackAutomating, Sendable {
    nonisolated static let automationPermissionDeniedErrorCode = -1743
    nonisolated static let playingPlayerStateCode: OSType = fourCharCode("kPSP")

    let target: MediaPlaybackTarget
    let applicationName: String
    let bundleIdentifier: String

    nonisolated var resumeCommand: MediaPlaybackResumeCommand {
        MediaPlaybackResumeCommand(target: target)
    }

    nonisolated func pauseIfPlaying(logger: Logger) -> MediaPlaybackPlayerResult {
        guard isApplicationRunning else { return .notRunning }

        guard let state = withApplication(logger: logger, { $0.playerState }).flatMap(\.self) else {
            return .failed
        }

        guard state == Self.playingPlayerStateCode else { return .notPlaying }

        guard send(#selector(ScriptableMediaApplication.pause), logger: logger, { $0.pause?() }) else {
            return .unsupported
        }

        logger.info("Paused media playback for recording: \(applicationName, privacy: .public)")
        return .paused(MediaPlaybackResumeSession(target: target))
    }

    nonisolated func resume(logger: Logger) {
        guard isApplicationRunning else { return }
        let command = resumeCommand
        let resumed = send(command.selector, logger: logger) { application in
            switch command {
            case .play:
                application.play?()
            case .playOnce:
                application.playOnce?(false)
            }
        }
        if !resumed {
            logger.warning("Unable to resume media playback after recording: \(applicationName, privacy: .public)")
        }
    }

    private nonisolated var isApplicationRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    private nonisolated func send(
        _ selector: Selector,
        logger: Logger,
        _ command: (ScriptableMediaApplication) -> Void
    ) -> Bool {
        let sent = withApplication(logger: logger) { application in
            guard application.responds(to: selector) else { return false }
            command(application)
            return true
        }
        return sent ?? false
    }

    private nonisolated func withApplication<Value>(
        logger: Logger,
        _ body: (ScriptableMediaApplication & NSObjectProtocol) -> Value
    ) -> Value? {
        guard let application = SBApplication(bundleIdentifier: bundleIdentifier) else { return nil }
        let capture = ScriptingErrorCapture()
        application.delegate = capture
        let value = body(application)
        if let error = capture.error {
            logScriptingError(error, logger: logger)
            return nil
        }
        return value
    }

    private nonisolated func logScriptingError(_ error: NSError, logger: Logger) {
        let message = error.localizedDescription
        if error.code == Self.automationPermissionDeniedErrorCode {
            logger.warning(
                "ScriptingBridge automation permission denied for \(applicationName, privacy: .public): \(message, privacy: .public)"
            )
        } else {
            logger.debug(
                "ScriptingBridge error for \(applicationName, privacy: .public) [\(error.code)]: \(message, privacy: .public)"
            )
        }
    }

    private nonisolated static func fourCharCode(_ string: String) -> OSType {
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
    @objc(playOnce:) optional func playOnce(_ once: Bool)
}

extension SBApplication: ScriptableMediaApplication {}

private final class ScriptingErrorCapture: NSObject, SBApplicationDelegate {
    var error: NSError?

    func eventDidFail(_: UnsafePointer<AppleEvent>, withError error: Error) -> Any? {
        self.error = error as NSError
        return nil
    }
}
