import AppKit
@preconcurrency import AVFoundation
import Combine
import CoreAudio
import Foundation
import os.log
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public final class MeetingRecorder: BaseAudioRecorder, AudioRecordingService, MeetingRecordingService {
    public static let shared = MeetingRecorder()

    enum Constants {
        static let tapBufferSize: AVAudioFrameCount = 2048
        static let tapBusNumber: AVAudioNodeBus = 0
        static let outputSampleRate: Double = 48000.0
        static let outputChannels: AVAudioChannelCount = 2
        static let inputDeviceRecoveryDebounce: Duration = .milliseconds(250)
        #if DEBUG
            static let micDiagnosticsEnabled = true
        #else
            static let micDiagnosticsEnabled = false
        #endif
        static let defaultInputPropagationTimeout: Duration = .seconds(1)
        static let retriableEngineStartErrorCodes: Set<Int> = [-10875, -10877]
    }

    var audioEngine: AVAudioEngine?
    var mixerNode: AVAudioMixerNode?
    var systemAudioSourceNode: AVAudioSourceNode?
    var microphoneMixingDestination: AVAudioMixingDestination?

    var injectedEngine: AVAudioEngine?

    let systemRecorder = SystemAudioRecorder.shared
    nonisolated let systemAudioQueue = AudioBufferQueue(capacity: 200)
    nonisolated let partialBufferState = PartialBufferState()

    var micDiagnosticsTimer: Timer?
    var isMicDiagnosticsTapInstalled = false
    let micDiagnosticsPeakBits = MicDiagnosticsPeakStorage()
    var micProbeWorker: AudioRecordingWorker?
    var micProbeStopTask: Task<Void, Never>?
    var micRecorderProbe: AVAudioRecorder?
    var micRecorderProbeStopTask: Task<Void, Never>?
    private var settingsSubscriptions = Set<AnyCancellable>()
    var inputDeviceRecoveryTask: Task<Void, Never>?
    var isRecoveringInputDevice = false

    override var defaultRecordingSource: RecordingSource {
        .all
    }

    override init(
        kernelProvider: AudioKernelProvider = .live,
        muteController: any OutputDuckingControlling = SystemAudioMuteController.shared,
        mediaPlaybackController: any MediaPlaybackControlling = MediaPlaybackController.shared
    ) {
        super.init(
            kernelProvider: kernelProvider,
            muteController: muteController,
            mediaPlaybackController: mediaPlaybackController
        )
        recordingRestarter = { [weak self] url, source, retryCount in
            guard let self else { throw CancellationError() }
            try await startRecording(to: url, source: source, retryCount: retryCount)
        }

        deviceManager.$availableInputDevices
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] devices in
                self?.scheduleInputDeviceRecoveryIfNeeded(for: devices)
            }
            .store(in: &settingsSubscriptions)

        let queue = systemAudioQueue
        systemRecorder.onAudioBuffer = { @Sendable buffer in
            queue.enqueue(buffer)
        }
        systemRecorder.onRecordingError = { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                AppLogger.error(
                    "System audio recorder failed during active session",
                    category: .recordingManager,
                    error: error
                )
                self.error = error
                if let onRecordingError {
                    onRecordingError(error)
                } else if isRecording {
                    _ = await stopRecording()
                }
            }
        }
    }

    override public func startRecording(to outputURL: URL, source: RecordingSource, retryCount: Int = 0) async throws {
        try await super.startRecording(to: outputURL, source: source, retryCount: retryCount)
    }

    override func performCaptureStart(to outputURL: URL, source: RecordingSource, retryCount: Int, generation: UInt64) async throws -> Bool {
        let (engine, targetSampleRate) = prepareEngineForRecording(source: source)

        do {
            try await setupGraphAndStart(
                engine: engine,
                writingTo: outputURL,
                source: source,
                retryCount: retryCount,
                sampleRate: targetSampleRate
            )

            if source == .system || source == .all {
                AppLogger.debug("Starting system recorder...", category: .recordingManager)
                try await systemRecorder.startCapture(sampleRate: targetSampleRate)
                try ensureCaptureGeneration(generation)
            } else {
                AppLogger.debug("Skipping system recorder start (source: \(source.rawValue))", category: .recordingManager)
            }
        } catch {
            await cleanupAfterFailedStart()
            if shouldRetryStartup(after: error, source: source, retryCount: retryCount) {
                let code = startupErrorCode(from: error) ?? 0
                AppLogger.warning(
                    "Retrying recording start after transient engine failure",
                    category: .recordingManager,
                    extra: ["code": code, "attempt": retryCount + 1, "max": BaseAudioRecorder.Constants.maxRetries]
                )
                try await Task.sleep(for: BaseAudioRecorder.Constants.retryDelay)
                try ensureCaptureGeneration(generation)
                try await startRecording(to: outputURL, source: source, retryCount: retryCount + 1)
                return false
            }
            throw error
        }
        return true
    }

    override func prepareForNewRecordingAttempt() {
        inputDeviceRecoveryTask?.cancel()
        isRecoveringInputDevice = false
    }

    public func setMeetingMicrophoneEnabled(_ isEnabled: Bool) {
        microphoneMixingDestination?.volume = isEnabled ? 1.0 : 0.0
    }

    override func prepareCaptureSource() {
        setMeetingMicrophoneEnabled(true)
    }

    override func stopCaptureSource() async {
        await systemRecorder.stopCapture()
        cleanupEngine()
    }

    override func finishCaptureFinalization(_ url: URL?) -> URL? {
        let queueStats = systemAudioQueue.stats
        if queueStats.dropped > 0 {
            AppLogger.warning(
                "System audio frames dropped during session",
                category: .recordingManager,
                extra: ["droppedFrames": queueStats.dropped, "buffersRemaining": queueStats.count]
            )
        }

        systemAudioQueue.clear()
        partialBufferState.clear()

        if let url {
            verifyFileIntegrity(url: url)
        }

        return url
    }

    override var hasPendingCaptureSourceResources: Bool {
        audioEngine != nil
            || mixerNode != nil
            || systemAudioSourceNode != nil
    }

    override func clearCaptureSourceBuffers() {
        systemAudioQueue.clear()
        partialBufferState.clear()
    }

    override func cancelCaptureSourceRecovery() {
        inputDeviceRecoveryTask?.cancel()
        inputDeviceRecoveryTask = nil
        isRecoveringInputDevice = false
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

    func startupErrorCode(from error: Error) -> Int? {
        if case let AudioRecorderError.failedToStartEngine(innerError) = error {
            return (innerError as NSError).code
        }

        return (error as NSError).code
    }

    func shouldRetryStartup(after error: Error, source _: RecordingSource, retryCount: Int) -> Bool {
        guard retryCount < BaseAudioRecorder.Constants.maxRetries, let code = startupErrorCode(from: error) else { return false }
        return Constants.retriableEngineStartErrorCodes.contains(code)
    }
}
