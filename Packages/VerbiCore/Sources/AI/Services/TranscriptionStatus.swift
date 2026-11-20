import Foundation
import VerbiCoreCommon
import VerbiCoreDomain

@MainActor
public class TranscriptionStatus: ObservableObject {
    @Published public private(set) var serviceState: ServiceState = .unknown
    @Published public private(set) var modelState: ModelState = .unloaded
    @Published public private(set) var device: String = "unknown"

    public enum State: Equatable {
        case idle
        case preparing
        case processing(progress: Double)
        case postProcessing(progress: Double)
        case completed
        case failed(TranscriptionStatusError)
    }

    @Published public private(set) var phase: TranscriptionPhase = .idle
    @Published public private(set) var progressPercentage: Double = 0.0
    @Published public private(set) var currentStatus: State = .idle
    @Published public private(set) var estimatedTimeRemaining: TimeInterval?
    @Published public private(set) var audioDurationSeconds: Double?
    @Published public private(set) var processedDurationSeconds: Double = 0.0
    @Published public private(set) var livePreviewText: String = ""

    @Published public private(set) var lastError: TranscriptionStatusError?
    @Published public private(set) var lastErrorTime: Date?

    @Published public private(set) var transcriptionStartTime: Date?
    @Published public private(set) var lastHealthCheck: Date?

    public init() {}

    public var statusMessage: String {
        switch (serviceState, modelState, phase) {
        case (.disconnected, _, _):
            "transcription.status.disconnected".localized
        case (.connecting, _, _):
            "transcription.status.connecting".localized
        case (.error, _, _):
            lastError?.localizedDescription ?? "transcription.status.connection_error".localized
        case (.connected, .downloading, _):
            "transcription.status.downloading_model".localized
        case (.connected, .loading, _):
            "transcription.status.loading_model".localized
        case (.connected, .error, _):
            "transcription.status.model_load_error".localized
        case (.connected, .unloaded, _):
            "transcription.status.model_not_loaded".localized
        case (.connected, .loaded, .idle):
            "transcription.status.ready".localized
        case (.connected, .loaded, .preparing):
            "transcription.status.preparing_audio".localized
        case (.connected, .loaded, .processing):
            formattedProgress
        case (.connected, .loaded, .postProcessing):
            "transcription.status.processing_result".localized
        case (.connected, .loaded, .completed):
            "transcription.status.completed".localized
        case (.connected, .loaded, .failed):
            lastError?.localizedDescription ?? "transcription.status.failed".localized
        default:
            "transcription.status.unknown".localized
        }
    }

    private var formattedProgress: String {
        if let estimated = estimatedTimeRemaining, estimated > 0 {
            return "transcription.status.transcribing_progress_remaining".localized(
                with: Int(progressPercentage),
                TimeFormatter.format(estimated)
            )
        } else if progressPercentage > 0 {
            return "transcription.status.transcribing_progress".localized(with: Int(progressPercentage))
        }
        return "transcription.status.transcribing_audio".localized
    }

    public var isReady: Bool {
        serviceState == .connected && modelState == .loaded && phase == .idle
    }

    public var isProcessing: Bool {
        [.preparing, .processing, .postProcessing].contains(phase)
    }

    public var hasBlockingError: Bool {
        serviceState == .error || serviceState == .disconnected || modelState == .error
    }

    public func updateServiceState(_ state: ServiceState) {
        serviceState = state
        if state == .connected {
            lastHealthCheck = Date()
        }
    }

    public func updateModelState(_ state: ModelState, device: String? = nil) {
        modelState = state
        if let device {
            self.device = device
        }
    }

    public func beginTranscription(audioDuration: Double?) {
        phase = .preparing
        currentStatus = .preparing
        progressPercentage = 0.0
        estimatedTimeRemaining = nil
        audioDurationSeconds = audioDuration
        processedDurationSeconds = 0.0
        transcriptionStartTime = Date()
        lastError = nil
        livePreviewText = ""
    }

    public func updateProgress(
        phase: TranscriptionPhase,
        percentage: Double? = nil,
        processedSeconds: Double? = nil
    ) {
        self.phase = phase

        if let percentage {
            progressPercentage = min(max(percentage, 0.0), 100.0)
        }

        switch phase {
        case .preparing:
            currentStatus = .preparing
        case .processing:
            currentStatus = .processing(progress: progressPercentage)
        case .postProcessing:
            currentStatus = .postProcessing(progress: progressPercentage)
        case .completed:
            currentStatus = .completed
        default:
            break
        }

        if let processed = processedSeconds {
            processedDurationSeconds = processed
            calculateEstimatedTime()
        }
    }

    public func completeTranscription(success: Bool) {
        phase = success ? .completed : .failed
        progressPercentage = success ? 100.0 : progressPercentage
        currentStatus = success ? .completed : (lastError != nil ? .failed(lastError!) : .idle)
        estimatedTimeRemaining = nil
        transcriptionStartTime = nil
    }

    public func resetToIdle() {
        phase = .idle
        currentStatus = .idle
        progressPercentage = 0.0
        estimatedTimeRemaining = nil
        audioDurationSeconds = nil
        processedDurationSeconds = 0.0
        transcriptionStartTime = nil
        livePreviewText = ""
    }

    public func recordError(_ error: TranscriptionStatusError) {
        lastError = error
        lastErrorTime = Date()
        currentStatus = .failed(error)

        switch error {
        case .serviceUnavailable, .connectionFailed:
            serviceState = .disconnected
        case .modelLoadFailed:
            modelState = .error
        case .transcriptionFailed:
            phase = .failed
        }
    }

    public func clearError() {
        lastError = nil
        lastErrorTime = nil
    }

    public func updateLivePreviewText(_ text: String) {
        livePreviewText = text
    }

    private func calculateEstimatedTime() {
        guard let startTime = transcriptionStartTime,
              let audioDuration = audioDurationSeconds,
              processedDurationSeconds > 0
        else {
            estimatedTimeRemaining = nil
            return
        }

        let elapsed = Date().timeIntervalSince(startTime)
        let processingSpeed = processedDurationSeconds / elapsed

        guard processingSpeed > 0 else {
            estimatedTimeRemaining = nil
            return
        }

        let remainingAudio = audioDuration - processedDurationSeconds
        estimatedTimeRemaining = remainingAudio / processingSpeed

        progressPercentage = (processedDurationSeconds / audioDuration) * 100.0
    }
}

public enum TranscriptionStatusError: LocalizedError, Equatable {
    case serviceUnavailable
    case connectionFailed(String)
    case modelLoadFailed(String)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            "Serviço de transcrição indisponível"
        case let .connectionFailed(reason):
            "Falha na conexão: \(reason)"
        case let .modelLoadFailed(reason):
            "Erro ao carregar modelo: \(reason)"
        case let .transcriptionFailed(reason):
            "Falha na transcrição: \(reason)"
        }
    }
}
