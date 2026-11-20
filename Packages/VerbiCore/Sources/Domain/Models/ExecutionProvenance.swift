import Foundation

public enum ExecutionVocabularySource: String, Codable, Hashable, Sendable {
    case originalSnapshot = "original_snapshot"
    case currentDictionary = "current_dictionary"
    case currentDictionaryFallback = "current_dictionary_fallback"
    case notRecorded = "not_recorded"
}

public struct ExecutionProvenance: Codable, Hashable, Sendable {
    public let transcriptionRequest: DomainTranscriptionRequestConfiguration?
    public let vocabularySnapshot: VocabularySnapshot
    public let vocabularySource: ExecutionVocabularySource?
    public let transcriptionModelIdentity: ModelPerformanceModelIdentity
    public let postProcessingSelection: DomainPostProcessingSelection?
    public let postProcessingModelIdentity: ModelPerformanceModelIdentity?
    public let postProcessingPromptID: UUID?
    public let postProcessingPromptTitle: String?
    public let kernelMode: CaptureMode?
    public let usedStructuredPostProcessing: Bool?
    private let skipPostProcessingOverride: Bool?

    public var skipPostProcessing: Bool {
        skipPostProcessingOverride ?? false
    }

    public init(
        transcriptionRequest: DomainTranscriptionRequestConfiguration?,
        vocabularySnapshot: VocabularySnapshot,
        vocabularySource: ExecutionVocabularySource? = nil,
        transcriptionModelIdentity: ModelPerformanceModelIdentity,
        postProcessingSelection: DomainPostProcessingSelection? = nil,
        postProcessingModelIdentity: ModelPerformanceModelIdentity? = nil,
        postProcessingPromptID: UUID? = nil,
        postProcessingPromptTitle: String? = nil,
        kernelMode: CaptureMode? = nil,
        usedStructuredPostProcessing: Bool? = nil,
        skipPostProcessing: Bool = false
    ) {
        self.transcriptionRequest = transcriptionRequest
        self.vocabularySnapshot = vocabularySnapshot
        self.vocabularySource = vocabularySource
        self.transcriptionModelIdentity = transcriptionModelIdentity
        self.postProcessingSelection = postProcessingSelection
        self.postProcessingModelIdentity = postProcessingModelIdentity
        self.postProcessingPromptID = postProcessingPromptID
        self.postProcessingPromptTitle = postProcessingPromptTitle
        self.kernelMode = kernelMode
        self.usedStructuredPostProcessing = usedStructuredPostProcessing
        skipPostProcessingOverride = skipPostProcessing ? true : nil
    }
}
