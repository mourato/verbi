import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

struct VocabularyTermRowView: View {
    let term: VocabularyTerm
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(term.term)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if !term.definition.isEmpty {
                    Text(term.definition)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("settings.dictionary.vocabulary.edit_entry".localized)
            .accessibilityLabel("settings.dictionary.vocabulary.edit_term".localized(with: term.term))

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("common.delete".localized)
            .accessibilityLabel("settings.dictionary.vocabulary.delete_term".localized(with: term.term))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("settings.dictionary.vocabulary.edit_entry".localized, systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("common.delete".localized, systemImage: "trash")
            }
        }
    }
}

#Preview("Vocabulary term") {
    VStack(spacing: 0) {
        VocabularyTermRowView(
            term: VocabularyTerm(term: "SwiftUI", definition: "Apple's declarative UI framework"),
            onEdit: {},
            onDelete: {}
        )
        VocabularyTermRowView(
            term: VocabularyTerm(term: "Metal", definition: ""),
            onEdit: {},
            onDelete: {}
        )
    }
    .padding()
    .frame(width: 420)
}
