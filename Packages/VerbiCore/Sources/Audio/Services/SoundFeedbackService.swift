import AppKit
import AVFoundation
import Foundation
import VerbiCoreCommon
import VerbiCoreInfrastructure

protocol SoundFeedbackPlaybackEngine: AnyObject, Sendable {
    func play(resourceName: String, volume: Float)
    func playPairedPreview(startResourceName: String, stopResourceName: String, volume: Float)
    func cancelPendingPreview()
}

private final class AVAudioPlayerSoundFeedbackEngine: SoundFeedbackPlaybackEngine, @unchecked Sendable {
    private static let pairedPreviewGapSeconds: TimeInterval = 0.15

    private let playbackQueue = DispatchQueue(
        label: "com.mourato.verbi.sound-feedback",
        qos: .userInteractive
    )
    private let resourceURLProvider: @Sendable (String) -> URL?
    private var players: [String: AVAudioPlayer] = [:]
    private var pendingPreviewStop: DispatchWorkItem?

    init(resourceURLProvider: @escaping @Sendable (String) -> URL? = SoundFeedbackService.resourceURL(for:)) {
        self.resourceURLProvider = resourceURLProvider
    }

    func play(resourceName: String, volume: Float) {
        let clampedVolume = SoundFeedbackCue.clampedVolume(volume)
        guard let url = resourceURLProvider(resourceName) else {
            AppLogger.warning(
                "Missing bundled sound feedback asset",
                category: .general,
                extra: ["resourceName": resourceName]
            )
            return
        }

        playbackQueue.async { [weak self] in
            guard let self else { return }
            cancelPendingPreviewOnQueue()
            _ = playOnQueue(resourceName: resourceName, url: url, volume: clampedVolume)
        }
    }

    func playPairedPreview(startResourceName: String, stopResourceName: String, volume: Float) {
        let clampedVolume = SoundFeedbackCue.clampedVolume(volume)
        guard let startURL = resourceURLProvider(startResourceName),
              let stopURL = resourceURLProvider(stopResourceName)
        else {
            AppLogger.warning(
                "Missing bundled sound feedback preview asset",
                category: .general,
                extra: [
                    "startResourceName": startResourceName,
                    "stopResourceName": stopResourceName
                ]
            )
            return
        }

        playbackQueue.async { [weak self] in
            guard let self else { return }
            cancelPendingPreviewOnQueue()

            guard let startDuration = playOnQueue(
                resourceName: startResourceName,
                url: startURL,
                volume: clampedVolume
            ) else {
                return
            }

            let stopWorkItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                pendingPreviewStop = nil
                _ = playOnQueue(resourceName: stopResourceName, url: stopURL, volume: clampedVolume)
            }
            pendingPreviewStop = stopWorkItem
            playbackQueue.asyncAfter(
                deadline: .now() + startDuration + Self.pairedPreviewGapSeconds,
                execute: stopWorkItem
            )
        }
    }

    func cancelPendingPreview() {
        playbackQueue.async { [weak self] in
            self?.cancelPendingPreviewOnQueue()
        }
    }

    private func cancelPendingPreviewOnQueue() {
        pendingPreviewStop?.cancel()
        pendingPreviewStop = nil
    }

    private func playOnQueue(resourceName: String, url: URL, volume: Float) -> TimeInterval? {
        do {
            let player: AVAudioPlayer
            if let cached = players[resourceName] {
                player = cached
            } else {
                player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[resourceName] = player
            }

            player.currentTime = 0
            player.volume = volume
            player.play()
            return player.duration
        } catch {
            AppLogger.warning(
                "Failed to play bundled sound feedback asset",
                category: .general,
                extra: [
                    "resourceName": resourceName,
                    "error": error.localizedDescription
                ]
            )
            return nil
        }
    }
}

@MainActor
public final class SoundFeedbackService {
    public static let shared = SoundFeedbackService()

    private let settings: AppSettingsStore
    private let playbackEngine: any SoundFeedbackPlaybackEngine
    private let systemSoundHandler: ((SoundFeedbackSound, Float) -> Void)?
    private var currentSystemSound: NSSound?

    private convenience init() {
        self.init(settings: .shared, playbackEngine: AVAudioPlayerSoundFeedbackEngine())
    }

    init(
        settings: AppSettingsStore,
        playbackEngine: any SoundFeedbackPlaybackEngine,
        systemSoundHandler: ((SoundFeedbackSound, Float) -> Void)? = nil
    ) {
        self.settings = settings
        self.playbackEngine = playbackEngine
        self.systemSoundHandler = systemSoundHandler
    }

    public nonisolated static func resourceURL(for resourceName: String) -> URL? {
        Bundle.module.url(forResource: resourceName, withExtension: "m4a")
            ?? Bundle.module.url(forResource: resourceName, withExtension: "m4a", subdirectory: "Sounds")
    }

    public func playRecordingStartSound() {
        playbackEngine.cancelPendingPreview()
        guard settings.soundFeedbackEnabled else { return }
        playbackEngine.play(
            resourceName: settings.soundFeedbackCue.startResourceName,
            volume: settings.soundFeedbackVolume
        )
    }

    public func playRecordingStopSound() {
        playbackEngine.cancelPendingPreview()
        guard settings.soundFeedbackEnabled else { return }
        playbackEngine.play(
            resourceName: settings.soundFeedbackCue.stopResourceName,
            volume: settings.soundFeedbackVolume
        )
    }

    public func playRecordingCancelledSound() {
        playbackEngine.cancelPendingPreview()
        guard settings.soundFeedbackEnabled else { return }
        let volume = SoundFeedbackCue.clampedVolume(settings.soundFeedbackVolume)
        if let systemSoundHandler {
            systemSoundHandler(.basso, volume)
        } else {
            playSystemSound(.basso, volume: volume)
        }
    }

    public func preview(_ cue: SoundFeedbackCue) {
        playbackEngine.playPairedPreview(
            startResourceName: cue.startResourceName,
            stopResourceName: cue.stopResourceName,
            volume: settings.soundFeedbackVolume
        )
    }

    public func previewAtVolume(_ volume: Float, cue: SoundFeedbackCue? = nil) {
        let resolvedCue = cue ?? settings.soundFeedbackCue
        playbackEngine.play(
            resourceName: resolvedCue.startResourceName,
            volume: SoundFeedbackCue.clampedVolume(volume)
        )
    }

    private func playSystemSound(_ sound: SoundFeedbackSound, volume: Float) {
        guard let soundName = sound.systemSoundName else { return }

        if let nsSound = NSSound(named: NSSound.Name(soundName)) {
            currentSystemSound?.stop()
            nsSound.volume = SoundFeedbackCue.clampedVolume(volume)
            currentSystemSound = nsSound
            currentSystemSound?.play()
        } else {
            AppLogger.warning(
                "Failed to load system sound",
                category: .general,
                extra: ["soundName": soundName]
            )
        }
    }
}
