import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

struct DictionarySubstitutionRuleRowView: View {
    let entry: VocabularySubstitutionGroup
    let isSelected: Bool
    let conflictingOriginKeys: Set<String>
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onRemoveOrigin: (String) -> Void

    private var hasConflict: Bool {
        entry.originKeys.isDisjoint(with: conflictingOriginKeys) == false
    }

    var body: some View {
        HStack(spacing: 8) {
            SettingsRowClickSurface(
                onSingleClick: onSelect,
                onDoubleClick: onEdit,
                content: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(destinationLabel)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(AppDesignSystem.Colors.primaryTextStyle(isSelected: isSelected))

                        Text(entry.origins.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(AppDesignSystem.Colors.secondaryTextStyle(isSelected: isSelected))
                            .lineLimit(2)
                            .help(entry.origins.joined(separator: ", "))

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
                accessibilityLabel: "settings.vocabulary.entry_actions".localized(with: destinationLabel)
            ) {
                Button {
                    onEdit()
                } label: {
                    Label("settings.vocabulary.edit_rule".localized, systemImage: "pencil")
                }

                if entry.origins.count > 1 {
                    Menu {
                        ForEach(entry.origins, id: \.self) { origin in
                            Button(origin) {
                                onRemoveOrigin(origin)
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
                    Label("settings.vocabulary.delete_rule".localized, systemImage: "trash")
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
                Label("settings.vocabulary.edit_rule".localized, systemImage: "pencil")
            }

            if entry.origins.count > 1 {
                Menu {
                    ForEach(entry.origins, id: \.self) { origin in
                        Button(origin) {
                            onRemoveOrigin(origin)
                        }
                    }
                } label: {
                    Label("settings.vocabulary.remove_variant".localized, systemImage: "minus.circle")
                }
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("settings.vocabulary.delete_rule".localized, systemImage: "trash")
            }
        }
    }

    private var destinationLabel: String {
        entry.destination.isEmpty
            ? "settings.vocabulary.removes_text".localized
            : entry.destination
    }

    private var accessibilityLabel: String {
        var parts = [destinationLabel, entry.origins.joined(separator: ", ")]
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

#Preview("Substitution entry") {
    VStack(spacing: 0) {
        DictionarySubstitutionRuleRowView(
            entry: VocabularySubstitutionGroup(destination: "Raycast", origins: ["raycast", "reycast"]),
            isSelected: false,
            conflictingOriginKeys: [],
            onSelect: {},
            onEdit: {},
            onDelete: {},
            onRemoveOrigin: { _ in }
        )
        DictionarySubstitutionRuleRowView(
            entry: VocabularySubstitutionGroup(destination: "", origins: ["hum", "uhm"]),
            isSelected: true,
            conflictingOriginKeys: ["hum"],
            onSelect: {},
            onEdit: {},
            onDelete: {},
            onRemoveOrigin: { _ in }
        )
    }
    .padding()
    .frame(width: 420)
}
