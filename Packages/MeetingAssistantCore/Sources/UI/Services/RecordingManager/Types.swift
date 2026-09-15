import Foundation
import MeetingAssistantCoreDomain

/// Post-processing configuration result for debugging and introspection.
public struct PostProcessingConfigurationDebugInfo: Sendable {
    /// The kernel mode used for post-processing.
    public let kernelMode: IntelligenceKernelMode
    /// Whether post-processing will be applied.
    public let applyPostProcessing: Bool
    /// The ID of the selected prompt, if any.
    public let promptId: UUID?
    /// The title of the selected prompt, if any.
    public let promptTitle: String?

    public init(
        kernelMode: IntelligenceKernelMode,
        applyPostProcessing: Bool,
        promptId: UUID?,
        promptTitle: String?
    ) {
        self.kernelMode = kernelMode
        self.applyPostProcessing = applyPostProcessing
        self.promptId = promptId
        self.promptTitle = promptTitle
    }
}
