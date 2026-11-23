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
public class AudioRecorder: ObservableObject, AudioRecordingService {
    public static let shared = AudioRecorder()

    enum Constants {
        static let tapBufferSize: AVAudioFrameCount = 2048
        static let tapBusNumber: AVAudioNodeBus = 0
        static let outputSampleRate: Double = 48000.0
        static let outputChannels: AVAudioChannelCount = 2
        static let validationInterval: TimeInterval = 4.0
        static let retryDelay: UInt64 = 500_000_000
        static let inputDeviceRecoveryDebounce: UInt64 = 250_000_000
        static let maxRetries = 2
        #if DEBUG
            static let micDiagnosticsEnabled = true
        #else
            static let micDiagnosticsEnabled = false
        #endif
        static let fallbackSampleRate: Double = 48000.0
        static let fallbackChannels: Int = 1
        static let fallbackBitRate: Int = 128_000
        static let fallbackMeterUpdateInterval: TimeInterval = 0.05
        static let fallbackMeterTimerToleranceRatio: Double = 0.25
        static let simpleMeterUpdateInterval: TimeInterval = 0.05
        static let outputMuteDelayAfterStart: UInt64 = 200_000_000
        static let retriableEngineStartErrorCodes: Set<Int> = [-10875, -10877]
    }

    @Published public internal(set) var isRecording = false

    @Published var restartingCaptureURL: URL?

    var captureGeneration: UInt64 = 0

