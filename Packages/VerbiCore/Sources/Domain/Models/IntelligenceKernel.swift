import Foundation

/// Supported execution modes for the shared intelligence kernel.
public enum CaptureMode: String, CaseIterable, Codable, Sendable {
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

/// Compatibility name for the pre-phase-3 kernel mode type.
@available(*, deprecated, renamed: "CaptureMode")
public typealias IntelligenceKernelMode = CaptureMode

/// Shared request contract for post-processing through the intelligence kernel.
public struct IntelligenceKernelPostProcessingRequest: Sendable {
    public let mode: CaptureMode
    public let transcriptionText: String
    public let prompt: DomainPostProcessingPrompt?

    public init(
        mode: CaptureMode,
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
    public let mode: CaptureMode
    public let output: DomainPostProcessingResult

    public init(mode: CaptureMode, output: DomainPostProcessingResult) {
        self.mode = mode
        self.output = output
    }
}

/// Shared request contract for grounded Q&A through the intelligence kernel.
public struct IntelligenceKernelQuestionRequest: Sendable {
    public let mode: CaptureMode
    public let question: String
    public let transcription: CaptureArtifact
    public let modelSelectionOverride: MeetingQAModelSelection?

    public init(
        mode: CaptureMode,
        question: String,
        transcription: CaptureArtifact,
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
    public let mode: CaptureMode
    public let isGroundedInTranscript: Bool
    public let containsSpeculation: Bool
    public let confidenceScore: Double

    public init(
        mode: CaptureMode,
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
