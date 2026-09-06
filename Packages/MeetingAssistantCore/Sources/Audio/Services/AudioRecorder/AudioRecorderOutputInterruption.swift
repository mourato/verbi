@preconcurrency import AVFoundation
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

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

extension AudioRecorder {
    public func setMeetingMicrophoneEnabled(_ isEnabled: Bool) {
        microphoneMixingDestination?.volume = isEnabled ? 1.0 : 0.0
    }

    func prepareEngineForRecording(source: RecordingSource) -> (AVAudioEngine, Double) {
        let engine = injectedEngine ?? AVAudioEngine()
        audioEngine = engine

        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        AppLogger.info(
            "Output node format",
            category: .recordingManager,
            extra: [
                "sampleRate": outputFormat.sampleRate,
                "channels": outputFormat.channelCount,
                "commonFormat": outputFormat.commonFormat.rawValue,
            ],
        )

        if outputFormat.sampleRate <= 0 || outputFormat.channelCount == 0 {
            AppLogger.fault(
                "Output device has invalid hardware format — audio capture will fail",
                category: .recordingManager,
                extra: [
                    "sampleRate": outputFormat.sampleRate,
                    "channels": outputFormat.channelCount,
                ],
            )
        }

        let targetSampleRate = resolveTargetSampleRate(engine: engine, source: source)
        AppLogger.info("Resolved target sample rate: \(targetSampleRate)", category: .recordingManager)
        return (engine, targetSampleRate)
    }

    func prepareRecordingAttempt(outputURL: URL, source: RecordingSource) throws {
        resetOutputInterruptionState()

        AppLogger.info(
            "Starting recording",
            category: .recordingManager,
            extra: ["path": outputURL.path, "source": source.rawValue],
        )
        activeRecordingSource = source
        lastMeterSnapshotDate = nil
        latestMeterSnapshot = nil
        currentBarPowerLevels = []
        let settings = AppSettingsStore.shared

        prepareOutputInterruptionIfNeeded(source: source, settings: settings)
        setMeetingMicrophoneEnabled(true)
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
            try? await Task.sleep(nanoseconds: Constants.outputMuteDelayAfterStart)
            guard let self, isRecording else { return }
            applyOutputMuteIfNeeded()
        }
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
                extra: ["error": error.localizedDescription],
            )
        }
    }

    private func prepareOutputInterruptionIfNeeded(source: RecordingSource, settings: AppSettingsStore) {
        guard source == .microphone else { return }

        let configuredDuckingLevelPercent = AppSettingsStore.clampedAudioDuckingLevelPercent(
            settings.audioDuckingLevelPercent,
        )

        switch settings.recordingMediaHandlingMode {
        case .none:
            return
        case .pauseMedia:
            // ponytail: best-effort async pause; never block start on AppleScript; no duck fallback while awaiting
            scheduleMediaPauseOffCriticalPath()
        case .duckAudio:
            let plan = Self.makeOutputInterruptionPlan(
                mode: .duckAudio,
                mediaPauseOutcome: .noActivePlayback,
                duckingLevelPercent: configuredDuckingLevelPercent,
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
                extra: ["deviceID": outID, "deviceName": deviceManager.getDeviceName(for: outID) ?? "Unknown"],
            )
            return
        }

        outputMuteSession = muteController.prepareOutputMuteSession()
        outputDuckingLevelPercent = configuredDuckingLevelPercent
    }

    static func makeOutputInterruptionPlan(
        mode: AppSettingsStore.RecordingMediaHandlingMode,
        mediaPauseOutcome: MediaPlaybackPauseOutcome,
        duckingLevelPercent: Int,
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

    func cleanupEngine() {
        if let mixer = mixerNode {
            mixer.removeTap(onBus: 0)
        }

        mixerNode = nil
        systemAudioSourceNode = nil
        microphoneMixingDestination = nil

        if let engine = audioEngine {
            stopMicDiagnostics(for: engine.inputNode)
            if engine.isRunning {
                engine.stop()
            }
            engine.reset()
            audioEngine = nil
        }
    }

    func resetRecordingStateAfterStop() {
        isRecording = false
        currentRecordingURL = nil
        currentAveragePower = -160.0
        currentPeakPower = -160.0
        currentBarPowerLevels = []
        latestMeterSnapshot = nil
        lastMeterSnapshotDate = nil
    }

    var shouldUseRealtimeMicrophonePipeline: Bool {
        onMixedAudioBuffer != nil
    }

    var hasPendingStartupResources: Bool {
        audioEngine != nil
            || mixerNode != nil
            || systemAudioSourceNode != nil
            || currentRecordingURL != nil
            || fallbackRecorder != nil
    }

    func cleanupAfterFailedStart() async {
        validationTimer?.invalidate()
        validationTimer = nil

        if let recorder = fallbackRecorder {
            stopFallbackRecorder(recorder)
        }

        _ = await systemRecorder.stopRecording()
        cleanupEngine()
        _ = await worker.stop()
        systemAudioQueue.clear()
        partialBufferState.clear()

        restoreOutputInterruptionIfNeeded()
        isRecording = false
        activeRecordingSource = nil
        inputDeviceRecoveryTask?.cancel()
        inputDeviceRecoveryTask = nil
        isRecoveringInputDevice = false
        currentRecordingURL = nil
        currentAveragePower = -160.0
        currentPeakPower = -160.0
        currentBarPowerLevels = []
        latestMeterSnapshot = nil
        lastMeterSnapshotDate = nil
    }

    func startupErrorCode(from error: Error) -> Int? {
        if case let AudioRecorderError.failedToStartEngine(innerError) = error {
            return (innerError as NSError).code
        }

        return (error as NSError).code
    }

    func shouldRetryStartup(after error: Error, source _: RecordingSource, retryCount: Int) -> Bool {
        guard retryCount < Constants.maxRetries else { return false }
        guard let code = startupErrorCode(from: error) else { return false }
        return Constants.retriableEngineStartErrorCodes.contains(code)
    }
}
