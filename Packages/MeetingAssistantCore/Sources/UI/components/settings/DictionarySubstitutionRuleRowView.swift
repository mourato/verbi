import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

struct DictionarySubstitutionRuleRowView: View {
    let rule: VocabularyReplacementRule
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowClickSurface(
                onSingleClick: onSelect,
                onDoubleClick: onEdit,
                content: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.find)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(AppDesignSystem.Colors.primaryTextStyle(isSelected: isSelected))
                            Text(rule.replace.isEmpty ? "settings.vocabulary.empty_replace".localized : rule.replace)
                                .font(.caption)
                                .foregroundStyle(AppDesignSystem.Colors.secondaryTextStyle(isSelected: isSelected))
                        }

                        Spacer()

                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(AppDesignSystem.Colors.secondaryTextStyle(isSelected: isSelected))
                    }
                }
            )
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

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("settings.vocabulary.delete_rule".localized, systemImage: "trash")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("settings.vocabulary.actions".localized)
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

    private var accessibilityLabel: String {
        [rule.find, rule.replace.isEmpty ? "settings.vocabulary.empty_replace".localized : rule.replace]
            .joined(separator: ", ")
    }
}
