import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

struct VocabularyTermEditorSheet: View {
    let isEditing: Bool
    @Binding var term: String
    @Binding var definition: String
    let validationMessage: String?
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isEditing
                ? "settings.dictionary.vocabulary.edit_entry".localized
                : "settings.dictionary.vocabulary.add_entry".localized)
                .font(.title3)
                .bold()

            Text("settings.dictionary.vocabulary.term_hint_role".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("settings.dictionary.vocabulary.term_label".localized)
                    .font(.subheadline)
                TextField("settings.dictionary.vocabulary.add_placeholder".localized, text: $term)
                    .textFieldStyle(.roundedBorder)
            }

            Text("settings.dictionary.vocabulary.term_destination_role".localized)
                .font(.caption2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("settings.dictionary.vocabulary.definition_label".localized)
                    .font(.subheadline)
                TextField("settings.dictionary.vocabulary.definition_placeholder".localized, text: $definition)
                    .textFieldStyle(.roundedBorder)
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.error)
            }

            HStack {
                Spacer()
                Button("common.cancel".localized, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button("common.save".localized, action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 520)
    }
}

#Preview("Vocabulary term editor") {
    VocabularyTermEditorSheet(
        isEditing: false,
        term: .constant("SwiftUI"),
        definition: .constant(""),
        validationMessage: nil,
        onSave: {},
        onCancel: {}
    )
}
