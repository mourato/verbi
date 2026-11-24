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
        static let meterUpdateInterval: TimeInterval = 0.05
        static let outputMuteDelayAfterStart: UInt64 = 200_000_000
        static let defaultInputPropagationTimeout: Duration = .seconds(1)
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
    @Published public internal(set) var activeMicrophoneDeviceName: String?
    @Published public internal(set) var activeMicrophoneDidFallBackToDefault = false
    @Published var latestMeterSnapshot: AudioRecordingWorker.MeterSnapshot?

    var audioEngine: AVAudioEngine?
    var mixerNode: AVAudioMixerNode?
    var systemAudioSourceNode: AVAudioSourceNode?
    var microphoneMixingDestination: AVAudioMixingDestination?

    var microphoneCapture: (any MicrophoneCaptureSessionProtocol)?
    var makeMicrophoneCaptureSession: MicrophoneCaptureSessionFactory = makeDefaultMicrophoneCaptureSession
    var validationInterval: TimeInterval = Constants.validationInterval
    var microphonePermissionValidator: (() throws -> Void)?

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
        microphoneCaptureFactory: MicrophoneCaptureSessionFactory? = nil,
        mediaPlaybackController: any MediaPlaybackControlling = MediaPlaybackController.shared
    ) {
        worker = AudioRecordingWorker(energyMeterKernel: kernelProvider.makeEnergyMeterKernel())
        self.muteController = muteController
        self.mediaPlaybackController = mediaPlaybackController
        makeMicrophoneCaptureSession = microphoneCaptureFactory ?? makeDefaultMicrophoneCaptureSession
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

        if source == .microphone {
            try await startMicrophoneCapture(to: outputURL, retryCount: retryCount, generation: generation)
            return
        }

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

    private func startMicrophoneCapture(to outputURL: URL, retryCount: Int, generation: UInt64) async throws {
        do {
            try await startMicrophoneCaptureRecording(to: outputURL, retryCount: retryCount)
            try ensureCaptureGeneration(generation)
        } catch {
            await cleanupAfterFailedStart()
            throw error
        }
        scheduleOutputMuteIfNeeded()
    }

    func startMicrophoneCaptureRecording(to outputURL: URL, retryCount: Int) async throws {
        let worker = worker
        let capture = try makeMicrophoneCaptureSession(
            { buffer in worker.process(buffer) },
            { [weak self] error in
                Task { @MainActor in self?.handleMicrophoneCaptureFailure(error) }
            }
        )
        try await worker.start(
            writingTo: outputURL,
            format: capture.format,
            fileFormat: AppSettingsStore.shared.audioFormat
        )
        microphoneCapture = capture
        do {
            try await startMicrophoneCaptureSession(capture, preferredUID: preferredMicrophoneCaptureUID())
        } catch {
            throw AudioRecorderError.failedToStartEngine(error)
        }
        currentRecordingURL = outputURL
        isRecording = true
        AppLogger.info("Microphone capture session started", category: .recordingManager)
        startValidationTimer(url: outputURL, source: .microphone, retryCount: retryCount)
    }

    private func handleMicrophoneCaptureFailure(_ error: Error) {
        guard microphoneCapture != nil else { return }
        AppLogger.error("Microphone capture session failed", category: .recordingManager, error: error)
        let failure = AudioRecorderError.microphoneCaptureInterrupted(error)
        self.error = failure
        if let onRecordingError {
            onRecordingError(failure)
        } else {
            Task { _ = await stopRecording() }
        }
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
            microphoneCapture = nil
            await capture.stop()
            restoreOutputInterruptionIfNeeded()
            let url = await worker.stop()
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

    @MainActor
    func publishMeterSnapshot(averagePower: Float, peakPower: Float, spectrum: [Float] = []) {
        currentAveragePower = averagePower
        currentPeakPower = peakPower

        let now = Date()
        let deltaTime = if let lastMeterSnapshotDate {
            max(0.001, now.timeIntervalSince(lastMeterSnapshotDate))
        } else {
            Constants.meterUpdateInterval
        }
        lastMeterSnapshotDate = now
        latestMeterSnapshot = AudioRecordingWorker.MeterSnapshot(averagePowerDB: averagePower, peakPowerDB: peakPower, deltaTime: deltaTime, spectrum: spectrum)
    }
}
