import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

/// One dictionary word row: the spelling Verbi should write, with its
/// heard-as variants underneath. Text-removal lines show the deleted
/// spellings with a removal note instead.
struct DictionaryWordRowView: View {
    let word: DictionaryWord
    let isSelected: Bool
    let conflictingOriginKeys: Set<String>
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRemoveVariant: (String) -> Void

    private var hasConflict: Bool {
        word.heardAs.contains {
            conflictingOriginKeys.contains(VocabularyNormalization.originKey($0))
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            SettingsRowClickSurface(
                onSingleClick: onSelect,
                onDoubleClick: onEdit,
                content: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(titleLabel)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(AppDesignSystem.Colors.primaryTextStyle(isSelected: isSelected))

                        if let subtitle = subtitleKey {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(AppDesignSystem.Colors.secondaryTextStyle(isSelected: isSelected))
                                .lineLimit(2)
                                .help(subtitleHelp)
                        }

                        if hasConflict {
                            Label("settings.vocabulary.row_conflict".localized, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(
                                    isSelected
                                        ? AppDesignSystem.Colors.primaryTextStyle(isSelected: true)
                                        : AnyShapeStyle(AppDesignSystem.Colors.warning)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("settings.vocabulary.row_hint".localized)

            SettingsContextMenuButton(
                accessibilityLabel: "settings.vocabulary.entry_actions".localized(with: titleLabel)
            ) {
                Button {
                    onEdit()
                } label: {
                    Label("settings.dictionary.words.edit_word".localized, systemImage: "pencil")
                }

                if word.heardAs.count > 1 {
                    Menu {
                        ForEach(word.heardAs, id: \.self) { variant in
                            Button(variant) {
                                onRemoveVariant(variant)
                            }
                        }
                    } label: {
                        Label("settings.vocabulary.remove_variant".localized, systemImage: "minus.circle")
                    }
                }

                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("settings.dictionary.words.delete_word".localized, systemImage: "trash")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
        .contextMenu {
            Button {
                onEdit()
            } label: {
                Label("settings.dictionary.words.edit_word".localized, systemImage: "pencil")
            }

            if word.heardAs.count > 1 {
                Menu {
                    ForEach(word.heardAs, id: \.self) { variant in
                        Button(variant) {
                            onRemoveVariant(variant)
                        }
                    }
                } label: {
                    Label("settings.vocabulary.remove_variant".localized, systemImage: "minus.circle")
                }
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("settings.dictionary.words.delete_word".localized, systemImage: "trash")
            }
        }
    }

    private var titleLabel: String {
        word.isTextRemoval
            ? word.heardAs.joined(separator: ", ")
            : word.word
    }

    private var subtitleKey: String? {
        if word.isTextRemoval {
            return "settings.dictionary.words.removed_from_text".localized
        }
        guard !word.heardAs.isEmpty else { return nil }
        return "settings.dictionary.words.heard_as_prefix".localized(
            with: word.heardAs.joined(separator: ", ")
        )
    }

    private var subtitleHelp: String {
        if word.isTextRemoval {
            return "settings.dictionary.words.removed_from_text".localized
        }
        return word.heardAs.joined(separator: ", ")
    }

    private var accessibilityLabel: String {
        var parts: [String] = if word.isTextRemoval {
            [titleLabel, "settings.dictionary.words.removed_from_text".localized]
        } else if word.heardAs.isEmpty {
            [titleLabel]
        } else {
            ["settings.dictionary.words.row_accessibility".localized(with: titleLabel, word.heardAs.joined(separator: ", "))]
        }
        if hasConflict {
            parts.append("settings.vocabulary.row_conflict".localized)
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var rowBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                .fill(AppDesignSystem.Colors.selectionFill)
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                        .stroke(AppDesignSystem.Colors.selectionStroke, lineWidth: 1)
                )
        } else {
            Color.clear
        }
    }
}

#Preview("Dictionary word") {
    VStack(spacing: 0) {
        DictionaryWordRowView(
            word: DictionaryWord(
                id: UUID(),
                word: "Raycast",
                heardAs: ["raycast", "reycast"],
                termID: nil,
                groupID: UUID()
            ),
            isSelected: false,
            conflictingOriginKeys: [],
            onSelect: {},
            onEdit: {},
            onDelete: {},
            onRemoveVariant: { _ in }
        )
        DictionaryWordRowView(
            word: DictionaryWord(
                id: UUID(),
                word: "",
                heardAs: ["hum", "uhm"],
                termID: nil,
                groupID: UUID()
            ),
            isSelected: true,
            conflictingOriginKeys: ["hum"],
            onSelect: {},
            onEdit: {},
            onDelete: {},
            onRemoveVariant: { _ in }
        )
        DictionaryWordRowView(
            word: DictionaryWord(
                id: UUID(),
                word: "SwiftUI",
                heardAs: [],
                termID: UUID(),
                groupID: nil
            ),
            isSelected: false,
            conflictingOriginKeys: [],
            onSelect: {},
            onEdit: {},
            onDelete: {},
            onRemoveVariant: { _ in }
        )
    }
    .padding()
    .frame(width: 420)
}
