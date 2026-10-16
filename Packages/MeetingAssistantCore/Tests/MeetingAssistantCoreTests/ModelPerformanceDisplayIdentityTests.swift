@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreUI
import XCTest

final class ModelPerformanceDisplayIdentityTests: XCTestCase {
    func testTranscription_ResolvesCurrentProductNameFromStoredRawID() {
        let stored = makeIdentity(providerID: "groq", providerName: "Groq", modelID: "whisper-large-v3")

        let identity = ModelPerformanceDisplayIdentity(stored, stage: .transcription)

        XCTAssertEqual(identity.title, "settings.service.transcription_provider.model_option.whisper_large_v3".localized)
        XCTAssertNotEqual(identity.title, "whisper-large-v3")
        XCTAssertEqual(identity.providerName, TranscriptionProvider.groq.displayName)
        XCTAssertEqual(identity.brand, .openai)
        XCTAssertEqual(identity.host, .groq)
    }

    func testPostProcessing_UsesAIProviderBrandAndKeepsStoredNames() {
        let stored = makeIdentity(providerID: "anthropic", providerName: "Work Claude", modelID: "claude-sonnet-4")

        let identity = ModelPerformanceDisplayIdentity(stored, stage: .postProcessing)

        XCTAssertEqual(identity.title, "claude-sonnet-4")
        XCTAssertEqual(identity.providerName, "Work Claude")
        XCTAssertEqual(identity.brand, .anthropic)
        XCTAssertNil(identity.host)
    }

    func testUnknownProvider_FallsBackToStoredDisplayNames() {
        let stored = makeIdentity(providerID: "unknown", providerName: "Unknown", modelID: "mystery", modelName: "Mystery")

        let identity = ModelPerformanceDisplayIdentity(stored, stage: .transcription)

        XCTAssertEqual(identity.title, "Mystery")
        XCTAssertEqual(identity.providerName, "Unknown")
        XCTAssertNil(identity.brand)
    }

    func testKnownProviderUnknownModel_PreservesStoredProductName() {
        let stored = makeIdentity(providerID: "groq", providerName: "Old host", modelID: "future-model", modelName: "Future Model")

        let identity = ModelPerformanceDisplayIdentity(stored, stage: .transcription)

        XCTAssertEqual(identity.title, "Future Model")
        XCTAssertEqual(identity.providerName, TranscriptionProvider.groq.displayName)
        XCTAssertEqual(identity.brand, .groq)
    }

    func testStageSelectsProviderNamespace() {
        // "groq" is both a transcription and an AI provider; the post-processing stage must not map transcription names.
        let stored = makeIdentity(providerID: "groq", providerName: "Groq", modelID: "whisper-large-v3")

        let identity = ModelPerformanceDisplayIdentity(stored, stage: .postProcessing)

        XCTAssertEqual(identity.title, "whisper-large-v3")
    }

    func testMetricBar_SegmentsRelativeToBest() {
        XCTAssertEqual(ModelMetricBar.filledSegments(for: ModelMetricBar.fraction(10, best: 10)), 5)
        XCTAssertEqual(ModelMetricBar.filledSegments(for: ModelMetricBar.fraction(5, best: 10)), 3)
        XCTAssertEqual(ModelMetricBar.filledSegments(for: ModelMetricBar.fraction(0.1, best: 10)), 1)
        XCTAssertEqual(ModelMetricBar.filledSegments(for: ModelMetricBar.fraction(0, best: 10)), 0)
        XCTAssertEqual(ModelMetricBar.filledSegments(for: ModelMetricBar.fraction(3, best: 0)), 0)
        XCTAssertEqual(ModelMetricBar.filledSegments(for: .greatestFiniteMagnitude), 5)
        XCTAssertEqual(ModelMetricBar.filledSegments(for: .nan), 0)
        XCTAssertEqual(ModelMetricBar.fraction(3, best: .infinity), 0)
    }

    private func makeIdentity(
        providerID: String,
        providerName: String,
        modelID: String,
        modelName: String? = nil
    ) -> ModelPerformanceModelIdentity {
        ModelPerformanceModelIdentity(
            providerID: providerID,
            providerDisplayName: providerName,
            modelID: modelID,
            modelDisplayName: modelName ?? modelID,
            runtimeKind: .remote
        )
    }
}
