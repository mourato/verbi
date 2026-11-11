import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain

/// Word/heard-as fields shared by the settings word sheet and the quick
/// correction editor. Both surfaces therefore render the same validation,
/// conflict list, and consolidation affordances, with the word field first.
struct VocabularyEntryEditorFields: View {
    @ObservedObject var viewModel: VocabularySettingsViewModel
    @Binding var wordInput: String
    @Binding var heardAsInput: String
    var heardAsRequired = false
    var constrainsConflictList = true
    let onResolveConflicts: () -> Void

    @FocusState private var isWordFocused: Bool
    @AccessibilityFocusState private var isWordAccessibilityFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            wordField
            heardAsField

            if viewModel.pendingConflicts.isEmpty == false {
                conflictResolutionSection
            } else if let errorKey = validationErrorKey {
                Text(errorKey.localized)
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.error)
            } else if let duplicate = duplicateWord {
                Text("settings.dictionary.words.validation.duplicated".localized(with: duplicate))
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.error)
            }
        }
        .task {
            isWordFocused = true
            isWordAccessibilityFocused = true
        }
    }

    private var wordField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.dictionary.words.word_label".localized)
                .font(.subheadline)
            TextField("settings.dictionary.words.word_placeholder".localized, text: $wordInput)
                .textFieldStyle(.roundedBorder)
                .focused($isWordFocused)
                .accessibilityLabel("settings.dictionary.words.word_label".localized)
                .accessibilityHint("settings.dictionary.words.word_caption".localized)
                .accessibilityFocused($isWordAccessibilityFocused)
                .onChange(of: wordInput) { _, _ in
                    viewModel.cancelOriginConflicts()
                }
            Text("settings.dictionary.words.word_caption".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var heardAsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.dictionary.words.heard_as_label".localized)
                .font(.subheadline)
            TextField("settings.dictionary.words.heard_as_placeholder".localized, text: $heardAsInput)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("settings.dictionary.words.heard_as_label".localized)
                .accessibilityHint(heardAsCaptionKey.localized)
                .onChange(of: heardAsInput) { _, _ in
                    viewModel.cancelOriginConflicts()
                }
            Text(heardAsCaptionKey.localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var heardAsCaptionKey: String {
        heardAsRequired
            ? "settings.dictionary.words.heard_as_caption_required"
            : "settings.dictionary.words.heard_as_caption"
    }

    private var conflictResolutionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("settings.vocabulary.conflict_title".localized, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(AppDesignSystem.Colors.warning)
                .accessibilityElement(children: .combine)

            if constrainsConflictList, viewModel.pendingConflicts.count > 2 {
                ScrollView {
                    conflictRows
                }
                .frame(maxHeight: 132)
            } else {
                conflictRows
            }

            Button("settings.vocabulary.conflict_move".localized, action: onResolveConflicts)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var conflictRows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.pendingConflicts) { conflict in
                Text("settings.vocabulary.conflict_row".localized(with: conflict.origin, conflict.destination))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var validationErrorKey: String? {
        switch viewModel.editorValidationError {
        case .none, .some(.originConflict), .some(.duplicateWord):
            nil
        case .some(.emptyWordAndHeardAs):
            "settings.dictionary.words.validation.empty"
        case .some(.emptyHeardAs):
            "settings.dictionary.words.validation.heard_as_required"
        case .some(.saveFailed):
            "settings.dictionary.import.error_save_failed"
        }
    }

    private var duplicateWord: String? {
        guard case let .duplicateWord(word) = viewModel.editorValidationError else {
            return nil
        }
        return word
    }
}

#Preview {
    struct PreviewState {
        var word = "Raycast"
        var heardAs = "raycast, reycast"
    }

    return PreviewStateContainer(PreviewState()) { state in
        VocabularyEntryEditorFields(
            viewModel: VocabularySettingsViewModel(),
            wordInput: state.word,
            heardAsInput: state.heardAs,
            onResolveConflicts: {}
        )
        .padding()
        .frame(width: 520)
    }
}
