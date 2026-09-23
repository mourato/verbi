import AppKit
@preconcurrency import AVFoundation
import Combine
import CoreAudio
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.log

// MARK: - Audio Recorder (Merged Mic + System)

/// Recorder that merges Microphone (InputNode) and System Audio (ScreenCaptureKit)
/// into a single AAC (.m4a) file using AVAudioEngine's Mixer.
@MainActor
public class AudioRecorder: ObservableObject, AudioRecordingService {
    public static let shared = AudioRecorder()

    // MARK: - Constants

    enum Constants {
        static let tapBufferSize: AVAudioFrameCount = 2048
        static let tapBusNumber: AVAudioNodeBus = 0
        static let outputSampleRate: Double = 48000.0
        static let outputChannels: AVAudioChannelCount = 2
        static let validationInterval: TimeInterval = 1.5
        static let retryDelay: UInt64 = 500_000_000 // 500ms
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
        static let outputMuteDelayAfterStart: UInt64 = 200_000_000 // 200ms
        static let retriableEngineStartErrorCodes: Set<Int> = [-10875, -10877]
    }

    @Published public internal(set) var isRecording = false
    public var isRecordingPublisher: AnyPublisher<Bool, Never> {
        $isRecording.eraseToAnyPublisher()
    }

    @Published public internal(set) var currentRecordingURL: URL?
    @Published public internal(set) var error: Error?
    @Published public internal(set) var currentAveragePower: Float = -160.0
    @Published public internal(set) var currentPeakPower: Float = -160.0
    @Published public internal(set) var currentBarPowerLevels: [Float] = []
    @Published var latestMeterSnapshot: AudioRecordingWorker.MeterSnapshot?

    // MARK: - Audio Engine

    var audioEngine: AVAudioEngine?
    var mixerNode: AVAudioMixerNode?
    var systemAudioSourceNode: AVAudioSourceNode?
    var microphoneMixingDestination: AVAudioMixingDestination?

    /// Simple recorder for mic-only recordings. Bypasses AVAudioEngine and its
    /// aggregate device, which can malfunction on macOS with USB microphones.
    var simpleRecorder: AVAudioRecorder?
    private var simpleMeterTimer: Timer?

    // MARK: - Dependency Injection for Testing

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

    // MARK: - System Audio Integration

    let systemRecorder = SystemAudioRecorder.shared
    /// Non-isolated to allow background threads (SystemAudioRecorder) to enqueue without MainActor hopping
    nonisolated let systemAudioQueue = AudioBufferQueue(capacity: 200)
    /// Tracks partially consumed buffers between render cycles to prevent frame loss
    nonisolated let partialBufferState = PartialBufferState()

    // MARK: - Worker & State

    /// Thread-safe worker that handles file writing and processing off the main actor.
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
    private var fallbackMeterTimer: Timer?
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

        // Setup worker callbacks to bridge back to MainActor
        worker.setOnPowerUpdate { [weak self] avg, peak, barPowerLevels in
            Task { @MainActor [weak self] in
                self?.publishMeterSnapshot(
                    averagePower: avg,
                    peakPower: peak,
                    barPowerLevels: barPowerLevels
                )
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

        AppSettingsStore.shared.$recordingIndicatorStyle
            .removeDuplicates()
            .sink { [weak self] style in
                self?.worker.setMeteringBarCount(Self.waveformBarCount(for: style))
            }
            .store(in: &settingsSubscriptions)

        deviceManager.$availableInputDevices
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] devices in
                self?.scheduleInputDeviceRecoveryIfNeeded(for: devices)
            }
            .store(in: &settingsSubscriptions)

        worker.setMeteringBarCount(Self.waveformBarCount(for: AppSettingsStore.shared.recordingIndicatorStyle))

        // Link System Recorder to Queue
        // Capture queue directly to avoid 'self' (MainActor) capture in background thread
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

    // MARK: - Public API

    /// Start recording audio to the specified URL. (Protocol Conformance)
    /// Defaults to .all sources.
    public func startRecording(to outputURL: URL, retryCount: Int) async throws {
        try await startRecording(to: outputURL, source: .all, retryCount: retryCount)
    }

