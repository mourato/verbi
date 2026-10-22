@testable import VerbiCore
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class AssistantTranscriptionPhaseTests: XCTestCase {

    // MARK: - normalizedAssistantTranscription

    func testNormalizedAssistantTranscription_AppliesVocabularyRulesBeforeTrimming() {
        let phase = makePhase()
        let result = phase.normalizedAssistantTranscription(
            "  open ay eye summarize this for reycast  ",
            vocabularyReplacementRules: [
                VocabularyReplacementRule(find: "open ay eye", replace: "OpenAI"),
                VocabularyReplacementRule(find: "reycast, recast", replace: "Raycast"),
            ],
        )
        XCTAssertEqual(result, "OpenAI summarize this for Raycast")
    }

    func testNormalizedAssistantTranscription_ReturnsTrimmedOriginalWhenNoRuleMatches() {
        let phase = makePhase()
        let result = phase.normalizedAssistantTranscription(
            "  ask for status update  ",
            vocabularyReplacementRules: [
                VocabularyReplacementRule(find: "open ay eye", replace: "OpenAI"),
            ],
        )
        XCTAssertEqual(result, "ask for status update")
    }

    func testNormalizedAssistantTranscription_HandlesEmptyInput() {
        let phase = makePhase()
        let result = phase.normalizedAssistantTranscription(
            "  ",
            vocabularyReplacementRules: [],
        )
        XCTAssertEqual(result, "")
    }

    // MARK: - resolveSelectedIntegration

    func testResolveSelectedIntegration_ReturnsIntegrationWhenDispatchEnabled() {
        let phase = makePhase()
        let integration = makeIntegrationConfig(name: "test")
        let result = phase.resolveSelectedIntegration(
            executionFlow: .integrationDispatch,
            isAssistantIntegrationsEnabled: true,
            assistantSelectedIntegration: integration,
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.name, "test")
    }

    func testResolveSelectedIntegration_ReturnsNilWhenNotDispatchFlow() {
        let phase = makePhase()
        let integration = makeIntegrationConfig(name: "test")
        let result = phase.resolveSelectedIntegration(
            executionFlow: .assistantMode,
            isAssistantIntegrationsEnabled: true,
            assistantSelectedIntegration: integration,
        )
        XCTAssertNil(result)
    }

    func testResolveSelectedIntegration_ReturnsNilWhenIntegrationsDisabled() {
        let phase = makePhase()
        let integration = makeIntegrationConfig(name: "test")
        let result = phase.resolveSelectedIntegration(
            executionFlow: .integrationDispatch,
            isAssistantIntegrationsEnabled: false,
            assistantSelectedIntegration: integration,
        )
        XCTAssertNil(result)
    }

    func testResolveSelectedIntegration_ReturnsNilWhenNoIntegration() {
        let phase = makePhase()
        let result = phase.resolveSelectedIntegration(
            executionFlow: .integrationDispatch,
            isAssistantIntegrationsEnabled: true,
            assistantSelectedIntegration: nil,
        )
        XCTAssertNil(result)
    }

    // MARK: - performTranscription

    func testPerformTranscription_UsesAssistantExecutionModeAndAppliesVocabularyRules() async throws {
        let transcriber = MockAssistantCommandTranscriber()
        transcriber.response = TranscriptionResponse(
            text: "  open ay eye summarize this for reycast  ",
            language: "pt",
            durationSeconds: 1,
            model: "mock-model",
            processedAt: Date().ISO8601Format(),
        )
        let phase = makePhase(transcriber: transcriber)
        let integration = makeIntegrationConfig(name: "Raycast")

        let result = try await phase.performTranscription(
            recordingURL: URL(fileURLWithPath: "/tmp/assistant-test.m4a"),
            vocabularyReplacementRules: [
                VocabularyReplacementRule(find: "open ay eye", replace: "OpenAI"),
                VocabularyReplacementRule(find: "reycast, recast", replace: "Raycast"),
            ],
            selection: .default,
            inputLanguageCode: nil,
            executionFlow: .integrationDispatch,
            isAssistantIntegrationsEnabled: true,
            assistantSelectedIntegration: integration,
        )

        XCTAssertEqual(result.command, "OpenAI summarize this for Raycast")
        XCTAssertEqual(result.executionFlow, .integrationDispatch)
        XCTAssertEqual(result.selectedIntegration?.name, "Raycast")
        XCTAssertEqual(transcriber.lastExecutionMode, .assistant)
        XCTAssertEqual(transcriber.lastDiarizationOverride, false)
        XCTAssertNil(transcriber.lastVocabularyHints)
        XCTAssertEqual(transcriber.lastConfiguration?.providerID, TranscriptionProvider.local.rawValue)
        XCTAssertEqual(transcriber.lastConfiguration?.modelID, TranscriptionProviderSelection.default.selectedModel)
        XCTAssertNil(transcriber.lastConfiguration?.inputLanguageCode)
    }

    func testPerformTranscription_PassesVocabularyHintsWithoutOverride() async throws {
        let transcriber = MockAssistantCommandTranscriber()
        transcriber.response = TranscriptionResponse(
            text: "hello world",
            language: "en",
            durationSeconds: 1,
            model: "mock-model",
            processedAt: Date().ISO8601Format(),
        )
        let phase = makePhase(transcriber: transcriber)
        let hints = VocabularyProviderHints(groqPrompt: "SwiftUI, Metal", elevenLabsKeyterms: ["SwiftUI", "Metal"])

        _ = try await phase.performTranscription(
            recordingURL: URL(fileURLWithPath: "/tmp/assistant-hints.m4a"),
            vocabularyReplacementRules: [],
            vocabularyHints: hints,
            selection: .default,
            inputLanguageCode: "en",
            executionFlow: .assistantMode,
            isAssistantIntegrationsEnabled: false,
            assistantSelectedIntegration: nil,
        )

        XCTAssertEqual(transcriber.lastVocabularyHints, hints)
        XCTAssertEqual(transcriber.lastConfiguration?.providerID, TranscriptionProviderSelection.default.provider.rawValue)
        XCTAssertEqual(transcriber.lastConfiguration?.modelID, TranscriptionProviderSelection.default.selectedModel)
        XCTAssertEqual(transcriber.lastConfiguration?.inputLanguageCode, "en")
        XCTAssertEqual(transcriber.lastConfiguration?.vocabularyHints, hints)
    }

    func testPerformTranscription_ThrowsEmptyCommandAfterNormalization() async {
        let transcriber = MockAssistantCommandTranscriber()
        transcriber.response = TranscriptionResponse(
            text: "  ",
            language: "pt",
            durationSeconds: 1,
            model: "mock-model",
            processedAt: Date().ISO8601Format(),
        )
        let phase = makePhase(transcriber: transcriber)

        do {
            _ = try await phase.performTranscription(
                recordingURL: URL(fileURLWithPath: "/tmp/assistant-test.m4a"),
                vocabularyReplacementRules: [],
                selection: .default,
                inputLanguageCode: nil,
                executionFlow: .assistantMode,
                isAssistantIntegrationsEnabled: true,
                assistantSelectedIntegration: nil,
            )
            XCTFail("Expected empty command error")
        } catch {
            XCTAssertEqual(error as? AssistantVoiceCommandError, .emptyCommand)
        }
    }

    func testPerformTranscription_DropsIntegrationWhenDisabled() async throws {
        let transcriber = MockAssistantCommandTranscriber()
        transcriber.response = TranscriptionResponse(
            text: "summarize this",
            language: "pt",
            durationSeconds: 1,
            model: "mock-model",
            processedAt: Date().ISO8601Format(),
        )
        let phase = makePhase(transcriber: transcriber)

        let result = try await phase.performTranscription(
            recordingURL: URL(fileURLWithPath: "/tmp/assistant-test.m4a"),
            vocabularyReplacementRules: [],
            selection: .default,
            inputLanguageCode: nil,
            executionFlow: .integrationDispatch,
            isAssistantIntegrationsEnabled: false,
            assistantSelectedIntegration: makeIntegrationConfig(name: "Disabled"),
        )

        XCTAssertEqual(result.command, "summarize this")
        XCTAssertNil(result.selectedIntegration)
    }

    // MARK: - Helpers

    private func makePhase(
        transcriber: MockAssistantCommandTranscriber = MockAssistantCommandTranscriber(),
    ) -> AssistantTranscriptionPhase {
        AssistantTranscriptionPhase(transcriptionClient: transcriber)
    }

    private func makeIntegrationConfig(name: String) -> AssistantIntegrationConfig {
        AssistantIntegrationConfig(
            id: UUID(),
            name: name,
            kind: .deeplink,
            isEnabled: true,
            deepLink: "test://",
            promptInstructions: nil,
            selectedPreset: nil,
            shortcutDefinition: nil,
            shortcutPresetKey: .notSpecified,
            shortcutActivationMode: .holdOrToggle,
            modifierShortcutGesture: nil,
            advancedScript: nil,
            showsPromptSelectorInOverlay: false,
            showsLanguageSelectorInOverlay: false,
        )
    }
}

