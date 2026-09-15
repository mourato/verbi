import Foundation

/// Supported execution modes for the shared intelligence kernel.
public enum IntelligenceKernelMode: String, CaseIterable, Codable, Sendable {
    case meeting
    case dictation
    case assistant

    public var displayName: String {
        switch self {
        case .meeting: "meetings"
        case .dictation: "dictations"
        case .assistant: "assistant"
        }
    }
}

/// Shared request contract for post-processing through the intelligence kernel.
public struct IntelligenceKernelPostProcessingRequest: Sendable {
    public let mode: IntelligenceKernelMode
    public let transcriptionText: String
    public let prompt: DomainPostProcessingPrompt?

    public init(
        mode: IntelligenceKernelMode,
        transcriptionText: String,
        prompt: DomainPostProcessingPrompt? = nil
    ) {
        self.mode = mode
        self.transcriptionText = transcriptionText
        self.prompt = prompt
    }
}

/// Shared response contract for post-processing through the intelligence kernel.
public struct IntelligenceKernelPostProcessingResult: Sendable {
    public let mode: IntelligenceKernelMode
    public let output: DomainPostProcessingResult

    public init(mode: IntelligenceKernelMode, output: DomainPostProcessingResult) {
        self.mode = mode
        self.output = output
    }
}

/// Shared request contract for grounded Q&A through the intelligence kernel.
public struct IntelligenceKernelQuestionRequest: Sendable {
    public let mode: IntelligenceKernelMode
    public let question: String
    public let transcription: Transcription
    public let modelSelectionOverride: MeetingQAModelSelection?

    public init(
        mode: IntelligenceKernelMode,
        question: String,
        transcription: Transcription,
        modelSelectionOverride: MeetingQAModelSelection? = nil
    ) {
        self.mode = mode
        self.question = question
        self.transcription = transcription
        self.modelSelectionOverride = modelSelectionOverride
    }
}

/// Shared validation output for any kernel mode.
public struct IntelligenceKernelValidationResult: Sendable, Equatable {
    public let mode: IntelligenceKernelMode
    public let isGroundedInTranscript: Bool
    public let containsSpeculation: Bool
    public let confidenceScore: Double

    public init(
        mode: IntelligenceKernelMode,
        isGroundedInTranscript: Bool,
        containsSpeculation: Bool,
        confidenceScore: Double
    ) {
        self.mode = mode
        self.isGroundedInTranscript = isGroundedInTranscript
        self.containsSpeculation = containsSpeculation
        self.confidenceScore = confidenceScore
    }
}
