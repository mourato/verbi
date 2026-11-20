import Foundation
import VerbiCoreDomain

public struct PostProcessingConfigurationDebugInfo: Sendable {
    public let kernelMode: CaptureMode
    public let applyPostProcessing: Bool
    public let promptId: UUID?
    public let promptTitle: String?

    public init(
        kernelMode: CaptureMode,
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
