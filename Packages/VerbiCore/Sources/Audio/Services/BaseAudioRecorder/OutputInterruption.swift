@preconcurrency import AVFoundation
import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
protocol OutputDuckingControlling {
    func prepareOutputMuteSession() -> SystemAudioMuteController.OutputMuteSession?
    func applyDucking(to session: inout SystemAudioMuteController.OutputMuteSession, levelPercent: Int) throws
    func restoreOutputState(from session: SystemAudioMuteController.OutputMuteSession)
}

extension SystemAudioMuteController: OutputDuckingControlling {}

enum OutputInterruptionPlan: Equatable {
    case none
    case pause(MediaPlaybackResumeSession)
    case duck(Int)
}

extension BaseAudioRecorder {
    func prepareRecordingAttempt(outputURL: URL, source: RecordingSource) throws {
        resetOutputInterruptionState()

        AppLogger.info(
            "Starting recording",
            category: .recordingManager,
            extra: ["path": outputURL.path, "source": source.rawValue]
        )
        activeRecordingSource = source
        lastMeterSnapshotDate = nil
        latestMeterSnapshot = nil
        let settings = AppSettingsStore.shared

        prepareOutputInterruptionIfNeeded(source: source, settings: settings)
        prepareCaptureSource()
        applyMicrophoneBoostIfNeeded(settings: settings, source: source)
        try validateRecordingPermissionIfNeeded(source: source)
    }

    func restoreOutputInterruptionIfNeeded() {
        outputMuteTask?.cancel()
        outputMuteTask = nil

        if let pausedMediaSession {
            self.pausedMediaSession = nil
            mediaPlaybackController.resumePlayback(from: pausedMediaSession)
        }

        guard let session = outputMuteSession else {
            outputDuckingLevelPercent = nil
            return
        }

        outputMuteSession = nil
        outputDuckingLevelPercent = nil
        muteController.restoreOutputState(from: session)
    }

    func resetOutputInterruptionState() {
        outputMuteTask?.cancel()
        outputMuteTask = nil
        outputMuteSession = nil
        pausedMediaSession = nil
        outputDuckingLevelPercent = nil
    }

    func scheduleOutputMuteIfNeeded() {
        guard outputMuteSession != nil, outputDuckingLevelPercent != nil else { return }

        outputMuteTask?.cancel()
        outputMuteTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Constants.outputMuteDelayAfterStart)
            guard let self, isRecording else { return }
            applyOutputMuteIfNeeded()
        }
    }

    func increaseDefaultMicrophoneInputVolumeIfPossible() {
        guard deviceManager.setDefaultInputVolumeToMaximum() else {
            AppLogger.debug(
                "Unable to set default microphone input volume to maximum (property not available or not settable).",
                category: .recordingManager
            )
            return
        }

        AppLogger.info(
            "Default microphone input volume set to maximum at recording start.",
            category: .recordingManager
        )
    }

    private func applyMicrophoneBoostIfNeeded(settings: AppSettingsStore, source: RecordingSource) {
        let shouldBoostMicInputVolume = settings.autoIncreaseMicrophoneVolume
            && settings.useSystemDefaultInput
            && (source == .microphone || source == .all)
        if shouldBoostMicInputVolume {
            increaseDefaultMicrophoneInputVolumeIfPossible()
        }
    }

    private func validateRecordingPermissionIfNeeded(source: RecordingSource) throws {
        guard source == .microphone || source == .all else { return }
        if let microphonePermissionValidator {
            try microphonePermissionValidator()
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            AppLogger.error("Microphone permission denied. Cannot start recording.", category: .recordingManager)
            restoreOutputInterruptionIfNeeded()
            throw AudioRecorderError.permissionDenied
        }
    }

    private func applyOutputMuteIfNeeded() {
        guard var session = outputMuteSession, let duckingLevelPercent = outputDuckingLevelPercent else { return }

        do {
            try muteController.applyDucking(to: &session, levelPercent: duckingLevelPercent)
            outputMuteSession = session
        } catch {
            AppLogger.warning(
                "Failed to apply system audio ducking",
                category: .recordingManager,
                extra: ["error": error.localizedDescription]
            )
        }
    }

    private func prepareOutputInterruptionIfNeeded(source: RecordingSource, settings: AppSettingsStore) {
        guard source == .microphone else { return }

        let configuredDuckingLevelPercent = AppSettingsStore.clampedAudioDuckingLevelPercent(
            settings.audioDuckingLevelPercent
        )

        switch settings.recordingMediaHandlingMode {
        case .none:
            return
        case .pauseMedia:
            scheduleMediaPauseOffCriticalPath()
        case .duckAudio:
            let plan = Self.makeOutputInterruptionPlan(
                mode: .duckAudio,
                mediaPauseOutcome: .noActivePlayback,
                duckingLevelPercent: configuredDuckingLevelPercent
            )
            if case let .duck(levelPercent) = plan {
                prepareOutputDuckingIfNeeded(configuredDuckingLevelPercent: levelPercent)
            }
        }
    }

    private func scheduleMediaPauseOffCriticalPath() {
        mediaPlaybackController.schedulePausePlaybackIfNeeded { [weak self] outcome in
            guard let self else { return }
            if case let .paused(session) = outcome {
                pausedMediaSession = session
            }
        }
    }

    private func prepareOutputDuckingIfNeeded(configuredDuckingLevelPercent: Int) {
        if let outID = deviceManager.getDefaultOutputDeviceID(),
           let inID = deviceManager.getDefaultInputDeviceIDRaw(),
           outID == inID
        {
            AppLogger.warning(
                "Skipping output ducking: output device is the same as input device",
                category: .recordingManager,
                extra: ["deviceID": outID, "deviceName": deviceManager.getDeviceName(for: outID) ?? "Unknown"]
            )
            return
        }

        outputMuteSession = muteController.prepareOutputMuteSession()
        outputDuckingLevelPercent = configuredDuckingLevelPercent
    }

    static func makeOutputInterruptionPlan(
        mode: AppSettingsStore.RecordingMediaHandlingMode,
        mediaPauseOutcome: MediaPlaybackPauseOutcome,
        duckingLevelPercent: Int
    ) -> OutputInterruptionPlan {
        switch mode {
        case .none:
            return .none
        case .duckAudio:
            guard duckingLevelPercent < 100 else { return .none }
            return .duck(duckingLevelPercent)
        case .pauseMedia:
            if case let .paused(session) = mediaPauseOutcome {
                return .pause(session)
            }

            guard duckingLevelPercent < 100 else { return .none }
            return .duck(duckingLevelPercent)
        }
    }

    func resetRecordingStateAfterStop() {
        isRecording = false
        currentRecordingURL = nil
        activeMicrophoneDeviceName = nil
        activeMicrophoneDidFallBackToDefault = false
        currentAveragePower = -160.0
        currentPeakPower = -160.0
        latestMeterSnapshot = nil
        lastMeterSnapshotDate = nil
    }
}