@MainActor
private final class MockAssistantCommandTranscriber: TranscriptionService {
    var response = TranscriptionResponse(
        text: "summarize this",
        language: "pt",
        durationSeconds: 1,
        model: "mock-model",
        processedAt: Date().ISO8601Format(),
    )
    var lastExecutionMode: CaptureMode?
    var lastDiarizationOverride: Bool?
    var lastVocabularyHints: VocabularyProviderHints?
    var lastConfiguration: DomainTranscriptionRequestConfiguration?

    func transcribe(
        audioURL _: URL,
        onProgress _: (@Sendable (Double) -> Void)?,
        executionMode: CaptureMode,
        diarizationEnabledOverride: Bool?,
        configuration: DomainTranscriptionRequestConfiguration,
    ) async throws -> TranscriptionResponse {
        lastExecutionMode = executionMode
        lastDiarizationOverride = diarizationEnabledOverride
        lastConfiguration = configuration
        lastVocabularyHints = configuration.vocabularyHints
        return response
    }

    func transcribe(audioURL _: URL, onProgress _: (@Sendable (Double) -> Void)?) async throws -> TranscriptionResponse {
        response
    }

    func transcribe(samples _: [Float]) async throws -> TranscriptionResponse {
        response
    }

    func healthCheck() async throws -> Bool {
        true
    }

    func fetchServiceStatus() async throws -> ServiceStatusResponse {
        fatalError("Assistant transcription test does not fetch service status")
    }
}
