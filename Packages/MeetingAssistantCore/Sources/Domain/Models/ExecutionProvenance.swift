import Foundation

/// Immutable, privacy-safe inputs that identify one execution.
public struct ExecutionProvenance: Codable, Hashable, Sendable {
    public let transcriptionRequest: DomainTranscriptionRequestConfiguration?
    public let vocabularySnapshot: VocabularySnapshot
    public let transcriptionModelIdentity: ModelPerformanceModelIdentity
    public let postProcessingSelection: DomainPostProcessingSelection?
    public let postProcessingModelIdentity: ModelPerformanceModelIdentity?
    public let postProcessingPromptID: UUID?
    public let postProcessingPromptTitle: String?
    public let kernelMode: IntelligenceKernelMode?
    public let usedStructuredPostProcessing: Bool?

    public init(
        transcriptionRequest: DomainTranscriptionRequestConfiguration?,
        vocabularySnapshot: VocabularySnapshot,
        transcriptionModelIdentity: ModelPerformanceModelIdentity,
        postProcessingSelection: DomainPostProcessingSelection? = nil,
        postProcessingModelIdentity: ModelPerformanceModelIdentity? = nil,
        postProcessingPromptID: UUID? = nil,
        postProcessingPromptTitle: String? = nil,
        kernelMode: IntelligenceKernelMode? = nil,
        usedStructuredPostProcessing: Bool? = nil
    ) {
        self.transcriptionRequest = transcriptionRequest
        self.vocabularySnapshot = vocabularySnapshot
        self.transcriptionModelIdentity = transcriptionModelIdentity
        self.postProcessingSelection = postProcessingSelection
        self.postProcessingModelIdentity = postProcessingModelIdentity
        self.postProcessingPromptID = postProcessingPromptID
        self.postProcessingPromptTitle = postProcessingPromptTitle
        self.kernelMode = kernelMode
        self.usedStructuredPostProcessing = usedStructuredPostProcessing
    }
}
