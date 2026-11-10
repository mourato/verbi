import Foundation

/// Where the vocabulary used by an execution came from.
///
/// Missing on records written before retries recorded their effective
/// vocabulary source. New retries always record one of these values.
public enum ExecutionVocabularySource: String, Codable, Hashable, Sendable {
    /// The snapshot stored with the original capture was reused.
    case originalSnapshot = "original_snapshot"
    /// The dictionary as it existed when the attempt started.
    case currentDictionary = "current_dictionary"
    /// An original snapshot was requested but the artifact predates it, so the
    /// attempt explicitly fell back to the dictionary as it existed at start.
    case currentDictionaryFallback = "current_dictionary_fallback"
    /// A reprocessed artifact synthesized an empty snapshot because the source
    /// artifact never recorded one. Treat it as unknown, not as an authoritative
    /// empty dictionary.
    case notRecorded = "not_recorded"
}

/// Immutable, privacy-safe inputs that identify one execution.
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

    /// Missing in older records; the override belongs only to the stored meeting session.
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
