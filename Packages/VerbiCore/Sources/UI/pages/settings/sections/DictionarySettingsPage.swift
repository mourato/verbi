import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

public enum DictionaryWorkflow: String, CaseIterable, Identifiable, Sendable {
    case substitutions
    case vocabulary

    public var id: String {
        rawValue
    }

    public var title: String {
        switch self {
        case .substitutions: "settings.dictionary.workflow.substitutions".localized
        case .vocabulary: "settings.dictionary.workflow.vocabulary".localized
        }
    }

    public var icon: String {
        switch self {
        case .substitutions: "arrow.2.squarepath"
        case .vocabulary: "text.book.closed"
        }
    }
}

public struct DictionarySettingsPage: View {
    @StateObject private var substitutionViewModel: VocabularySettingsViewModel
    @StateObject var vocabularyViewModel: VocabularyTermsSettingsViewModel
    @ObservedObject var settings: AppSettingsStore
    @State private var selectedWorkflow: DictionaryWorkflow = .substitutions
    @State private var entryOriginsInput = ""
    @State private var entryDestinationInput = ""
    @State private var termInput = ""
    @State private var termDefinitionInput = ""
    @State private var selectedEntryID: UUID?
    @State private var selectedTermID: UUID?
    @State var importExportMessage: String?
    @State var showImportExportAlert = false
    @State var importPreview: DictionaryImportPreview?
    private let showsHeader: Bool
    private let onBack: (() -> Void)?

    public init(
        settings: AppSettingsStore = .shared,
        showsHeader: Bool = true,
        onBack: (() -> Void)? = nil
    ) {
        _substitutionViewModel = StateObject(wrappedValue: VocabularySettingsViewModel(settings: settings))
        _vocabularyViewModel = StateObject(wrappedValue: VocabularyTermsSettingsViewModel(settings: settings))
        self.settings = settings
        self.showsHeader = showsHeader
        self.onBack = onBack
    }

