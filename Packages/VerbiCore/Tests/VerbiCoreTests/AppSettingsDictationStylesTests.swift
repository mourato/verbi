@testable import VerbiCore
import XCTest

@MainActor
final class AppSettingsDictationStylesTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testDictationStyles_EnforcesGlobalTargetExclusivity() {
        let sharedTarget = DictationTrigger.app(bundleIdentifier: "com.microsoft.VSCode")

        settings.dictationStyles = [
            DictationStyle(
                id: UUID(),
                name: "Style A",
                iconSymbol: "textformat",
                promptInstructions: "A",
                forceMarkdownOutput: true,
                replaceBasePrompt: false,
                outputLanguage: .original,
                targets: [
                    sharedTarget,
                    .website(url: "https://docs.example.com"),
                ],
            ),
            DictationStyle(
                id: UUID(),
                name: "Style B",
                iconSymbol: "text.quote",
                promptInstructions: "B",
                forceMarkdownOutput: false,
                replaceBasePrompt: false,
                outputLanguage: .english,
                targets: [
                    sharedTarget,
                    .website(url: "https://api.example.com"),
                ],
            ),
        ]

        let styleA = settings.dictationStyles[1]
        let styleB = settings.dictationStyles[2]

        XCTAssertTrue(styleA.targets.contains(sharedTarget))
        XCTAssertFalse(styleB.targets.contains(sharedTarget))
        XCTAssertEqual(styleB.targets, [.website(url: "https://api.example.com")])
    }

    func testDictationStyles_RemovesInvalidAndDuplicateTargetsWithinStyle() {
        settings.dictationStyles = [
            DictationStyle(
                id: UUID(),
                name: "Style",
                iconSymbol: "textformat",
                promptInstructions: "Rule",
                forceMarkdownOutput: true,
                replaceBasePrompt: false,
                outputLanguage: .original,
                targets: [
                    .app(bundleIdentifier: "com.microsoft.VSCode"),
                    .app(bundleIdentifier: " com.microsoft.vscode "),
                    .website(url: "   "),
                    .website(url: "https://docs.example.com"),
                ],
            ),
        ]

        let targets = settings.dictationStyles[1].targets
        XCTAssertEqual(
            targets,
            [
                .app(bundleIdentifier: "com.microsoft.VSCode"),
                .website(url: "https://docs.example.com"),
            ],
        )
    }

    func testDictationStyleTarget_NormalizedIdentityTreatsWebsiteSchemesAsEquivalent() {
        let httpsTarget = DictationTrigger.website(url: " HTTPS://Docs.Example.com ")
        let httpTarget = DictationTrigger.website(url: "http://docs.example.com")
        let bareTarget = DictationTrigger.website(url: "docs.example.com")

        XCTAssertEqual(httpsTarget.normalizedIdentity, httpTarget.normalizedIdentity)
        XCTAssertEqual(httpTarget.normalizedIdentity, bareTarget.normalizedIdentity)
    }

    func testDictationStyles_CreatesDefaultModeWhenDeleted() {
        settings.dictationStyles = []

        XCTAssertEqual(settings.dictationStyles.count, 1)
        XCTAssertEqual(settings.dictationStyles.first?.id, AppSettingsStore.defaultDictationModeID)
        XCTAssertEqual(settings.dictationStyles.first?.isDefault, true)
        XCTAssertEqual(settings.dictationStyles.first?.targets, [])
    }

    func testDictationStyle_PostProcessingEnabledDefaultsForLegacyPayloads() throws {
        let legacyPayload = """
        {
          "id": "00000000-0000-0000-0000-000000000020",
          "name": "Default",
          "iconSymbol": "textformat",
          "promptInstructions": "",
          "forceMarkdownOutput": false,
          "replaceBasePrompt": false,
          "outputLanguage": "original",
          "targets": [],
          "isDefault": true
        }
        """

        let style = try JSONDecoder().decode(DictationStyle.self, from: Data(legacyPayload.utf8))

        XCTAssertTrue(style.postProcessingEnabled)
    }

    func testDictationStyles_LegacyModesMigrateGlobalConfigurationExactlyOnce() throws {
        let legacyPayload = """
        [{
          "id": "00000000-0000-0000-0000-000000000021",
          "name": "Legacy",
          "promptInstructions": "",
          "forceMarkdownOutput": false,
          "replaceBasePrompt": false,
          "outputLanguage": "original",
          "targets": [],
          "isDefault": false
        }]
        """
        let legacyStyles = try JSONDecoder().decode([DictationStyle].self, from: Data(legacyPayload.utf8))
        let textPolicy = DictationTextHandlingPolicy(autoCopyToClipboard: false, autoPasteToActiveApp: true, smartSpacingAndCapitalization: false, smartParagraphs: true)
        let transcription = TranscriptionProviderSelection(provider: .groq, selectedModel: " whisper-large-v3 ")
        let migrated = AppSettingsStore.migrateLegacyDictationStyles(
            legacyStyles,
            dictationSelection: EnhancementsAISelection(provider: .openai, selectedModel: "custom"),
            transcriptionSelection: transcription,
            inputLanguageCode: "pt-BR",
            textHandlingPolicy: textPolicy,
        )

        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated[0].textHandlingPolicy, textPolicy)
        XCTAssertEqual(migrated[0].transcriptionConfiguration.selection.provider, .groq)
        XCTAssertEqual(migrated[0].transcriptionConfiguration.selection.selectedModel, "whisper-large-v3")
        XCTAssertEqual(migrated[0].transcriptionConfiguration.inputLanguageCode, "pt-BR")
        XCTAssertEqual(migrated[0].configurationSchemaVersion, DictationStyle.currentConfigurationSchemaVersion)
        XCTAssertEqual(AppSettingsStore.migrateLegacyDictationStyles(
            migrated,
            dictationSelection: EnhancementsAISelection(provider: .anthropic, selectedModel: "changed"),
            transcriptionSelection: .default,
            inputLanguageCode: nil,
            textHandlingPolicy: .init(),
        ), migrated)
    }

    func testDictationStyle_NewPayloadNormalizesUnknownLocalModel() {
        let style = DictationStyle(
            name: "Mode",
            promptInstructions: "",
            forceMarkdownOutput: false,
            replaceBasePrompt: false,
            targets: [],
            transcriptionConfiguration: DictationTranscriptionConfiguration(
                selection: TranscriptionProviderSelection(provider: .local, selectedModel: "unknown-model"),
            ),
        )

        XCTAssertEqual(style.transcriptionConfiguration.selection.selectedModel, TranscriptionProvider.localModelID)
    }

    func testDictationStyles_PersistPerModePostProcessingValue() {
        settings.dictationStyles = [
            DictationStyle(
                name: "No AI",
                promptInstructions: "Keep the transcript unchanged.",
                postProcessingEnabled: false,
                forceMarkdownOutput: false,
                replaceBasePrompt: false,
                targets: [.app(bundleIdentifier: "com.apple.TextEdit")],
            ),
        ]

        let style = settings.dictationStyles[1]
        XCTAssertFalse(style.postProcessingEnabled)
        XCTAssertEqual(style.promptInstructions, "Keep the transcript unchanged.")
    }

    func testDictationStyles_DefaultModeAdoptsLegacyContextAndModelSelection() {
        settings.contextAwarenessEnabled = true
        settings.contextAwarenessIncludeClipboard = true
        settings.contextAwarenessIncludeWindowOCR = false
        settings.contextAwarenessIncludeAccessibilityText = true
        settings.contextAwarenessRedactSensitiveData = false
        settings.enhancementsDictationAISelection = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4.1-mini")

        settings.dictationStyles = []

        let defaultStyle = settings.dictationStyles[0]
        XCTAssertEqual(defaultStyle.contextSourcePolicy?.hasEnabledContextSources, true)
        XCTAssertEqual(defaultStyle.contextSourcePolicy?.includeClipboard, true)
        XCTAssertEqual(defaultStyle.contextSourcePolicy?.includeWindowOCR, false)
        XCTAssertEqual(defaultStyle.contextSourcePolicy?.includeAccessibilityText, true)
        XCTAssertEqual(defaultStyle.contextSourcePolicy?.redactSensitiveData, false)
        XCTAssertEqual(defaultStyle.enhancementsSelection?.provider, .openai)
        XCTAssertEqual(defaultStyle.enhancementsSelection?.selectedModel, "gpt-4.1-mini")
    }

    func testDictationStyles_DefaultModeDoesNotMatchTargets() {
        settings.dictationStyles = [
            DictationStyle(
                id: AppSettingsStore.defaultDictationModeID,
                name: "Default",
                promptInstructions: "",
                forceMarkdownOutput: true,
                replaceBasePrompt: false,
                targets: [.app(bundleIdentifier: "com.apple.TextEdit")],
                isDefault: true,
            ),
        ]

        let defaultStyle = settings.dictationStyles[0]
        XCTAssertEqual(defaultStyle.targets, [])
        XCTAssertFalse(defaultStyle.matches(bundleIdentifier: "com.apple.TextEdit", activeURL: nil))
    }

    func testEffectiveDictationStyle_UsesDefaultModeWithoutContext() {
        let selection = EnhancementsAISelection(provider: .anthropic, selectedModel: "claude-3-5-haiku")
        settings.dictationStyles = [
            DictationStyle(
                id: AppSettingsStore.defaultDictationModeID,
                name: "Default",
                promptInstructions: "Default instructions",
                forceMarkdownOutput: true,
                replaceBasePrompt: false,
                targets: [],
                enhancementsSelection: selection,
                isDefault: true,
            ),
            DictationStyle(
                name: "Safari",
                promptInstructions: "Safari instructions",
                forceMarkdownOutput: false,
                replaceBasePrompt: false,
                targets: [.app(bundleIdentifier: "com.apple.Safari")],
            ),
        ]

        let effectiveStyle = settings.effectiveDictationStyle(bundleIdentifier: nil, activeURL: nil)

        XCTAssertEqual(effectiveStyle.id, AppSettingsStore.defaultDictationModeID)
        XCTAssertEqual(effectiveStyle.enhancementsSelection, selection)
    }

    func testDictationContextSourcePolicy_DecodesLegacyDisabledGateAsNoCaptureSources() throws {
        let jsonString = """
        {
          "isEnabled": false,
          "includeClipboard": true,
          "includeWindowOCR": true,
          "includeAccessibilityText": true,
          "redactSensitiveData": true
        }
        """
        let json = Data(jsonString.utf8)

        let policy = try JSONDecoder().decode(DictationContextSourcePolicy.self, from: json)

        XCTAssertEqual(policy.hasEnabledContextSources, false)
        XCTAssertEqual(policy.includeClipboard, false)
        XCTAssertEqual(policy.includeWindowOCR, false)
        XCTAssertEqual(policy.includeAccessibilityText, false)
        XCTAssertEqual(policy.redactSensitiveData, true)
    }

    func testDictationContextSourcePolicy_RedactionAloneDoesNotEnableContextCapture() {
        let policy = DictationContextSourcePolicy(
            includeClipboard: false,
            includeWindowOCR: false,
            includeAccessibilityText: false,
            redactSensitiveData: true,
        )

        XCTAssertEqual(policy.hasEnabledContextSources, false)
    }

    func testDictationContextSourcePolicy_SelectedTextAtStartDefaultsOffAndRoundTrips() throws {
        let legacyJSON = """
        {
          "includeClipboard": false,
          "includeWindowOCR": false,
          "includeAccessibilityText": false,
          "redactSensitiveData": true
        }
        """

        let legacyPolicy = try JSONDecoder().decode(
            DictationContextSourcePolicy.self,
            from: Data(legacyJSON.utf8),
        )
        XCTAssertFalse(legacyPolicy.includeSelectedTextAtStart)

        let policy = DictationContextSourcePolicy(
            includeClipboard: false,
            includeWindowOCR: false,
            includeAccessibilityText: false,
            includeSelectedTextAtStart: true,
            redactSensitiveData: true,
        )
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(DictationContextSourcePolicy.self, from: data)

        XCTAssertTrue(decoded.includeSelectedTextAtStart)
        XCTAssertTrue(decoded.hasEnabledContextSources)
    }

    func testDictationStyles_PromptInstructionsRoundTripsThroughDraftAndSave() throws {
        let viewModel = DictationStylesSettingsViewModel(settings: settings)

        viewModel.prepareEditor(for: nil)

        XCTAssertNotNil(viewModel.editorDraft)
        XCTAssertEqual(viewModel.editorDraft?.promptInstructions, "")

        viewModel.editorDraft?.promptInstructions = "Prefer concise technical responses with code examples."

        try viewModel.saveStyle(XCTUnwrap(viewModel.editorDraft))
        let savedStyle = settings.dictationStyles.last(where: { $0.isDefault == false })
        XCTAssertNotNil(savedStyle)
        XCTAssertEqual(savedStyle?.promptInstructions, "Prefer concise technical responses with code examples.")
    }

    func testDictationStyles_EmptyPromptInstructionsArePreserved() {
        settings.dictationStyles = [
            DictationStyle(
                name: "No Prompt",
                iconSymbol: "textformat",
                promptInstructions: "",
                forceMarkdownOutput: false,
                replaceBasePrompt: false,
                targets: [.app(bundleIdentifier: "com.apple.TextEdit")],
            ),
        ]

        let style = settings.dictationStyles[1]
        XCTAssertEqual(style.promptInstructions, "")
    }

    func testDictationStyleRoute_PromptEditorCarriesStyleIdentity() {
        let styleID = UUID()

        XCTAssertEqual(
            DictationStyleRoute.promptEditor(styleID: styleID),
            DictationStyleRoute.promptEditor(styleID: styleID),
        )
        XCTAssertNotEqual(
            DictationStyleRoute.promptEditor(styleID: styleID),
            DictationStyleRoute.editor(styleID: styleID),
        )
    }

    func testTranscriptionSelectionChangesDoNotRewriteDefaultDictationStyle() throws {
        let initialSelection = try XCTUnwrap(
            settings.dictationStyles.first(where: \.isDefault)?.transcriptionConfiguration.selection
        )
        XCTAssertEqual(initialSelection.provider, .local)

        settings.updateTranscriptionDictationProvider(.groq)
        XCTAssertEqual(settings.transcriptionDictationSelection.provider, .groq)
        XCTAssertEqual(
            settings.dictationStyles.first(where: \.isDefault)?.transcriptionConfiguration.selection,
            initialSelection
        )

        settings.updateTranscriptionDictationModel("whisper-large-v3")
        XCTAssertEqual(
            settings.dictationStyles.first(where: \.isDefault)?.transcriptionConfiguration.selection,
            initialSelection
        )

        settings.updateTranscriptionModel("whisper-large-v3-turbo", for: .groq)
        XCTAssertEqual(
            settings.dictationStyles.first(where: \.isDefault)?.transcriptionConfiguration.selection,
            initialSelection
        )

        settings.updateTranscriptionDictationSelection(provider: .openai, model: "gpt-4o-mini-transcribe")
        XCTAssertEqual(settings.transcriptionDictationSelection.provider, .openai)
        XCTAssertEqual(
            settings.dictationStyles.first(where: \.isDefault)?.transcriptionConfiguration.selection,
            initialSelection
        )
    }
}
