@preconcurrency import AVFoundation
import Combine
import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public class BaseAudioRecorder: ObservableObject {
    enum Constants {
        static let validationInterval: TimeInterval = 4.0
        static let retryDelay: Duration = .milliseconds(500)
        static let maxRetries = 2
        static let meterUpdateInterval: TimeInterval = 0.05
        static let outputMuteDelayAfterStart: Duration = .milliseconds(200)
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

    var validationInterval: TimeInterval = Constants.validationInterval
    var microphonePermissionValidator: (() throws -> Void)?

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
    var lastMeterSnapshotDate: Date?
    var activeValidationSessionID: UUID?
    var activeRecordingSource: RecordingSource?
    var recordingRestarter: (@MainActor (URL, RecordingSource, Int) async throws -> Void)?

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

    private let mixedBufferCallbackStorage = MixedBufferCallbackStorage()

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
    }

    var defaultRecordingSource: RecordingSource {
        .microphone
    }

    public func startRecording(to outputURL: URL, retryCount: Int) async throws {
        try await startRecording(to: outputURL, source: defaultRecordingSource, retryCount: retryCount)
    }

    func startRecording(to outputURL: URL, source: RecordingSource, retryCount: Int) async throws {
        let generation = captureGeneration
        activeValidationSessionID = UUID()
        await finalizeCapture()
        prepareForNewRecordingAttempt()
        activeRecordingSource = nil
        try prepareRecordingAttempt(outputURL: outputURL, source: source)
        let shouldScheduleOutputInterruption = try await performCaptureStart(to: outputURL, source: source, retryCount: retryCount, generation: generation)
        try ensureCaptureGeneration(generation)
        if shouldScheduleOutputInterruption {
            scheduleOutputMuteIfNeeded()
        }
    }

    func performCaptureStart(to _: URL, source: RecordingSource, retryCount _: Int, generation _: UInt64) async throws -> Bool {
        await Task.yield()
        throw AudioRecorderError.unsupportedRecordingSource(source)
    }

    func prepareForNewRecordingAttempt() {}

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
        cancelCaptureSourceRecovery()
        activeRecordingSource = nil

        guard isRecording else {
            if hasPendingStartupResources {
                await cleanupAfterFailedStart()
            }
            return currentRecordingURL
        }

        AppLogger.info("Stopping recording...", category: .recordingManager)

        validationTimer?.invalidate()
        validationTimer = nil

        await stopCaptureSource()
        restoreOutputInterruptionIfNeeded()

        let url = await worker.stop()

        resetRecordingStateAfterStop()

        return finishCaptureFinalization(url)
    }

    func stopCaptureSource() async {
        await Task.yield()
    }

    func finishCaptureFinalization(_ url: URL?) -> URL? {
        url
    }

    var hasPendingCaptureSourceResources: Bool {
        false
    }

    var hasPendingStartupResources: Bool {
        currentRecordingURL != nil || hasPendingCaptureSourceResources
    }

    func cleanupAfterFailedStart() async {
        validationTimer?.invalidate()
        validationTimer = nil

        await stopCaptureSource()
        _ = await worker.stop()
        clearCaptureSourceBuffers()

        restoreOutputInterruptionIfNeeded()
        resetStateAfterFailedStart()
    }

    func clearCaptureSourceBuffers() {}

    func cancelCaptureSourceRecovery() {}

    func prepareCaptureSource() {}

    func resetStateAfterFailedStart() {
        isRecording = false
        activeRecordingSource = nil
        cancelCaptureSourceRecovery()
        currentRecordingURL = nil
        currentAveragePower = -160.0
        currentPeakPower = -160.0
        latestMeterSnapshot = nil
        lastMeterSnapshotDate = nil
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
