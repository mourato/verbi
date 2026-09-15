import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct DictationStyleEditorDetailView: View {
    private let appCatalog: [InstalledApplicationRecord]
    private let isLoadingAppCatalog: Bool
    private let onEnsureAppCatalogLoaded: () -> Void
    private let onFindConflictingStyleName: (DictationStyleTarget, UUID?) -> String?
    private let modelOptions: [EnhancementsProviderModelOption]
    private let isLoadingModelOptions: Bool
    private let onRefreshModelOptions: () -> Void
    private let providerDisplayName: (EnhancementsAISelection) -> String
    private let onSave: (DictationStyleEditorDraft) -> Void
    private let onCancel: () -> Void
    private let onDelete: (() -> Void)?
    private let onOpenPromptEditor: ((DictationStyleEditorDraft) -> Void)?

    @State private var styleID: UUID?
    @State private var name: String
    @State private var iconSymbol: String
    @State private var promptInstructions: String
    @State private var postProcessingEnabled: Bool
    @State private var forceMarkdownOutput: Bool
    @State private var replaceBasePrompt: Bool
    @State private var outputLanguage: DictationOutputLanguage
    @State private var targets: [DictationStyleTarget]
    @State private var includeClipboard: Bool
    @State private var includeWindowOCR: Bool
    @State private var includeAccessibilityText: Bool
    @State private var includeSelectedTextAtStart: Bool
    @State private var redactSensitiveData: Bool
    @State private var enhancementsSelection: EnhancementsAISelection?
    @State private var autoCopyToClipboard: Bool
    @State private var autoPasteToActiveApp: Bool
    @State private var smartSpacingAndCapitalization: Bool
    @State private var smartParagraphs: Bool
    @State private var transcriptionProviderRawValue: String
    @State private var transcriptionModelID: String
    @State private var transcriptionInputLanguageCode: String?
    @State private var isDefault: Bool
    @State private var validationMessage: String?
    @State private var isDeleteConfirmationPresented = false
    @State private var isIconPickerPresented = false

    public init(
        draft: DictationStyleEditorDraft,
        appCatalog: [InstalledApplicationRecord],
        isLoadingAppCatalog: Bool,
        onEnsureAppCatalogLoaded: @escaping () -> Void,
        onFindConflictingStyleName: @escaping (DictationStyleTarget, UUID?) -> String?,
        modelOptions: [EnhancementsProviderModelOption],
        isLoadingModelOptions: Bool,
        onRefreshModelOptions: @escaping () -> Void,
        providerDisplayName: @escaping (EnhancementsAISelection) -> String,
        onSave: @escaping (DictationStyleEditorDraft) -> Void,
        onCancel: @escaping () -> Void,
        onDelete: (() -> Void)? = nil,
        onOpenPromptEditor: ((DictationStyleEditorDraft) -> Void)? = nil
    ) {
        self.appCatalog = appCatalog
        self.isLoadingAppCatalog = isLoadingAppCatalog
        self.onEnsureAppCatalogLoaded = onEnsureAppCatalogLoaded
        self.onFindConflictingStyleName = onFindConflictingStyleName
        self.modelOptions = modelOptions
        self.isLoadingModelOptions = isLoadingModelOptions
        self.onRefreshModelOptions = onRefreshModelOptions
        self.providerDisplayName = providerDisplayName
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDelete = onDelete
        self.onOpenPromptEditor = onOpenPromptEditor
        _styleID = State(initialValue: draft.id)
        _name = State(initialValue: draft.name)
        _iconSymbol = State(initialValue: draft.iconSymbol)
        _promptInstructions = State(initialValue: draft.promptInstructions)
        _postProcessingEnabled = State(initialValue: draft.postProcessingEnabled)
        _forceMarkdownOutput = State(initialValue: draft.forceMarkdownOutput)
        _replaceBasePrompt = State(initialValue: draft.replaceBasePrompt)
        _outputLanguage = State(initialValue: draft.outputLanguage)
        _targets = State(initialValue: draft.targets)
        let policy = draft.contextSourcePolicy
        _includeClipboard = State(initialValue: policy?.includeClipboard ?? false)
        _includeWindowOCR = State(initialValue: policy?.includeWindowOCR ?? false)
        _includeAccessibilityText = State(initialValue: policy?.includeAccessibilityText ?? true)
        _includeSelectedTextAtStart = State(initialValue: policy?.includeSelectedTextAtStart ?? false)
        _redactSensitiveData = State(initialValue: policy?.redactSensitiveData ?? true)
        _enhancementsSelection = State(initialValue: draft.enhancementsSelection)
        _autoCopyToClipboard = State(initialValue: draft.textHandlingPolicy.autoCopyToClipboard)
        _autoPasteToActiveApp = State(initialValue: draft.textHandlingPolicy.autoPasteToActiveApp)
        _smartSpacingAndCapitalization = State(initialValue: draft.textHandlingPolicy.smartSpacingAndCapitalization)
        _smartParagraphs = State(initialValue: draft.textHandlingPolicy.smartParagraphs)
        _transcriptionProviderRawValue = State(initialValue: draft.transcriptionConfiguration.selection.provider.rawValue)
        _transcriptionModelID = State(initialValue: draft.transcriptionConfiguration.selection.selectedModel)
        _transcriptionInputLanguageCode = State(initialValue: draft.transcriptionConfiguration.inputLanguageCode)
        _isDefault = State(initialValue: draft.isDefault)
    }

    public var body: some View {
        ModeEditorDrawer(
            headerStyle: .close,
            title: headerTitle,
            iconSymbol: normalizedIconSymbol,
            name: $name,
            onIconPicker: { isIconPickerPresented = true },
            onClose: onCancel,
            footerLeadingAction: styleID != nil && !isDefault ? { isDeleteConfirmationPresented = true } : nil,
            footerTrailingTitle: styleID == nil ? "common.create".localized : "common.save".localized,
            footerTrailingAction: saveDraft
        ) { editorForm }
            .popover(isPresented: $isIconPickerPresented) {
                DictationStyleIconPickerPopover(
                    selection: $iconSymbol,
                    onComplete: { isIconPickerPresented = false }
                )
            }
            .confirmationDialog(
                "settings.styles.editor.delete_confirmation_title".localized,
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("common.delete".localized, role: .destructive) { onDelete?() }
                Button("common.cancel".localized, role: .cancel) {}
            } message: {
                Text("settings.styles.editor.delete_confirmation_message".localized(with: headerTitle))
            }
            .onAppear {
                onEnsureAppCatalogLoaded()
                onRefreshModelOptions()
            }
    }

    private var headerTitle: String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "settings.styles.editor.new_title".localized : value
    }

    private var editorForm: some View {
        Form {
            if isDefault {
                Section("settings.styles.editor.targets".localized) {
                    Text("settings.styles.editor.default_mode_hint".localized).foregroundStyle(.secondary)
                }
            } else {
                Section("settings.styles.editor.targets".localized) {
                    DictationStyleTriggerSection(
                        targets: $targets,
                        appCatalog: appCatalog,
                        isLoadingAppCatalog: isLoadingAppCatalog,
                        styleID: styleID,
                        onEnsureAppCatalogLoaded: onEnsureAppCatalogLoaded,
                        onFindConflictingStyleName: onFindConflictingStyleName
                    )
                }
            }

            Section("settings.styles.editor.behavior".localized) {
                SettingsDrillDownButtonRow(
                    title: "settings.styles.editor.prompt".localized,
                    subtitle: promptSummary,
                    action: { onOpenPromptEditor?(currentDraft) }
                )
                SettingsCheckboxRow("settings.styles.editor.post_processing_enabled".localized, isOn: $postProcessingEnabled)
                SettingsCheckboxRow("settings.styles.editor.markdown_output".localized, isOn: $forceMarkdownOutput)
                SettingsCheckboxRow("settings.styles.editor.replace_base_prompt".localized, isOn: $replaceBasePrompt)
                Picker("settings.styles.editor.output_language".localized, selection: $outputLanguage) {
                    ForEach(DictationOutputLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                SettingsCheckboxRow("settings.general.auto_copy_transcription".localized, isOn: $autoCopyToClipboard)
                SettingsCheckboxRow("settings.general.auto_paste_transcription".localized, isOn: $autoPasteToActiveApp)
                SettingsCheckboxRow("settings.dictation.smart_spacing".localized, isOn: $smartSpacingAndCapitalization)
                SettingsCheckboxRow("settings.dictation.smart_paragraphs".localized, isOn: $smartParagraphs)
            } header: {
                SettingsFormSectionHeader(title: "settings.dictation.text_handling".localized, icon: "text.alignleft")
            }

            Section {
                transcriptionProviderPicker
                activeModelLabel
                inputLanguagePicker
            } header: {
                SettingsFormSectionHeader(title: "settings.models.routing.title".localized, icon: "arrow.triangle.branch")
            }

            Section("settings.styles.editor.context_sources".localized) {
                SettingsCheckboxRow("settings.context_awareness.accessibility_text".localized, isOn: $includeAccessibilityText)
                SettingsCheckboxRow("settings.context_awareness.selected_text_at_start".localized, isOn: $includeSelectedTextAtStart)
                Text("settings.context_awareness.selected_text_at_start_desc".localized)
                    .font(.caption).foregroundStyle(.secondary)
                SettingsCheckboxRow("settings.context_awareness.clipboard".localized, isOn: $includeClipboard)
                SettingsCheckboxRow("settings.context_awareness.window_ocr".localized, isOn: $includeWindowOCR)
                SettingsCheckboxRow("settings.context_awareness.redact_sensitive_data".localized, isOn: $redactSensitiveData)
            }

            Section("settings.enhancements.selector.dictation.title".localized) {
                EnhancementsModelPicker(
                    title: "settings.enhancements.selector.dictation.title".localized,
                    subtitle: "settings.enhancements.selector.dictation.subtitle".localized,
                    selection: enhancementsSelection ?? .default,
                    options: modelOptions,
                    isLoadingOptions: isLoadingModelOptions,
                    providerDisplayName: providerDisplayName,
                    onRefresh: onRefreshModelOptions,
                    onSelect: { option in
                        enhancementsSelection = EnhancementsAISelection(provider: option.provider, selectedModel: option.modelID, registrationID: option.registrationID)
                    }
                )
            }

            if let validationMessage, !validationMessage.isEmpty {
                Section { Text(validationMessage).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var promptSummary: String {
        let value = promptInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "settings.styles.editor.prompt_empty".localized : (value.count <= 80 ? value : String(value.prefix(80)) + "…")
    }

    private var normalizedIconSymbol: String {
        let value = iconSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "textformat" : value
    }

    @ViewBuilder
    private var transcriptionProviderPicker: some View {
        let providers = TranscriptionProvider.allCases
        Picker(
            "settings.service.transcription_provider.provider".localized,
            selection: $transcriptionProviderRawValue
        ) {
            ForEach(providers, id: \.rawValue) { provider in
                Text(provider.displayName).tag(provider.rawValue)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: transcriptionProviderRawValue) { _, newRawValue in
            if let provider = TranscriptionProvider(rawValue: newRawValue) {
                transcriptionModelID = provider.defaultModelID
            }
        }
    }

    private var activeModelLabel: some View {
        LabeledContent("settings.models.routing.active_model".localized) {
            let provider = TranscriptionProvider(rawValue: transcriptionProviderRawValue) ?? .local
            Text(provider.displayName(forModelID: transcriptionModelID))
                .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private var inputLanguagePicker: some View {
        let hints = TranscriptionInputLanguageHint.allCases
        Picker(
            "settings.service.transcription_provider.input_language".localized,
            selection: Binding(
                get: { transcriptionInputLanguageCode ?? TranscriptionInputLanguageHint.automatic.rawValue },
                set: { newValue in
                    transcriptionInputLanguageCode = newValue == TranscriptionInputLanguageHint.automatic.rawValue ? nil : newValue
                }
            )
        ) {
            ForEach(hints, id: \.rawValue) { hint in
                Text(hint.displayName).tag(hint.rawValue)
            }
        }
        .pickerStyle(.menu)

        Text("settings.service.transcription_provider.input_language.help".localized)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var currentDraft: DictationStyleEditorDraft {
        DictationStyleEditorDraft(
            id: styleID, name: name, iconSymbol: normalizedIconSymbol, promptInstructions: promptInstructions,
            postProcessingEnabled: postProcessingEnabled, forceMarkdownOutput: forceMarkdownOutput,
            replaceBasePrompt: replaceBasePrompt, outputLanguage: outputLanguage, targets: targets,
            contextSourcePolicy: DictationContextSourcePolicy(
                includeClipboard: includeClipboard, includeWindowOCR: includeWindowOCR,
                includeAccessibilityText: includeAccessibilityText, includeSelectedTextAtStart: includeSelectedTextAtStart,
                redactSensitiveData: redactSensitiveData
            ), enhancementsSelection: enhancementsSelection, textHandlingPolicy: textHandlingPolicy,
            transcriptionConfiguration: transcriptionConfiguration, isDefault: isDefault
        )
    }

    private var textHandlingPolicy: DictationTextHandlingPolicy {
        DictationTextHandlingPolicy(
            autoCopyToClipboard: autoCopyToClipboard,
            autoPasteToActiveApp: autoPasteToActiveApp,
            smartSpacingAndCapitalization: smartSpacingAndCapitalization,
            smartParagraphs: smartParagraphs
        )
    }

    private var transcriptionConfiguration: DictationTranscriptionConfiguration {
        DictationTranscriptionConfiguration(
            selection: TranscriptionProviderSelection(
                provider: TranscriptionProvider(rawValue: transcriptionProviderRawValue) ?? .local,
                selectedModel: transcriptionModelID
            ),
            inputLanguageCode: transcriptionInputLanguageCode
        )
    }

    private func saveDraft() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { validationMessage = "settings.styles.editor.validation.name_required".localized
            return
        }
        let normalizedTargets = isDefault ? [] : deduplicatedTargets(targets)
        guard isDefault || !normalizedTargets.isEmpty else { validationMessage = "settings.styles.editor.validation.targets_required".localized
            return
        }
        for target in normalizedTargets {
            if let conflict = onFindConflictingStyleName(target, styleID) {
                validationMessage = conflict.isEmpty ? "settings.styles.editor.validation.target_conflict".localized : "settings.styles.editor.validation.target_conflict_named".localized(with: conflict)
                return
            }
        }
        validationMessage = nil
        onSave(DictationStyleEditorDraft(
            id: styleID, name: trimmedName, iconSymbol: normalizedIconSymbol,
            promptInstructions: promptInstructions.trimmingCharacters(in: .whitespacesAndNewlines),
            postProcessingEnabled: postProcessingEnabled, forceMarkdownOutput: forceMarkdownOutput,
            replaceBasePrompt: replaceBasePrompt, outputLanguage: outputLanguage, targets: normalizedTargets,
            contextSourcePolicy: currentDraft.contextSourcePolicy, enhancementsSelection: enhancementsSelection,
            textHandlingPolicy: textHandlingPolicy, transcriptionConfiguration: transcriptionConfiguration, isDefault: isDefault
        ))
    }

    private func deduplicatedTargets(_ values: [DictationStyleTarget]) -> [DictationStyleTarget] {
        var seen = Set<String>()
        return values.filter { seen.insert($0.normalizedIdentity).inserted }
    }
}

#Preview("Mode Editor") {
    DictationStyleEditorDetailView(
        draft: DictationStyleEditorDraft(name: "Writing", iconSymbol: "note.text", promptInstructions: "Be concise", forceMarkdownOutput: true, replaceBasePrompt: false, outputLanguage: .original, targets: [.app(bundleIdentifier: "com.apple.Safari")], contextSourcePolicy: nil, enhancementsSelection: nil, isDefault: false),
        appCatalog: [], isLoadingAppCatalog: false, onEnsureAppCatalogLoaded: {}, onFindConflictingStyleName: { _, _ in nil }, modelOptions: [], isLoadingModelOptions: false, onRefreshModelOptions: {}, providerDisplayName: { _ in "" }, onSave: { _ in }, onCancel: {}
    )
    .frame(width: 400, height: 640)
}