    public var isRecordingPublisher: AnyPublisher<Bool, Never> {
        $isRecording
            .combineLatest($restartingCaptureURL)
            .map { isRecording, restartingCaptureURL in isRecording || restartingCaptureURL != nil }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @Published public internal(set) var currentRecordingURL: URL?
    @Published public internal(set) var error: Error?
    @Published public internal(set) var currentAveragePower: Float = -160.0
    @Published public internal(set) var currentPeakPower: Float = -160.0
    @Published var latestMeterSnapshot: AudioRecordingWorker.MeterSnapshot?

    var audioEngine: AVAudioEngine?
    var mixerNode: AVAudioMixerNode?
    var systemAudioSourceNode: AVAudioSourceNode?
    var microphoneMixingDestination: AVAudioMixingDestination?

    var simpleRecorder: AVAudioRecorder?
    var microphoneCapture: MicrophoneCaptureSession?
    private var simpleMeterTimer: Timer?
    private var simpleSpectrumTap: MicrophoneSpectrumTap?

    var injectedEngine: AVAudioEngine?

    private final class MixedBufferCallbackStorage: @unchecked Sendable {
        private let lock = NSLock()
        private var callback: (@Sendable (AVAudioPCMBuffer) -> Void)?

        func get() -> (@Sendable (AVAudioPCMBuffer) -> Void)? {
            lock.lock()
            defer { lock.unlock() }
            return callback
        }

        func set(_ callback: (@Sendable (AVAudioPCMBuffer) -> Void)?) {
            lock.lock()
            self.callback = callback
            lock.unlock()
        }
    }

    let systemRecorder = SystemAudioRecorder.shared
    nonisolated let systemAudioQueue = AudioBufferQueue(capacity: 200)
    nonisolated let partialBufferState = PartialBufferState()

    let worker: AudioRecordingWorker
    var validationTimer: Timer?
    public var onRecordingError: (@Sendable (Error) -> Void)?

    let muteController: any OutputDuckingControlling
    let mediaPlaybackController: any MediaPlaybackControlling
    var outputMuteSession: SystemAudioMuteController.OutputMuteSession?
    var pausedMediaSession: MediaPlaybackResumeSession?
    var outputDuckingLevelPercent: Int?
    var outputMuteTask: Task<Void, Never>?
    let deviceManager = AudioDeviceManager()
    let microphoneInputSelectionResolver: MicrophoneInputSelectionResolver
    var micDiagnosticsTimer: Timer?
    var isMicDiagnosticsTapInstalled = false
    let micDiagnosticsPeakBits = MicDiagnosticsPeakStorage()
    var micProbeWorker: AudioRecordingWorker?
    var micProbeStopTask: Task<Void, Never>?
    var micRecorderProbe: AVAudioRecorder?
    var micRecorderProbeStopTask: Task<Void, Never>?
    var fallbackRecorder: AVAudioRecorder?
    var fallbackMeterTimer: Timer?
    private var settingsSubscriptions = Set<AnyCancellable>()
    var lastMeterSnapshotDate: Date?
    var activeValidationSessionID: UUID?
    private let mixedBufferCallbackStorage = MixedBufferCallbackStorage()
    var activeRecordingSource: RecordingSource?
    var inputDeviceRecoveryTask: Task<Void, Never>?
    var isRecoveringInputDevice = false

    public nonisolated var onMixedAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? {
        get { mixedBufferCallbackStorage.get() }
        set { mixedBufferCallbackStorage.set(newValue) }
    }

    init(
        kernelProvider: AudioKernelProvider = .live,
        muteController: any OutputDuckingControlling = SystemAudioMuteController.shared,
        mediaPlaybackController: any MediaPlaybackControlling = MediaPlaybackController.shared
    ) {
        worker = AudioRecordingWorker(energyMeterKernel: kernelProvider.makeEnergyMeterKernel())
        self.muteController = muteController
        self.mediaPlaybackController = mediaPlaybackController
        microphoneInputSelectionResolver = MicrophoneInputSelectionResolver(deviceManager: deviceManager)

        worker.setOnPowerUpdate { [weak self] avg, peak, spectrum in
            Task { @MainActor [weak self] in
                self?.publishMeterSnapshot(averagePower: avg, peakPower: peak, spectrum: spectrum)
            }
        }

        worker.setOnError { [weak self] error in
            Task { @MainActor [weak self] in
                self?.handleWorkerError(error)
            }
        }

        let mixedBufferCallbackStorage = mixedBufferCallbackStorage
        worker.setOnProcessedBuffer { buffer in
            mixedBufferCallbackStorage.get()?(buffer)
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

    public func startRecording(to outputURL: URL, retryCount: Int) async throws {
        try await startRecording(to: outputURL, source: .all, retryCount: retryCount)
    }

    public func startRecording(to outputURL: URL, source: RecordingSource, retryCount: Int = 0) async throws {
        let generation = captureGeneration
        activeValidationSessionID = UUID()
        await finalizeCapture()
        inputDeviceRecoveryTask?.cancel()
        isRecoveringInputDevice = false
        activeRecordingSource = nil
        try prepareRecordingAttempt(outputURL: outputURL, source: source)

        if source == .microphone, shouldUseRealtimeMicrophonePipeline {
            try await startMicrophoneCaptureRecording(to: outputURL, retryCount: retryCount)
            try ensureCaptureGeneration(generation)
            scheduleOutputMuteIfNeeded()
            return
        }

        let (engine, targetSampleRate) = prepareEngineForRecording(source: source)

        do {
            if source == .microphone, !shouldUseRealtimeMicrophonePipeline {
                try await startSimpleMicRecording(to: outputURL)
                scheduleOutputMuteIfNeeded()
                return
            }

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

            scheduleOutputMuteIfNeeded()

        } catch {
            await cleanupAfterFailedStart()
            if shouldRetryStartup(after: error, source: source, retryCount: retryCount) {
                let code = startupErrorCode(from: error) ?? 0
                AppLogger.warning(
                    "Retrying recording start after transient engine failure",
                    category: .recordingManager,
                    extra: ["code": code, "attempt": retryCount + 1, "max": Constants.maxRetries]
                )
                try await Task.sleep(nanoseconds: Constants.retryDelay)
                try ensureCaptureGeneration(generation)
                try await startRecording(to: outputURL, source: source, retryCount: retryCount + 1)
                return
            }
            throw error
        }
    }

    private func startMicrophoneCaptureRecording(to outputURL: URL, retryCount: Int) async throws {
        let worker = worker
        let capture = try MicrophoneCaptureSession { buffer in
            worker.process(buffer)
        }
        try await worker.start(
            writingTo: outputURL,
            format: capture.format,
            fileFormat: AppSettingsStore.shared.audioFormat
        )
        do {
            try capture.start(deviceUID: preferredMicrophoneCaptureUID())
        } catch {
            _ = await worker.stop()
            throw AudioRecorderError.failedToStartEngine(error)
        }
        microphoneCapture = capture
        currentRecordingURL = outputURL
        isRecording = true
        AppLogger.info("Microphone capture session started", category: .recordingManager)
        startValidationTimer(url: outputURL, source: .microphone, retryCount: retryCount)
    }

    private func preferredMicrophoneCaptureUID() -> String? {
        guard !AppSettingsStore.shared.useSystemDefaultInput,
              let deviceID = microphoneInputSelectionResolver.resolveCustomMicrophoneDeviceID()
        else { return nil }
        return deviceManager.getDeviceUID(for: deviceID)
    }

    private func startSimpleMicRecording(to outputURL: URL) throws {
        let settings = Self.recorderSettings(
            for: outputURL,
            sampleRate: 48000,
            channels: 1,
            aacSettings: [AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue]
        )

        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            throw AudioRecorderError.failedToStartEngine(NSError(
                domain: "AudioRecorder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "AVAudioRecorder failed to start"]
            ))
        }

        simpleRecorder = recorder
        currentRecordingURL = outputURL
        isRecording = true

        simpleSpectrumTap = MicrophoneSpectrumTap()
        simpleSpectrumTap?.start()

        simpleMeterTimer = Timer.scheduledTimer(withTimeInterval: Constants.simpleMeterUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let rec = simpleRecorder else { return }
                rec.updateMeters()
                publishMeterSnapshot(
                    averagePower: rec.averagePower(forChannel: 0),
                    peakPower: rec.peakPower(forChannel: 0),
                    spectrum: simpleSpectrumTap?.latestLevels ?? []
                )
            }
        }

        AppLogger.info(
            "Simple mic recording started (AVAudioRecorder)",
            category: .recordingManager,
            extra: ["path": outputURL.path]
        )
    }

    private func stopSimpleMicRecording() -> URL? {
        simpleMeterTimer?.invalidate()
        simpleMeterTimer = nil
        simpleSpectrumTap?.stop()
        simpleSpectrumTap = nil
        lastMeterSnapshotDate = nil
        latestMeterSnapshot = nil

        guard let recorder = simpleRecorder else { return nil }
        simpleRecorder = nil

        recorder.stop()

        let url = recorder.url
        AppLogger.info(
            "Simple mic recording stopped",
            category: .recordingManager,
            extra: ["path": url.path, "duration": recorder.currentTime]
        )
        return url
    }

    @discardableResult
    public func stopRecording() async -> URL? {
        let restartingURL = restartingCaptureURL
        captureGeneration &+= 1
        activeValidationSessionID = UUID()
        restartingCaptureURL = nil
        let url = await finalizeCapture()
        return url ?? restartingURL
    }

    func ensureCaptureGeneration(_ generation: UInt64) throws {
        guard captureGeneration == generation else { throw CancellationError() }
    }

    @discardableResult
    func finalizeCapture() async -> URL? {
        inputDeviceRecoveryTask?.cancel()
        inputDeviceRecoveryTask = nil
        activeRecordingSource = nil
        isRecoveringInputDevice = false

        guard isRecording else {
            if hasPendingStartupResources {
                await cleanupAfterFailedStart()
            }
            return currentRecordingURL
        }

        AppLogger.info("Stopping recording...", category: .recordingManager)

        validationTimer?.invalidate()
        validationTimer = nil

        if let capture = microphoneCapture {
            capture.stop()
            microphoneCapture = nil
            restoreOutputInterruptionIfNeeded()
            let url = await worker.stop()
            resetRecordingStateAfterStop()
            return url
        }

        if simpleRecorder != nil {
            let url = stopSimpleMicRecording() ?? currentRecordingURL
            cleanupEngine()
            restoreOutputInterruptionIfNeeded()
            resetRecordingStateAfterStop()
            return url
        }

        if let recorder = fallbackRecorder {
            let url = currentRecordingURL
            stopFallbackRecorder(recorder)
            cleanupEngine()
            restoreOutputInterruptionIfNeeded()
            resetRecordingStateAfterStop()
            return url
        }

        await systemRecorder.stopCapture()
        cleanupEngine()

        restoreOutputInterruptionIfNeeded()

        let url = await worker.stop()

        resetRecordingStateAfterStop()

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

    func startFallbackRecorder(to outputURL: URL) throws {
        let settings = Self.recorderSettings(
            for: outputURL,
            sampleRate: Constants.fallbackSampleRate,
            channels: Constants.fallbackChannels,
            aacSettings: [AVEncoderBitRateKey: Constants.fallbackBitRate]
        )

        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()
        fallbackRecorder = recorder
        currentRecordingURL = outputURL
        isRecording = true

        fallbackMeterTimer?.invalidate()
        fallbackMeterTimer = Timer.scheduledTimer(withTimeInterval: Constants.fallbackMeterUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateFallbackMeters()
            }
        }
        fallbackMeterTimer?.tolerance = Constants.fallbackMeterUpdateInterval * Constants.fallbackMeterTimerToleranceRatio

        AppLogger.info("Fallback mic recorder started", category: .recordingManager, extra: ["path": outputURL.path])
    }

    @MainActor
    func publishMeterSnapshot(averagePower: Float, peakPower: Float, spectrum: [Float] = []) {
        currentAveragePower = averagePower
        currentPeakPower = peakPower

        let now = Date()
        let deltaTime = if let lastMeterSnapshotDate {
            max(0.001, now.timeIntervalSince(lastMeterSnapshotDate))
        } else {
            Constants.simpleMeterUpdateInterval
        }
        lastMeterSnapshotDate = now
        latestMeterSnapshot = AudioRecordingWorker.MeterSnapshot(averagePowerDB: averagePower, peakPowerDB: peakPower, deltaTime: deltaTime, spectrum: spectrum)
    }
}
