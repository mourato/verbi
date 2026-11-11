import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

public struct DictionarySettingsPage: View {
    @StateObject private var viewModel: VocabularySettingsViewModel
    @ObservedObject var settings: AppSettingsStore
    @State private var selectedWordID: UUID?
    @State private var wordInput = ""
    @State private var heardAsInput = ""
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
        _viewModel = StateObject(wrappedValue: VocabularySettingsViewModel(settings: settings))
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
                    Text("settings.dictionary.words.header_description".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } content: {
            wordsContent
            if hasSpelledWords {
                hintsSection
            }
            importExportSection
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
        .sheet(isPresented: $viewModel.showWordEditor) {
            wordEditorSheet
                .onAppear(perform: syncEditorInputsFromEditingWord)
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
            deleteConfirmTitle,
            isPresented: $viewModel.showWordDeleteConfirmation
        ) {
            Button("common.cancel".localized, role: .cancel) {}
            Button("common.delete".localized, role: .destructive) {
                viewModel.executeDeleteWord()
            }
        } message: {
            Text("settings.dictionary.words.delete_confirm_message".localized)
        }
        .onDeleteCommand(perform: handleDeleteKey)
    }

    // MARK: - Words

    private var wordsContent: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.conflictingOriginCount > 0 {
                    Label(
                        "settings.vocabulary.legacy_conflicts".localized(with: viewModel.conflictingOriginCount),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.warning)
                    .accessibilityElement(children: .combine)
                }

                SettingsInlineList(
                    items: viewModel.words,
                    emptyText: "settings.dictionary.words.empty".localized,
                    containerStyle: .plain
                ) { word in
                    DictionaryWordRowView(
                        word: word,
                        isSelected: selectedWordID == word.id,
                        conflictingOriginKeys: viewModel.conflictingOriginKeys,
                        onSelect: { selectedWordID = word.id },
                        onEdit: {
                            selectedWordID = word.id
                            wordInput = word.word
                            heardAsInput = word.heardAs.joined(separator: ", ")
                            viewModel.startEditingWord(word)
                        },
                        onDelete: {
                            selectedWordID = word.id
                            viewModel.confirmDeleteWord(word)
                        },
                        onRemoveVariant: { variant in
                            _ = viewModel.removeVariant(variant, from: word)
                        }
                    )
                }

                HStack {
                    Spacer()
                    Button {
                        wordInput = ""
                        heardAsInput = ""
                        viewModel.startCreatingWord()
                    } label: {
                        Label("settings.dictionary.words.add_word".localized, systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
    }

    private var hasSpelledWords: Bool {
        viewModel.words.contains { !$0.isTextRemoval }
    }

    private var hintsSection: some View {
        let selection = settings.resolvedTranscriptionSelection(for: .dictation)
        return Section {
            DictionaryVocabularySupportView(
                providerLabel: selection.provider.displayName,
                modelLabel: selection.provider.displayName(forModelID: selection.selectedModel),
                support: VocabularyRecognitionSupport(
                    parameter: selection.provider.vocabularyHelper,
                    snapshot: VocabularySnapshot.current(from: settings)
                )
            )
        }
    }

    private var wordEditorSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(wordEditorTitle)
                .font(.title3)
                .bold()

            VocabularyEntryEditorFields(
                viewModel: viewModel,
                wordInput: $wordInput,
                heardAsInput: $heardAsInput,
                onResolveConflicts: {
                    _ = viewModel.resolveOriginConflictsByMoving()
                }
            )

            HStack {
                Spacer()
                Button("common.cancel".localized) {
                    viewModel.dismissWordEditor()
                }
                .keyboardShortcut(.cancelAction)

                Button("common.save".localized) {
                    _ = viewModel.saveWord(word: wordInput, heardAs: heardAsInput)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 520)
    }

    private var wordEditorTitle: String {
        viewModel.editingWord == nil
            ? "settings.dictionary.words.add_word".localized
            : "settings.dictionary.words.edit_word".localized
    }

    private func syncEditorInputsFromEditingWord() {
        if let word = viewModel.editingWord {
            wordInput = word.word
            heardAsInput = word.heardAs.joined(separator: ", ")
        } else {
            wordInput = ""
            heardAsInput = ""
        }
    }

    private var deleteConfirmTitle: String {
        guard let word = viewModel.wordToDelete else {
            return ""
        }
        let label = word.isTextRemoval
            ? word.heardAs.joined(separator: ", ")
            : word.word
        return "settings.dictionary.words.delete_confirm_title".localized(with: label)
    }

    // MARK: - Keyboard

    private func handleDeleteKey() {
        guard let selectedWordID,
              let word = viewModel.words.first(where: { $0.id == selectedWordID })
        else { return }
        viewModel.confirmDeleteWord(word)
    }
}

#Preview {
    DictionarySettingsPage()
}
