@preconcurrency import AVFoundation
import Foundation
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
public final class DictationRecorder: BaseAudioRecorder, AudioRecordingService {
    public static let shared = DictationRecorder()

    var microphoneCapture: (any MicrophoneCaptureSessionProtocol)?
    var makeMicrophoneCaptureSession: MicrophoneCaptureSessionFactory

    init(
        kernelProvider: AudioKernelProvider = .live,
        muteController: any OutputDuckingControlling = SystemAudioMuteController.shared,
        microphoneCaptureFactory: MicrophoneCaptureSessionFactory? = nil,
        mediaPlaybackController: any MediaPlaybackControlling = MediaPlaybackController.shared
    ) {
        makeMicrophoneCaptureSession = microphoneCaptureFactory ?? makeDefaultMicrophoneCaptureSession
        super.init(
            kernelProvider: kernelProvider,
            muteController: muteController,
            mediaPlaybackController: mediaPlaybackController
        )
        recordingRestarter = { [weak self] url, source, retryCount in
            guard let self else { throw CancellationError() }
            try await startRecording(to: url, source: source, retryCount: retryCount)
        }
    }

    override public func startRecording(to outputURL: URL, source: RecordingSource, retryCount: Int = 0) async throws {
        guard source == .microphone else {
            throw AudioRecorderError.unsupportedRecordingSource(source)
        }
        try await super.startRecording(to: outputURL, source: source, retryCount: retryCount)
    }

    override func performCaptureStart(to outputURL: URL, source _: RecordingSource, retryCount: Int, generation _: UInt64) async throws -> Bool {
        do {
            try await startMicrophoneCaptureRecording(to: outputURL, retryCount: retryCount)
        } catch {
            await cleanupAfterFailedStart()
            throw error
        }
        return true
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

    override func stopCaptureSource() async {
        if let capture = microphoneCapture {
            microphoneCapture = nil
            await capture.stop()
        }
    }

    override var hasPendingCaptureSourceResources: Bool {
        microphoneCapture != nil
    }
}