    public var body: some View {
        SettingsFormPage {
            VStack(alignment: .leading, spacing: 8) {
                if let onBack {
                    SettingsChildPageBackButton(action: onBack)
                }
                SettingsFormSectionHeader(title: "settings.section.dictionary".localized, icon: "character.book.closed")
                if showsHeader {
                    Text("settings.dictionary.description".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DSGlassSegmentedControl(
                    selection: $selectedWorkflow,
                    items: DictionaryWorkflow.allCases,
                    fillsWidth: true,
                    title: \.title,
                    icon: \.icon
                )
                .padding(.vertical, 4)
            }
        } content: {
            switch selectedWorkflow {
            case .substitutions:
                substitutionsContent
                importExportSection
            case .vocabulary:
                vocabularyContent
                vocabularySupportSection
                importExportSection
            }
        }
        .alert(
            "settings.dictionary.import_export.title".localized,
            isPresented: $showImportExportAlert
        ) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            if let message = importExportMessage {
                Text(message)
            }
        }
        .sheet(isPresented: $substitutionViewModel.showEntryEditor) {
            entryEditorSheet
                .onAppear(perform: syncEditorInputsFromEditingEntry)
        }.sheet(isPresented: $vocabularyViewModel.showTermEditor) {
            VocabularyTermEditorSheet(
                isEditing: vocabularyViewModel.editingTerm != nil,
                term: $termInput,
                definition: $termDefinitionInput,
                validationMessage: vocabularyViewModel.validationError.map(validationErrorMessage),
                onSave: {
                    _ = vocabularyViewModel.saveTerm(term: termInput, definition: termDefinitionInput)
                },
                onCancel: {
                    vocabularyViewModel.dismissTermEditor()
                }
            )
            .onAppear(perform: syncTermEditorInputs)
        }
        .sheet(item: $importPreview) { preview in
            DictionaryImportPreviewSheet(
                preview: preview,
                onConfirm: {
                    confirmImport(preview: preview)
                },
                onCancel: {
                    importPreview = nil
                }
            )
        }
        .alert(
            "settings.vocabulary.delete_confirm_title".localized,
            isPresented: $substitutionViewModel.showDeleteConfirmation
        ) {
            Button("common.cancel".localized, role: .cancel) {}
            Button("common.delete".localized, role: .destructive) {
                substitutionViewModel.executeDelete()
            }
        } message: {
            if let entry = substitutionViewModel.entryToDelete {
                Text("settings.vocabulary.delete_confirm_message".localized(with: destinationLabel(for: entry)))
            }
        }
        .alert(
            "settings.dictionary.vocabulary.delete_confirm_title".localized,
            isPresented: $vocabularyViewModel.showDeleteConfirmation
        ) {
            Button("common.cancel".localized, role: .cancel) {}
            Button("common.delete".localized, role: .destructive) {
                vocabularyViewModel.executeDelete()
            }
        } message: {
            if let term = vocabularyViewModel.termToDelete {
                Text("settings.dictionary.vocabulary.delete_confirm_message".localized(with: term.term))
            }
        }
        .onDeleteCommand(perform: handleDeleteKey)
    }

    // MARK: - Substitutions

    private var substitutionsContent: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("settings.vocabulary.applied_order_note".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if substitutionViewModel.conflictingOriginCount > 0 {
                    Label(
                        "settings.vocabulary.legacy_conflicts".localized(with: substitutionViewModel.conflictingOriginCount),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.warning)
                    .accessibilityElement(children: .combine)
                }

                SettingsInlineList(
                    items: substitutionViewModel.groups,
                    emptyText: "settings.vocabulary.empty".localized,
                    containerStyle: .plain
                ) { entry in
                    DictionarySubstitutionRuleRowView(
                        entry: entry,
                        isSelected: selectedEntryID == entry.id,
                        conflictingOriginKeys: substitutionViewModel.conflictingOriginKeys,
                        onSelect: { selectedEntryID = entry.id },
                        onEdit: {
                            selectedEntryID = entry.id
                            entryOriginsInput = entry.origins.joined(separator: ", ")
                            entryDestinationInput = entry.destination
                            substitutionViewModel.startEditingEntry(entry)
                        },
                        onDelete: {
                            selectedEntryID = entry.id
                            substitutionViewModel.confirmDelete(entry)
                        },
                        onRemoveOrigin: { origin in
                            _ = substitutionViewModel.removeOrigin(origin, from: entry)
                        }
                    )
                }

                HStack {
                    Spacer()
                    Button {
                        entryOriginsInput = ""
                        entryDestinationInput = ""
                        substitutionViewModel.startCreatingEntry()
                    } label: {
                        Label("settings.vocabulary.add_rule".localized, systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        } header: {
            SettingsFormSectionHeader(
                title: "settings.dictionary.workflow.substitutions".localized,
                icon: "arrow.2.squarepath"
            )
        }
    }

    private var entryEditorSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entryEditorTitle)
                .font(.title3)
                .bold()

            Text("settings.vocabulary.editor_description".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("settings.vocabulary.find_label".localized)
                    .font(.subheadline)
                TextField("settings.vocabulary.find_placeholder".localized, text: $entryOriginsInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: entryOriginsInput) { _, _ in
                        substitutionViewModel.cancelOriginConflicts()
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("settings.vocabulary.replace_label".localized)
                    .font(.subheadline)
                TextField("settings.vocabulary.replace_placeholder".localized, text: $entryDestinationInput)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: entryDestinationInput) { _, _ in
                        substitutionViewModel.cancelOriginConflicts()
                    }
                Text("settings.vocabulary.empty_destination_help".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if substitutionViewModel.pendingConflicts.isEmpty == false {
                conflictResolutionSection
            } else if let errorKey = entryEditorErrorKey {
                Text(errorKey.localized)
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.error)
            }

            HStack {
                Spacer()
                Button("common.cancel".localized) {
                    substitutionViewModel.dismissEntryEditor()
                }
                .keyboardShortcut(.cancelAction)

                Button("common.save".localized) {
                    _ = substitutionViewModel.saveEntry(
                        origins: entryOriginsInput,
                        destination: entryDestinationInput
                    )
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 520)
    }

    private var conflictResolutionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("settings.vocabulary.conflict_title".localized, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(AppDesignSystem.Colors.warning)

            ForEach(substitutionViewModel.pendingConflicts) { conflict in
                Text("settings.vocabulary.conflict_row".localized(with: conflict.origin, conflict.destination))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Button("settings.vocabulary.conflict_move".localized) {
                _ = substitutionViewModel.resolveOriginConflictsByMoving()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var entryEditorTitle: String {
        substitutionViewModel.editingEntry == nil
            ? "settings.vocabulary.add_rule".localized
            : "settings.vocabulary.edit_rule".localized
    }

    private var entryEditorErrorKey: String? {
        switch substitutionViewModel.editorValidationError {
        case .none, .some(.originConflict): nil
        case .some(.emptyOrigins): "settings.vocabulary.validation.find_required"
        }
    }

    private func syncEditorInputsFromEditingEntry() {
        if let entry = substitutionViewModel.editingEntry {
            entryOriginsInput = entry.origins.joined(separator: ", ")
            entryDestinationInput = entry.destination
        } else {
            entryOriginsInput = ""
            entryDestinationInput = ""
        }
    }

    private func destinationLabel(for entry: VocabularySubstitutionGroup) -> String {
        entry.destination.isEmpty
            ? "settings.vocabulary.removes_text".localized
            : entry.destination
    }

    // MARK: - Vocabulary

    private var vocabularyContent: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("settings.dictionary.vocabulary.description".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("settings.dictionary.vocabulary.term_role".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("settings.dictionary.vocabulary.external_disclosure".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField(
                        "settings.dictionary.vocabulary.add_placeholder".localized,
                        text: $vocabularyViewModel.bulkInputText
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { vocabularyViewModel.addTermsFromBulkInput() }

                    Button("common.add".localized) {
                        vocabularyViewModel.addTermsFromBulkInput()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vocabularyViewModel.bulkInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Spacer()
                    Button {
                        vocabularyViewModel.startEditingTerm()
                    } label: {
                        Label("settings.dictionary.vocabulary.add_entry".localized, systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                if let error = vocabularyViewModel.validationError {
                    Text(validationErrorMessage(for: error))
                        .font(.caption)
                        .foregroundStyle(AppDesignSystem.Colors.error)
                }

                if vocabularyViewModel.addedTermsCount > 0 {
                    Text("settings.dictionary.vocabulary.added_count".localized(with: vocabularyViewModel.addedTermsCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if vocabularyViewModel.terms.isEmpty {
                    Text("settings.dictionary.vocabulary.empty".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(vocabularyViewModel.terms) { term in
                        VocabularyTermRowView(
                            term: term,
                            onEdit: {
                                selectedTermID = term.id
                                vocabularyViewModel.startEditingTerm(term)
                            },
                            onDelete: {
                                selectedTermID = term.id
                                vocabularyViewModel.confirmDelete(term)
                            }
                        )
                    }
                }
            }
        } header: {
            SettingsFormSectionHeader(
                title: "settings.dictionary.workflow.vocabulary".localized,
                icon: "text.book.closed"
            )
        }
    }

    private func syncTermEditorInputs() {
        termInput = vocabularyViewModel.editingTerm?.term ?? ""
        termDefinitionInput = vocabularyViewModel.editingTerm?.definition ?? ""
    }

    private var vocabularySupportSection: some View {
        let selection = settings.resolvedTranscriptionSelection(for: .dictation)
        return Section {
            DictionaryVocabularySupportView(
                providerLabel: selection.provider.displayName,
                modelLabel: selection.provider.displayName(forModelID: selection.selectedModel),
                usesRemoteRecognition: selection.provider.usesRemoteInference,
                support: VocabularyRecognitionSupport(
                    parameter: selection.provider.vocabularyHelper,
                    snapshot: VocabularySnapshot(terms: settings.vocabularyTerms, replacementRules: [])
                )
            )
        } header: {
            SettingsFormSectionHeader(
                title: "settings.dictionary.vocabulary.support.title".localized,
                icon: "waveform.badge.magnifyingglass"
            )
        }
    }

    private func validationErrorMessage(for error: VocabularyTermsSettingsViewModel.ValidationError) -> String {
        switch error {
        case .emptyTerm:
            "settings.dictionary.vocabulary.validation.empty".localized
        case let .duplicatedTerm(term):
            "settings.dictionary.vocabulary.validation.duplicated".localized(with: term)
        }
    }

    // MARK: - Keyboard

    private func handleDeleteKey() {
        switch selectedWorkflow {
        case .substitutions:
            guard let selectedEntryID,
                  let entry = substitutionViewModel.groups.first(where: { $0.id == selectedEntryID })
            else { return }
            substitutionViewModel.confirmDelete(entry)
        case .vocabulary:
            guard let selectedTermID,
                  let term = vocabularyViewModel.terms.first(where: { $0.id == selectedTermID })
            else { return }
            vocabularyViewModel.confirmDelete(term)
        }
    }
}

#Preview {
    DictionarySettingsPage()
}