    /// Start recording merged audio (Mic + System) to the specified URL.
    /// - Parameters:
    ///   - outputURL: The destination URL for the audio file.
    ///   - source: The audio source to record.
    ///   - retryCount: Number of retries attempted so far.
    public func startRecording(to outputURL: URL, source: RecordingSource, retryCount: Int = 0) async throws {
        // Invalidate validation callbacks from any previous attempt before its teardown can yield.
        activeValidationSessionID = UUID()
        // Stop any existing recording first
        await stopRecording()
        inputDeviceRecoveryTask?.cancel()
        isRecoveringInputDevice = false
        activeRecordingSource = nil
        try prepareRecordingAttempt(outputURL: outputURL, source: source)

        let (engine, targetSampleRate) = prepareEngineForRecording(source: source)

        do {
            // For mic-only recordings, use AVAudioRecorder directly.
            // AVAudioEngine creates an internal aggregate device on macOS when input
            // and output devices differ, which can malfunction with USB microphones
            // (zero-filled buffers, reconfig loops). AVAudioRecorder uses a simple
            // I/O path without aggregate devices — proven to capture audio correctly.
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

            // Start ScreenCaptureKit after AVAudioEngine is stable.
            // This avoids a race where SCStream activation can transiently invalidate
            // output hardware format during engine initialization (-10875/-10877).
            if source == .system || source == .all {
                AppLogger.debug("Starting system recorder...", category: .recordingManager)
                try await systemRecorder.startRecording(to: outputURL, sampleRate: targetSampleRate)
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
                try await startRecording(to: outputURL, source: source, retryCount: retryCount + 1)
                return
            }
            throw error
        }
    }

    // MARK: - Simple Mic Recording (AVAudioRecorder)

    /// Start a mic-only recording using AVAudioRecorder directly.
    /// This bypasses AVAudioEngine and avoids the internal aggregate device
    /// that malfunctions on macOS with USB microphones.
    private func startSimpleMicRecording(to outputURL: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

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

        // Periodic metering for UI power updates
        simpleMeterTimer = Timer.scheduledTimer(withTimeInterval: Constants.simpleMeterUpdateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let rec = simpleRecorder else { return }
                rec.updateMeters()
                publishMeterSnapshot(
                    averagePower: rec.averagePower(forChannel: 0),
                    peakPower: rec.peakPower(forChannel: 0),
                    barPowerLevels: []
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

    /// Stop recording and finalize the audio file.
    @discardableResult
    public func stopRecording() async -> URL? {
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

        // Cancel validation timer
        validationTimer?.invalidate()
        validationTimer = nil

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

        // Stop Engine & System Capture
        _ = await systemRecorder.stopRecording()
        cleanupEngine()

        // Restore audio output if we muted it
        restoreOutputInterruptionIfNeeded()

        // Finalize worker - wait for all buffers to be processed
        let url = await worker.stop()

        // Reset state
        resetRecordingStateAfterStop()

        // Log dropped frames before clearing (for diagnostics)
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
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Constants.fallbackSampleRate,
            AVNumberOfChannelsKey: Constants.fallbackChannels,
            AVEncoderBitRateKey: Constants.fallbackBitRate
        ]

        let recorder = try AVAudioRecorder(url: outputURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()
        fallbackRecorder = recorder
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

    func stopFallbackRecorder(_ recorder: AVAudioRecorder) {
        fallbackMeterTimer?.invalidate()
        fallbackMeterTimer = nil
        lastMeterSnapshotDate = nil
        latestMeterSnapshot = nil

        recorder.stop()
        fallbackRecorder = nil

        AppLogger.info("Fallback mic recorder stopped", category: .recordingManager, extra: ["path": recorder.url.path])
    }

    @MainActor
    private func updateFallbackMeters() {
        guard let recorder = fallbackRecorder else { return }
        recorder.updateMeters()
        publishMeterSnapshot(
            averagePower: recorder.averagePower(forChannel: 0),
            peakPower: recorder.peakPower(forChannel: 0),
            barPowerLevels: []
        )
    }

    @MainActor
    func publishMeterSnapshot(
        averagePower: Float,
        peakPower: Float,
        barPowerLevels: [Float]
    ) {
        currentAveragePower = averagePower
        currentPeakPower = peakPower
        currentBarPowerLevels = barPowerLevels

        let now = Date()
        let deltaTime = if let lastMeterSnapshotDate {
            max(0.001, now.timeIntervalSince(lastMeterSnapshotDate))
        } else {
            Constants.simpleMeterUpdateInterval
        }
        lastMeterSnapshotDate = now
        latestMeterSnapshot = AudioRecordingWorker.MeterSnapshot(
            averagePowerDB: averagePower,
            peakPowerDB: peakPower,
            barPowerDBLevels: barPowerLevels,
            deltaTime: deltaTime
        )
    }

    static func waveformBarCount(for style: RecordingIndicatorStyle) -> Int {
        switch style {
        case .classic:
            18
        case .mini:
            9
        case .super:
            80
        case .none:
            0
        }
    }

    // MARK: - Permission Checking

    public func hasPermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public func getPermissionState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        @unknown default: return .notDetermined
        }
    }

    public func requestPermission() async {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
