@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

extension RecordingManagerTests {
    func testRunPostProcessing_WithLongManualInputPassesThroughToService() async throws {
        let manager = try XCTUnwrap(manager)
        let postProcessing = try XCTUnwrap(mockPostProcessing)
        let longInput = String(repeating: "Manual meeting segment. ", count: 5_500)
        let settings = AppSettingsStore.shared
        let selection = settings.enhancementsSelection(for: .meeting)
        let configuration = settings.resolvedEnhancementsAIConfiguration(for: selection)
        let prompt = PostProcessingPrompt(title: "Summarize", promptText: "Summarize this", isActive: true)

        let result = await manager.runPostProcessing(
            postProcessingInput: longInput,
            prompt: prompt,
            request: DomainPostProcessingRequest(
                prompt: DomainPostProcessingPrompt(id: prompt.id, title: prompt.title, content: prompt.promptText),
                mode: .meeting,
                selection: DomainPostProcessingSelection(
                    providerID: selection.provider.rawValue,
                    modelID: selection.selectedModel,
                    registrationID: selection.registrationID,
                ),
                configuration: DomainPostProcessingConfiguration(
                    providerID: configuration.provider.rawValue,
                    baseURL: configuration.baseURL,
                    modelID: configuration.selectedModel,
                ),
                useStructuredPipeline: false,
            ),
            qualityProfile: nil,
        )

        XCTAssertGreaterThan(longInput.count, 100_000)
        XCTAssertEqual(postProcessing.processTranscriptionCallCount, 1)
        XCTAssertEqual(postProcessing.lastProcessText, longInput)
        XCTAssertNil(result.failureReason)
        XCTAssertNotNil(result.processedContent)
    }
}
