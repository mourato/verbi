import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain

/// One reviewed correction: what was written and the spelling it should
/// become. The corrected spelling reaches future snapshots as a hint through
/// the unified hint list, so there is no separate vocabulary choice.
struct VocabularyQuickTeachView: View {
    @StateObject private var viewModel = VocabularySettingsViewModel()
    @State private var wordInput = ""
    @State private var heardAsInput = ""
    @State private var errorMessage: String?

    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    VocabularyEntryEditorFields(
                        viewModel: viewModel,
                        wordInput: $wordInput,
                        heardAsInput: $heardAsInput,
                        heardAsRequired: true,
                        constrainsConflictList: false,
                        onResolveConflicts: stageConflictMove
                    )
                    if viewModel.hasPendingQuickMove {
                        draftNotice
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(AppDesignSystem.Colors.error)
                            .accessibilityElement(children: .combine)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            actions
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 520, minHeight: 360)
        .onChange(of: wordInput) { _, _ in errorMessage = nil }
        .onChange(of: heardAsInput) { _, _ in errorMessage = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("settings.dictionary.quick_teach.title".localized)
                .font(.title3)
                .bold()
                .accessibilityAddTraits(.isHeader)
            Text("settings.dictionary.quick_teach.description".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var draftNotice: some View {
        Label("settings.dictionary.quick_teach.move_pending".localized, systemImage: "arrow.triangle.2.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        HStack {
            Spacer()
            Button("common.cancel".localized) {
                viewModel.cancelQuickTeachDraft()
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("common.save".localized, action: save)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func save() {
        apply(
            viewModel.saveQuickTeach(
                origins: heardAsInput,
                destination: wordInput
            )
        )
    }

    private func stageConflictMove() {
        guard viewModel.stageQuickTeachConflictMove() else {
            return
        }
        errorMessage = nil
    }

    private func apply(_ outcome: VocabularySettingsViewModel.QuickTeachOutcome) {
        switch outcome {
        case .saved:
            onDismiss()
        case .invalid, .conflicts:
            errorMessage = nil
        case let .failed(error):
            errorMessage = error.errorDescription
                ?? "settings.dictionary.quick_teach.error_persist".localized
        }
    }
}

#Preview {
    VocabularyQuickTeachView(onDismiss: {})
        .frame(width: 560, height: 470)
}
