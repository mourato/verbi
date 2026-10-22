import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

struct VocabularyTermRowView: View {
    let term: VocabularyTerm
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

            Spacer()

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
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("common.delete".localized, systemImage: "trash")
            }
        }
    }
}
