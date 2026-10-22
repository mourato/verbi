@testable import VerbiCore
import XCTest

@MainActor
final class DictationStylesSettingsViewModelTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testPrepareEditorForCreateCreatesFreshDraft() {
        let viewModel = DictationStylesSettingsViewModel(settings: settings)

        viewModel.prepareEditor(for: nil)

        XCTAssertNil(viewModel.editorDraft?.id)
        XCTAssertEqual(viewModel.editorDraft?.name, "")
        XCTAssertEqual(viewModel.editorDraft?.iconSymbol, "textformat")
        XCTAssertEqual(viewModel.editorDraft?.targets, [])
    }

    func testPrepareEditorForExistingStyleCopiesPersistedValues() throws {
        let style = DictationStyle(
            name: "Safari Notes",
            iconSymbol: "safari",
            promptInstructions: "Use concise bullets.",
            postProcessingEnabled: false,
            forceMarkdownOutput: false,
            replaceBasePrompt: true,
            outputLanguage: .english,
            targets: [.app(bundleIdentifier: "com.apple.Safari")],
        )
        settings.dictationStyles = [style]
        let persistedStyle = try XCTUnwrap(settings.dictationStyles.first(where: { !$0.isDefault }))
        let viewModel = DictationStylesSettingsViewModel(settings: settings)

        viewModel.prepareEditor(for: persistedStyle.id)

        XCTAssertEqual(viewModel.editorDraft?.id, persistedStyle.id)
        XCTAssertEqual(viewModel.editorDraft?.name, persistedStyle.name)
        XCTAssertEqual(viewModel.editorDraft?.promptInstructions, persistedStyle.promptInstructions)
        XCTAssertEqual(viewModel.editorDraft?.targets, persistedStyle.targets)
    }

    func testPrepareEditorForCreateInheritsPersistedDefaultModeConfiguration() throws {
        let textPolicy = DictationTextHandlingPolicy(
            autoCopyToClipboard: false,
            autoPasteToActiveApp: true,
            smartSpacingAndCapitalization: false,
            smartParagraphs: false,
        )
        let transcription = DictationTranscriptionConfiguration(
            selection: TranscriptionProviderSelection(provider: .groq, selectedModel: "whisper-large-v3"),
            inputLanguageCode: "pt-BR",
        )
        let enhancements = EnhancementsAISelection(provider: .openai, selectedModel: "gpt-4o-mini")
        var styles = settings.dictationStyles
        let defaultIndex = try XCTUnwrap(styles.firstIndex(where: \.isDefault))
        styles[defaultIndex] = DictationStyle(
            id: styles[defaultIndex].id,
            name: styles[defaultIndex].name,
            iconSymbol: styles[defaultIndex].iconSymbol,
            promptInstructions: styles[defaultIndex].promptInstructions,
            postProcessingEnabled: styles[defaultIndex].postProcessingEnabled,
            forceMarkdownOutput: styles[defaultIndex].forceMarkdownOutput,
            replaceBasePrompt: styles[defaultIndex].replaceBasePrompt,
            outputLanguage: styles[defaultIndex].outputLanguage,
            targets: [],
            contextSourcePolicy: styles[defaultIndex].contextSourcePolicy,
            enhancementsSelection: enhancements,
            isDefault: true,
            textHandlingPolicy: textPolicy,
            transcriptionConfiguration: transcription,
        )
        settings.dictationStyles = styles
        settings.autoCopyTranscriptionToClipboard = true
        settings.autoPasteTranscriptionToActiveApp = false
        settings.enhancementsDictationAISelection = EnhancementsAISelection(provider: .anthropic, selectedModel: "claude-sonnet")

        let viewModel = DictationStylesSettingsViewModel(settings: settings)
        viewModel.prepareEditor(for: nil)

        let draft = try XCTUnwrap(viewModel.editorDraft)
        XCTAssertEqual(draft.textHandlingPolicy, textPolicy)
        XCTAssertEqual(draft.transcriptionConfiguration, transcription)
        XCTAssertEqual(draft.enhancementsSelection, enhancements)
    }

    func testSaveStylePersistsTextHandlingAndTranscriptionConfiguration() throws {
        let viewModel = DictationStylesSettingsViewModel(settings: settings)
        viewModel.prepareEditor(for: nil)
        var draft = try XCTUnwrap(viewModel.editorDraft)
        draft.name = "Configured Mode"
        draft.targets = [.app(bundleIdentifier: "com.apple.Notes")]
        draft.textHandlingPolicy = DictationTextHandlingPolicy(
            autoCopyToClipboard: false,
            autoPasteToActiveApp: true,
            smartSpacingAndCapitalization: false,
            smartParagraphs: true,
        )
        draft.transcriptionConfiguration = DictationTranscriptionConfiguration(
            selection: TranscriptionProviderSelection(provider: .elevenLabs, selectedModel: "scribe_v1"),
            inputLanguageCode: "en",
        )

        let createdID = viewModel.saveStyle(draft)
        let saved = try XCTUnwrap(settings.dictationStyles.first(where: { $0.id == createdID }))

        XCTAssertEqual(saved.textHandlingPolicy, draft.textHandlingPolicy)
        XCTAssertEqual(saved.transcriptionConfiguration, draft.transcriptionConfiguration)
    }

    func testClearEditorDiscardsDraftWithoutPersistingChanges() {
        let viewModel = DictationStylesSettingsViewModel(settings: settings)
        viewModel.prepareEditor(for: nil)
        viewModel.editorDraft?.name = "Unsaved mode"

        viewModel.clearEditor()

        XCTAssertNil(viewModel.editorDraft)
        XCTAssertFalse(settings.dictationStyles.contains { $0.name == "Unsaved mode" })
    }

    func testSaveStylePersistsCreateAndClearsDraft() throws {
        let viewModel = DictationStylesSettingsViewModel(settings: settings)
        viewModel.prepareEditor(for: nil)
        var draft = try XCTUnwrap(viewModel.editorDraft)
        draft.name = "Daily Notes"

        let createdID = viewModel.saveStyle(draft)

        XCTAssertNil(viewModel.editorDraft)
        XCTAssertTrue(settings.dictationStyles.contains { $0.name == "Daily Notes" })
        XCTAssertEqual(settings.dictationStyles.first(where: { $0.name == "Daily Notes" })?.id, createdID)
    }

    func testSaveStyleUpdatesExistingModeAndCanReopenIt() throws {
        let style = DictationStyle(
            name: "Original",
            promptInstructions: "Original instructions",
            forceMarkdownOutput: true,
            replaceBasePrompt: false,
            targets: [.app(bundleIdentifier: "com.apple.TextEdit")],
        )
        settings.dictationStyles = [style]
        let persistedStyle = try XCTUnwrap(settings.dictationStyles.first(where: { !$0.isDefault }))
        let viewModel = DictationStylesSettingsViewModel(settings: settings)

        viewModel.prepareEditor(for: persistedStyle.id)
        var draft = try XCTUnwrap(viewModel.editorDraft)
        draft.name = "Updated"
        draft.promptInstructions = "Updated instructions"
        let updatedID = viewModel.saveStyle(draft)

        viewModel.prepareEditor(for: persistedStyle.id)

        XCTAssertEqual(updatedID, persistedStyle.id)
        XCTAssertEqual(viewModel.editorDraft?.name, "Updated")
        XCTAssertEqual(viewModel.editorDraft?.promptInstructions, "Updated instructions")
    }

    func testDeleteStyleRemovesExistingModeAndPreservesDefaultMode() throws {
        let style = DictationStyle(
            name: "Temporary",
            promptInstructions: "",
            forceMarkdownOutput: true,
            replaceBasePrompt: false,
            targets: [],
        )
        settings.dictationStyles = [style]
        let persistedStyle = try XCTUnwrap(settings.dictationStyles.first(where: { !$0.isDefault }))
        let viewModel = DictationStylesSettingsViewModel(settings: settings)

        viewModel.deleteStyle(id: persistedStyle.id)

        XCTAssertFalse(settings.dictationStyles.contains { $0.id == persistedStyle.id })
        XCTAssertTrue(settings.dictationStyles.contains { $0.isDefault })
    }
}
