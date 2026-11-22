import AVFoundation
import Combine
import Foundation
import os.lock
@preconcurrency import ScreenCaptureKit
import Synchronization
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

enum SystemAudioRecoveryPolicy {
    static let maxAttempts = 3
    static let baseDelayMilliseconds = 250
    static let validationTimeout: TimeInterval = 4.0
    static let audiblePeakThreshold: Float = 0.001

    static func delay(forAttempt attempt: Int) -> Duration {
        .milliseconds(Int64(baseDelayMilliseconds * (1 << max(0, attempt - 1))))
    }

    static func bufferContainsSignal(_ buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData else {
            return true
        }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return false
        }
        for channel in 0 ..< channelCount {
            let samples = channelData[channel]
            for frame in 0 ..< frameCount where abs(samples[frame]) >= audiblePeakThreshold {
                return true
            }
        }
        return false
    }

    enum ValidationOutcome: Equatable {
        case noBuffers
        case silent
        case audible
    }

    static func classify(buffersReceived: Bool, signalReceived: Bool) -> ValidationOutcome {
        guard buffersReceived else {
            return .noBuffers
        }
        guard signalReceived else {
            return .silent
        }
        return .audible
    }
}

@MainActor
public class SystemAudioRecorder: ObservableObject, SystemAudioCaptureService {
    public static let shared = SystemAudioRecorder()

    @Published public private(set) var isRecording = false

    private var stream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?
    private var streamDelegate: SystemAudioCaptureDelegate?
    private var audioCaptureQueue: DispatchQueue?

    private var streamOutputHolder: Any?

    private class CallbackStorage: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock()
        private var _callback: (@Sendable (AVAudioPCMBuffer) -> Void)?

