import Atomics
import AVFoundation
import Combine
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.lock
@preconcurrency import ScreenCaptureKit

// MARK: - System Audio Recorder (Screen Capture Stream)

/// Captures system audio using ScreenCaptureKit and streams buffers via callback.
/// Does NOT write to file directly. Utilized by `AudioRecorder` for mixing.
@MainActor
public class SystemAudioRecorder: ObservableObject, AudioRecordingService {
    public static let shared = SystemAudioRecorder()

    @Published public private(set) var isRecording = false
    public var isRecordingPublisher: AnyPublisher<Bool, Never> {
        $isRecording.eraseToAnyPublisher()
    }

    // Legacy properties maintained for protocol conformance, but not used for file writing
    @Published public private(set) var currentRecordingURL: URL?
    @Published public private(set) var error: Error?

    // MARK: - SCStream

    private var stream: SCStream?
    private var streamOutput: SystemAudioStreamOutput?
    private var streamDelegate: SystemAudioCaptureDelegate?
    private var audioCaptureQueue: DispatchQueue?

    // MARK: - Streaming Output

    /// Strong reference to prevent premature deallocation during capture
    private var streamOutputHolder: Any?

    // MARK: - Public API

    // Callback for received audio buffers (Thread-safe, called on background queue)

    /// Thread-safe storage for the audio buffer callback
    private class CallbackStorage: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock()
        private var _callback: (@Sendable (AVAudioPCMBuffer) -> Void)?

        var callback: (@Sendable (AVAudioPCMBuffer) -> Void)? {
            get { self.lock.withLock { self._callback } }
            set { self.lock.withLock { self._callback = newValue } }
        }
    }

    private let callbackStorage = CallbackStorage()

    /// Callback for received audio buffers (Thread-safe, called on background queue)
    public nonisolated var onAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)? {
        get { self.callbackStorage.callback }
        set { self.callbackStorage.callback = newValue }
    }

    // MARK: - Protocol Conformance

    public func startRecording(to outputURL: URL, retryCount: Int) async throws {
        try await startRecording(to: outputURL, sampleRate: 48000.0, retryCount: retryCount)
    }

    // MARK: - Configuration

    private var currentSampleRate: Double = 48000.0 // Configurable per recording session
    private let channelCount: Int = 2 // Stereo capture for system audio

    private let minVideoDimension = 2
    private let videoFrameRate = 1

    // MARK: - Validation

    private var validationTimer: Timer?
    private let hasReceivedValidBuffer = ManagedAtomic<Bool>(false)
    public var onRecordingError: (@Sendable (Error) -> Void)?

    private init() {}

    deinit {
        if let stream {
            Task { @MainActor [weak stream] in
                try? await stream?.stopCapture()
            }
        }
    }

    // MARK: - Public API

    /// Starts system audio capture.
    /// `outputURL` is ignored as this class no longer writes files, but kept for protocol conformance.
    public func startRecording(to _: URL, sampleRate: Double = 48000.0, retryCount _: Int = 0) async throws {
        guard !isRecording else {
            AppLogger.info("Already recording system audio", category: .recordingManager)
            return
        }

        guard await hasPermission() else {
            throw SystemAudioRecorderError.permissionDenied
        }

        AppLogger.info("Starting system audio capture stream at \(sampleRate)Hz...", category: .recordingManager)
        currentSampleRate = sampleRate
        hasReceivedValidBuffer.store(false, ordering: .relaxed)

        try await setupScreenCapture()

        do {
            try await stream?.startCapture()
            isRecording = true
            startValidationTimer()
            AppLogger.info("System audio capture started successfully", category: .recordingManager)
        } catch {
            AppLogger.error("Failed to start screen capture", category: .recordingManager, error: error)
            await cleanup()
            throw SystemAudioRecorderError.failedToStartCapture(error)
        }
    }

    public func stopRecording() async -> URL? {
        guard isRecording else { return nil }

        AppLogger.info("Stopping system audio capture...", category: .recordingManager)

        validationTimer?.invalidate()
        validationTimer = nil

        if let stream {
            try? await stream.stopCapture()
        }

        await cleanup()
        return nil // No file produced by this class directly
    }

    public func openSettings() {
        openScreenRecordingSettings()
    }

    // MARK: - Permission Checking

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

    // MARK: - Private Methods

    private func setupScreenCapture() async throws {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw SystemAudioRecorderError.noDisplayFound
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()

        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true // Essential to avoid feedback loop if we play back
        config.sampleRate = Int(currentSampleRate)
        config.channelCount = channelCount

        // Minimal video
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

        let queue = DispatchQueue(label: "MeetingAssistant.systemAudioCapture", qos: .userInitiated)
        audioCaptureQueue = queue

        let output = SystemAudioStreamOutput(
            onBuffer: { @Sendable [weak self] buffer in
                self?.handleBuffer(buffer)
            }
        )
        streamOutput = output
        streamOutputHolder = output // Keep strong reference to prevent deallocation

        try stream?.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)
    }

    private nonisolated func handleBuffer(_ buffer: AVAudioPCMBuffer) {
        // Mark validation
        if !hasReceivedValidBuffer.load(ordering: .relaxed) {
            hasReceivedValidBuffer.store(true, ordering: .relaxed)
        }

        // Forward buffer to listener directly on capture queue
        // This avoids Main Thread overhead for high-frequency audio buffers
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
    }

    private func handleStreamFailure(_ error: Error) async {
        guard isRecording else { return }

        AppLogger.error(
            "System audio capture stopped unexpectedly",
            category: .recordingManager,
            error: error
        )
        self.error = error
        onRecordingError?(SystemAudioRecorderError.streamStoppedUnexpectedly(error))
        validationTimer?.invalidate()
        validationTimer = nil
        await cleanup()
    }

    private func startValidationTimer() {
        validationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { @Sendable [weak self] _ in
            Task { @MainActor in
                await self?.handleValidationResult()
            }
        }
    }

    private func handleValidationResult() {
        let validationPassed = hasReceivedValidBuffer.load(ordering: .relaxed)
        if !validationPassed {
            AppLogger.warning("System audio validation failed - no valid buffers received", category: .recordingManager)
            // We don't fail hard here for now, as system audio might just be silent,
            // but for diagnosis it is useful.
        } else {
            AppLogger.info("System audio validation successful", category: .recordingManager)
        }
    }
}

// MARK: - Stream Output Handler

private class SystemAudioStreamOutput: NSObject, SCStreamOutput {
    /// private let logger: Logger // Removed unused
    private let onBuffer: @Sendable (AVAudioPCMBuffer) -> Void

    init(onBuffer: @escaping (@Sendable (AVAudioPCMBuffer) -> Void)) {
        // self.logger = logger
        self.onBuffer = onBuffer
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }

        guard let buffer = createPCMBuffer(from: sampleBuffer) else { return }
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

// MARK: - Errors

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
