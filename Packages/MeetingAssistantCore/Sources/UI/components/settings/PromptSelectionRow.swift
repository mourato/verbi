import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct PromptSelectionRow<MenuContent: View>: View {
    private let iconSystemName: String
    private let title: String
    private let description: String?
    private let isSelected: Bool
    private let onSelect: (() -> Void)?
    private let onDoubleClick: (() -> Void)?
    private let unselectedStrokeColor: Color
    private let showMenu: Bool
    private let preserveMenuSpacing: Bool
    private let menuAccessibilityLabel: String
    private let menuAccessibilityHint: String?
    private let menuContent: () -> MenuContent

    public init(
        iconSystemName: String,
        title: String,
        description: String?,
        isSelected: Bool,
        onSelect: (() -> Void)?,
        onDoubleClick: (() -> Void)? = nil,
        unselectedStrokeColor: Color = .clear,
        showMenu: Bool = true,
        preserveMenuSpacing: Bool = false,
        menuAccessibilityLabel: String,
        menuAccessibilityHint: String? = nil,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.iconSystemName = iconSystemName
        self.title = title
        self.description = description
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDoubleClick = onDoubleClick
        self.unselectedStrokeColor = unselectedStrokeColor
        self.showMenu = showMenu
        self.preserveMenuSpacing = preserveMenuSpacing
        self.menuAccessibilityLabel = menuAccessibilityLabel
        self.menuAccessibilityHint = menuAccessibilityHint
        self.menuContent = menuContent
    }

    public var body: some View {
        HStack(spacing: 12) {
            clickableContent

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppDesignSystem.Colors.success)
            }

            trailingMenu
        }
        .padding(10)
        .background(isSelected ? AppDesignSystem.Colors.selectionFill : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesignSystem.Layout.cardCornerRadius)
                .stroke(isSelected ? AppDesignSystem.Colors.selectionStroke : unselectedStrokeColor, lineWidth: 1)
        )
        .contextMenu {
            menuContent()
        }
    }

    @ViewBuilder
    private var clickableContent: some View {
        if onSelect != nil || onDoubleClick != nil {
            SettingsRowClickSurface(
                onSingleClick: onSelect,
                onDoubleClick: onDoubleClick
            ) {
                mainContent
            }
        } else {
            mainContent
        }
    }

    private var mainContent: some View {
        HStack(spacing: 12) {
            promptIcon
            promptInfo
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private var promptIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                .fill(isSelected ? AppDesignSystem.Colors.accent : AppDesignSystem.Colors.subtleFill)
                .frame(width: 36, height: 36)

            Image(systemName: iconSystemName)
                .font(.subheadline)
                .foregroundStyle(isSelected ? AppDesignSystem.Colors.onAccent : .primary)
        }
    }

    private var promptInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.body)
                .fontWeight(isSelected ? .bold : .medium)
                .foregroundStyle(AppDesignSystem.Colors.primaryTextStyle(isSelected: isSelected))

            if let description {
                Text(description)
                    .font(.caption2)
                    .foregroundStyle(AppDesignSystem.Colors.secondaryTextStyle(isSelected: isSelected))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trailingMenu: some View {
        if showMenu {
            SettingsContextMenuButton(
                accessibilityLabel: menuAccessibilityLabel,
                accessibilityHint: menuAccessibilityHint,
                symbolColor: isSelected
                    ? AppDesignSystem.Colors.selectedContentSecondaryForeground
                    : .secondary
            ) {
                menuContent()
            }
        } else if preserveMenuSpacing {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
                .opacity(0)
        }
    }
}

#Preview {
    PromptSelectionRow(
        iconSystemName: "sparkles",
        title: "Example Prompt",
        description: "Description",
        isSelected: true,
        onSelect: {},
        onDoubleClick: {},
        showMenu: true,
        menuAccessibilityLabel: "transcription.ai_actions".localized
    ) {
        Button("Select") {}
    }
    .padding()
}