        var callback: (@Sendable (AVAudioPCMBuffer) -> Void)? {
            get { self.lock.withLock { self._callback } }
            set { self.lock.withLock { self._callback = newValue } }
        }
    }

    private let callbackStorage = CallbackStorage()

    public nonisolated var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? {
        get { self.callbackStorage.callback }
        set { self.callbackStorage.callback = newValue }
    }

    public func startCapture(sampleRate: Double = 48000.0) async throws {
        guard !isRecording else {
            AppLogger.info("Already recording system audio", category: .recordingManager)
            return
        }

        guard await hasPermission() else {
            throw SystemAudioRecorderError.permissionDenied
        }

        AppLogger.info("Starting system audio capture stream at \(sampleRate)Hz...", category: .recordingManager)
        currentSampleRate = sampleRate
        streamRecoveryAttempts = 0
        streamRecoveryTask?.cancel()
        streamRecoveryTask = nil
        activeStreamRecoveryID = nil
        try await startCaptureStream()
    }

    public func stopCapture() async {
        activeStreamRecoveryID = nil
        streamRecoveryTask?.cancel()
        streamRecoveryTask = nil
        guard isRecording else { return }
        isRecording = false

        AppLogger.info("Stopping system audio capture...", category: .recordingManager)

        validationTimer?.invalidate()
        validationTimer = nil

        if let stream {
            try? await stream.stopCapture()
        }

        await cleanup()
    }

    private var currentSampleRate: Double = 48000.0
    private let channelCount: Int = 2

    private let minVideoDimension = 2
    private let videoFrameRate = 1

    private var validationTimer: Timer?
    private let hasReceivedValidBuffer = Atomic<Bool>(false)
    private let hasReceivedAudibleBuffer = Atomic<Bool>(false)
    public var onRecordingError: (@Sendable (Error) -> Void)?
    private var streamRecoveryAttempts = 0
    private var streamRecoveryTask: Task<Void, Never>?
    private var activeStreamRecoveryID: UUID?

    private init() {}

    deinit {
        if let stream {
            Task { @MainActor [weak stream] in
                try? await stream?.stopCapture()
            }
        }
    }

    public func openSettings() {
        openScreenRecordingSettings()
    }

    public func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    public func getPermissionState() -> PermissionState {
        CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    }

    public func requestPermission() async {
        _ = try? await SCShareableContent.current
    }

    private let screenRecordingPrivacyURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")

    public func openScreenRecordingSettings() {
        if let url = screenRecordingPrivacyURL {
            NSWorkspace.shared.open(url)
        }
    }

    private func setupScreenCapture() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw SystemAudioRecorderError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(currentSampleRate)
        config.channelCount = channelCount

        config.width = minVideoDimension
        config.height = minVideoDimension
        config.minimumFrameInterval = CMTime(value: 1, timescale: Int32(videoFrameRate))

        let delegate = SystemAudioCaptureDelegate { [weak self] error in
            Task { @MainActor [weak self] in
                await self?.handleStreamFailure(error)
            }
        }
        streamDelegate = delegate
        stream = SCStream(filter: filter, configuration: config, delegate: delegate)

        let queue = DispatchQueue(label: "Verbi.systemAudioCapture", qos: .userInitiated)
        audioCaptureQueue = queue

        let output = SystemAudioStreamOutput(
            onBuffer: { @Sendable [weak self] buffer in
                self?.handleBuffer(buffer)
            }
        )
        streamOutput = output
        streamOutputHolder = output

        try stream?.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
    }

    private func startCaptureStream(recoveryID: UUID? = nil) async throws -> Bool {
        hasReceivedValidBuffer.store(false, ordering: .relaxed)
        hasReceivedAudibleBuffer.store(false, ordering: .relaxed)
        try await setupScreenCapture()

        if let recoveryID, activeStreamRecoveryID != recoveryID {
            await cleanup()
            return false
        }

        do {
            try await stream?.startCapture()
            if let recoveryID, activeStreamRecoveryID != recoveryID {
                await cleanup()
                return false
            }
            isRecording = true
            startValidationTimer()
            AppLogger.info("System audio capture started successfully", category: .recordingManager)
            return true
        } catch {
            AppLogger.error("Failed to start screen capture", category: .recordingManager, error: error)
            await cleanup()
            throw SystemAudioRecorderError.failedToStartCapture(error)
        }
    }

    private nonisolated func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        if !hasReceivedValidBuffer.load(ordering: .relaxed) {
            hasReceivedValidBuffer.store(true, ordering: .relaxed)
        }

        if !hasReceivedAudibleBuffer.load(ordering: .relaxed), SystemAudioRecoveryPolicy.bufferContainsSignal(buffer) {
            hasReceivedAudibleBuffer.store(true, ordering: .relaxed)
        }

        if let onAudioBuffer {
            onAudioBuffer(buffer)
        } else {
            AudioPCMBufferLeaseRegistry.shared.releaseIfNeeded(for: buffer)
        }
    }

    private func cleanup() async {
        if let activeStream = stream {
            try? await activeStream.stopCapture()
        }

        stream = nil
        streamOutput = nil
        streamDelegate = nil
        audioCaptureQueue = nil
        isRecording = false
        hasReceivedValidBuffer.store(false, ordering: .relaxed)
        hasReceivedAudibleBuffer.store(false, ordering: .relaxed)
    }

    private func handleStreamFailure(_ error: Error) async {
        guard isRecording else { return }

        let recoveryID = UUID()
        activeStreamRecoveryID = recoveryID
        validationTimer?.invalidate()
        validationTimer = nil
        await cleanup()

        guard activeStreamRecoveryID == recoveryID else { return }
        streamRecoveryTask?.cancel()
        streamRecoveryTask = Task { @MainActor [weak self] in
            await self?.runStreamRecovery(initialError: error, recoveryID: recoveryID)
        }
    }

    private func runStreamRecovery(initialError: Error, recoveryID: UUID) async {
        var lastError = initialError
        var attempt = 0

        while activeStreamRecoveryID == recoveryID, attempt < SystemAudioRecoveryPolicy.maxAttempts {
            attempt += 1
            streamRecoveryAttempts = attempt
            AppLogger.warning(
                "System audio capture stopped unexpectedly; retrying stream",
                category: .recordingManager,
                extra: ["attempt": attempt, "max": SystemAudioRecoveryPolicy.maxAttempts]
            )
            do {
                try await Task.sleep(for: SystemAudioRecoveryPolicy.delay(forAttempt: attempt))
            } catch {
                return
            }
            guard activeStreamRecoveryID == recoveryID else { return }
            do {
                let recovered = try await startCaptureStream(recoveryID: recoveryID)
                guard recovered, activeStreamRecoveryID == recoveryID else { return }
                activeStreamRecoveryID = nil
                AppLogger.info("System audio capture recovered after stream failure", category: .recordingManager)
                return
            } catch {
                lastError = error
                AppLogger.error("Failed to restart system audio capture", category: .recordingManager, error: error)
                await cleanup()
            }
        }

        guard activeStreamRecoveryID == recoveryID else { return }
        activeStreamRecoveryID = nil
        reportStreamFailure(lastError)
    }

    private func reportStreamFailure(_ error: Error) {
        AppLogger.error("System audio capture stopped unexpectedly", category: .recordingManager, error: error)
        onRecordingError?(SystemAudioRecorderError.streamStoppedUnexpectedly(error))
    }

    private func startValidationTimer() {
        validationTimer?.invalidate()
        let timeout = SystemAudioRecoveryPolicy.validationTimeout
        validationTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { @Sendable [weak self] _ in
            Task { @MainActor in
                await self?.handleValidationResult()
            }
        }
    }

    private func handleValidationResult() async {
        guard isRecording else { return }
        let buffersReceived = hasReceivedValidBuffer.load(ordering: .relaxed)
        let signalReceived = hasReceivedAudibleBuffer.load(ordering: .relaxed)
        switch SystemAudioRecoveryPolicy.classify(buffersReceived: buffersReceived, signalReceived: signalReceived) {
        case .audible:
            AppLogger.info("System audio validation successful", category: .recordingManager)
        case .silent:
            AppLogger.info("System audio validation successful; stream is delivering silence", category: .recordingManager)
        case .noBuffers:
            AppLogger.error("System audio validation failed - no buffers received", category: .recordingManager)
            await cleanup()
            reportValidationFailure()
        }
    }

    private func reportValidationFailure() {
        let failure = SystemAudioRecorderError.recordingValidationFailed
        error = failure
        onRecordingError?(failure)
    }
}

