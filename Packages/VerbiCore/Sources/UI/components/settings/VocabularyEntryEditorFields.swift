import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain

/// Origin/destination fields shared by the settings entry editor and the quick
/// correction editor. Both surfaces therefore render the same validation,
/// conflict list, and consolidation affordances.
struct VocabularyEntryEditorFields: View {
    @ObservedObject var viewModel: VocabularySettingsViewModel
    @Binding var originsInput: String
    @Binding var destinationInput: String
    var focusesOriginsOnAppear = false
    var constrainsConflictList = true
    var originAccessibilityHintKey = "settings.vocabulary.find_hint"
    var destinationAccessibilityHintKey = "settings.vocabulary.replace_hint"
    let onResolveConflicts: () -> Void

    @FocusState private var isOriginsFocused: Bool
    @AccessibilityFocusState private var isOriginsAccessibilityFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            originsField
            destinationField

            if viewModel.pendingConflicts.isEmpty == false {
                conflictResolutionSection
            } else if let errorKey = validationErrorKey {
                Text(errorKey.localized)
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.error)
            }
        }
        .task {
            if focusesOriginsOnAppear {
                isOriginsFocused = true
                isOriginsAccessibilityFocused = true
            }
        }
    }

    private var originsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.vocabulary.find_label".localized)
                .font(.subheadline)
            TextField("settings.vocabulary.find_placeholder".localized, text: $originsInput)
                .textFieldStyle(.roundedBorder)
                .focused($isOriginsFocused)
                .accessibilityLabel("settings.vocabulary.find_label".localized)
                .accessibilityHint(originAccessibilityHintKey.localized)
                .accessibilityFocused($isOriginsAccessibilityFocused)
                .onChange(of: originsInput) { _, _ in
                    viewModel.cancelOriginConflicts()
                }
        }
    }

    private var destinationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.vocabulary.replace_label".localized)
                .font(.subheadline)
            TextField("settings.vocabulary.replace_placeholder".localized, text: $destinationInput)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("settings.vocabulary.replace_label".localized)
                .accessibilityHint(destinationAccessibilityHintKey.localized)
                .onChange(of: destinationInput) { _, _ in
                    viewModel.cancelOriginConflicts()
                }
            Text("settings.vocabulary.empty_destination_help".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        case .none, .some(.originConflict): nil
        case .some(.emptyOrigins): "settings.vocabulary.validation.find_required"
        }
    }
}

#Preview {
    struct PreviewState {
        var origins = "raycast, reycast"
        var destination = "Raycast"
    }

    return PreviewStateContainer(PreviewState()) { state in
        VocabularyEntryEditorFields(
            viewModel: VocabularySettingsViewModel(),
            originsInput: state.origins,
            destinationInput: state.destination,
            onResolveConflicts: {}
        )
        .padding()
        .frame(width: 520)
    }
}
