import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

/// Comprehensive status of the transcription system.
@MainActor
public class TranscriptionStatus: ObservableObject {
    // MARK: - Service State

    @Published public private(set) var serviceState: ServiceState = .unknown
    @Published public private(set) var modelState: ModelState = .unloaded
    @Published public private(set) var device: String = "unknown"

    // MARK: - Transcription Progress

    /// Modern state representation for external observers.
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

    // MARK: - Error Tracking

    @Published public private(set) var lastError: TranscriptionStatusError?
    @Published public private(set) var lastErrorTime: Date?

    // MARK: - Timing

    @Published public private(set) var transcriptionStartTime: Date?
    @Published public private(set) var lastHealthCheck: Date?

    public init() {}

    // MARK: - Computed Properties

    /// Returns user-friendly status message.
    public var statusMessage: String {
        switch (serviceState, modelState, phase) {
        case (.disconnected, _, _):
            "Serviço desconectado"
        case (.connecting, _, _):
            "Conectando ao serviço..."
        case (.error, _, _):
            lastError?.localizedDescription ?? "Erro de conexão"
        case (.connected, .downloading, _):
            "Baixando modelo (isso pode demorar)..."
        case (.connected, .loading, _):
            "Carregando modelo..."
        case (.connected, .error, _):
            "Erro ao carregar modelo"
        case (.connected, .unloaded, _):
            "Modelo não carregado"
        case (.connected, .loaded, .idle):
            "Pronto para transcrever"
        case (.connected, .loaded, .preparing):
            "Preparando áudio..."
        case (.connected, .loaded, .processing):
            formattedProgress
        case (.connected, .loaded, .postProcessing):
            "Processando resultado..."
        case (.connected, .loaded, .completed):
            "Transcrição concluída!"
        case (.connected, .loaded, .failed):
            lastError?.localizedDescription ?? "Falha na transcrição"
        default:
            "Status desconhecido"
        }
    }

    /// Returns formatted progress string.
    private var formattedProgress: String {
        if let estimated = estimatedTimeRemaining, estimated > 0 {
            return "Transcrevendo... \(Int(progressPercentage))% (~\(TimeFormatter.format(estimated)) restante)"
        } else if progressPercentage > 0 {
            return "Transcrevendo... \(Int(progressPercentage))%"
        }
        return "Transcrevendo áudio..."
    }

    /// Whether system is ready for transcription.
    public var isReady: Bool {
        serviceState == .connected && modelState == .loaded && phase == .idle
    }

    /// Whether transcription is currently in progress.
    public var isProcessing: Bool {
        [.preparing, .processing, .postProcessing].contains(phase)
    }

    /// Whether there's a blocking error.
    public var hasBlockingError: Bool {
        serviceState == .error || serviceState == .disconnected || modelState == .error
    }

    // MARK: - Update Methods

    /// Update service connection state.
    public func updateServiceState(_ state: ServiceState) {
        serviceState = state
        if state == .connected {
            lastHealthCheck = Date()
        }
    }

    /// Update model loading state.
    public func updateModelState(_ state: ModelState, device: String? = nil) {
        modelState = state
        if let device {
            self.device = device
        }
    }

    /// Begins a new transcription session.
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

    /// Updates transcription progress during processing.
    public func updateProgress(
        phase: TranscriptionPhase,
        percentage: Double? = nil,
        processedSeconds: Double? = nil
    ) {
        self.phase = phase

        if let percentage {
            progressPercentage = min(max(percentage, 0.0), 100.0)
        }

        // Update synthetic status
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

    /// Marks transcription as completed.
    public func completeTranscription(success: Bool) {
        phase = success ? .completed : .failed
        progressPercentage = success ? 100.0 : progressPercentage
        currentStatus = success ? .completed : (lastError != nil ? .failed(lastError!) : .idle)
        estimatedTimeRemaining = nil
        transcriptionStartTime = nil
    }

    /// Resets to idle state after completion.
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

    /// Records an error that occurred.
    public func recordError(_ error: TranscriptionStatusError) {
        lastError = error
        lastErrorTime = Date()
        currentStatus = .failed(error)

        // Update state based on error type
        switch error {
        case .serviceUnavailable, .connectionFailed:
            serviceState = .disconnected
        case .modelLoadFailed:
            modelState = .error
        case .transcriptionFailed:
            phase = .failed
        }
    }

    /// Clears error state.
    public func clearError() {
        lastError = nil
        lastErrorTime = nil
    }

    public func updateLivePreviewText(_ text: String) {
        livePreviewText = text
    }

    // MARK: - Private Methods

    /// Calculates estimated time remaining based on processing speed.
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

        // Update percentage based on processed duration
        progressPercentage = (processedDurationSeconds / audioDuration) * 100.0
    }
}

// MARK: - Error Types

/// Errors related to transcription status.
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