private class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void

    init(onBuffer: @escaping (@Sendable (AVAudioPCMBuffer) -> Void)) {
        self.onBuffer = onBuffer
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid, let buffer = createPCMBuffer(from: sampleBuffer) else { return }
        onBuffer(buffer)
    }

    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            return nil
        }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            AppLogger.error("Invalid audio format - sampleRate: \(format.sampleRate), channels: \(format.channelCount)", category: .recordingManager)
            return nil
        }
        let frames = AVAudioFrameCount(sampleBuffer.numSamples)

        guard frames > 0 else {
            return nil
        }

        let buffer = AudioPCMBufferPool.shared.checkout(format: format, frameCapacity: frames)
            ?? AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        guard let buffer else {
            return nil
        }
        buffer.frameLength = frames

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )

        guard status == noErr else {
            AudioPCMBufferPool.shared.release(buffer)
            AppLogger.error("CMSampleBufferCopyPCMDataIntoAudioBufferList failed with status: \(status)", category: .recordingManager)
            return nil
        }

        AudioPCMBufferLeaseRegistry.shared.register(buffer: buffer)

        return buffer
    }
}

public enum SystemAudioRecorderError: LocalizedError {
    case permissionDenied
    case noDisplayFound
    case invalidFormat
    case failedToStartCapture(Error)
    case streamStoppedUnexpectedly(Error)
    case recordingValidationFailed

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Permissão de gravação de tela negada. Habilite nas Preferências do Sistema."
        case .noDisplayFound:
            "Nenhuma tela encontrada para captura de áudio."
        case .invalidFormat:
            "Falha ao criar formato de áudio."
        case let .failedToStartCapture(error):
            "Falha ao iniciar captura de tela: \(error.localizedDescription)"
        case let .streamStoppedUnexpectedly(error):
            "A captura de áudio do sistema foi interrompida: \(error.localizedDescription)"
        case .recordingValidationFailed:
            "Gravação de áudio do sistema falhou - nenhum áudio válido recebido"
        }
    }
}

private final class SystemAudioCaptureDelegate: NSObject, SCStreamDelegate {
    private let onStopWithError: @Sendable (Error) -> Void

    init(onStopWithError: @escaping @Sendable (Error) -> Void) {
        self.onStopWithError = onStopWithError
    }

    func stream(_: SCStream, didStopWithError error: Error) {
        onStopWithError(error)
    }
}
