import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct StylesSettingsTab: View {
    @ObservedObject private var viewModel: DictationStylesSettingsViewModel
    @ObservedObject private var aiSettingsViewModel: AISettingsViewModel
    private let focusedStyle: FocusState<DictationStyleFocusTarget?>.Binding?
    private let accessibilityFocusedStyle: AccessibilityFocusState<DictationStyleFocusTarget?>.Binding?
    private let isListFocusEnabled: Bool
    @State private var selectedStyleID: UUID?
    private let onOpenEditor: ((UUID?) -> Void)?
    private let onOpenAssistant: (() -> Void)?
    private let onOpenIntegrations: (() -> Void)?

    public init(
        viewModel: DictationStylesSettingsViewModel,
        aiSettingsViewModel: AISettingsViewModel,
        focusedStyle: FocusState<DictationStyleFocusTarget?>.Binding? = nil,
        accessibilityFocusedStyle: AccessibilityFocusState<DictationStyleFocusTarget?>.Binding? = nil,
        isListFocusEnabled: Bool = true,
        onOpenEditor: ((UUID?) -> Void)? = nil,
        onOpenAssistant: (() -> Void)? = nil,
        onOpenIntegrations: (() -> Void)? = nil
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _aiSettingsViewModel = ObservedObject(wrappedValue: aiSettingsViewModel)
        self.focusedStyle = focusedStyle
        self.accessibilityFocusedStyle = accessibilityFocusedStyle
        self.isListFocusEnabled = isListFocusEnabled
        self.onOpenEditor = onOpenEditor
        self.onOpenAssistant = onOpenAssistant
        self.onOpenIntegrations = onOpenIntegrations
    }

    public var body: some View {
        SettingsFormPage {
            VStack(alignment: .leading, spacing: 4) {
                SettingsFormSectionHeader(
                    title: "settings.section.modes".localized,
                    icon: "paintpalette"
                )

                Text("settings.styles.description".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } content: {
            Section {
                stylesList

                HStack {
                    Spacer()
                    Button("settings.styles.add".localized, systemImage: "plus") {
                        onOpenEditor?(nil)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .stylesAddFocus(
                        focusedStyle: focusedStyle,
                        accessibilityFocusedStyle: accessibilityFocusedStyle,
                        isFocusEnabled: isListFocusEnabled
                    )
                }
            }

            if onOpenAssistant != nil || onOpenIntegrations != nil {
                Section {
                    if let onOpenAssistant {
                        SettingsListDrillDownButtonRow(
                            title: "settings.section.assistant".localized,
                            subtitle: "settings.assistant.header_desc".localized,
                            action: onOpenAssistant
                        )
                        .stylesTargetFocus(
                            focusedStyle: focusedStyle,
                            accessibilityFocusedStyle: accessibilityFocusedStyle,
                            target: .assistant,
                            isFocusEnabled: isListFocusEnabled
                        )
                    }

                    if let onOpenIntegrations {
                        SettingsListDrillDownButtonRow(
                            title: "settings.section.integrations".localized,
                            subtitle: "settings.integrations.header_desc".localized,
                            action: onOpenIntegrations
                        )
                        .stylesTargetFocus(
                            focusedStyle: focusedStyle,
                            accessibilityFocusedStyle: accessibilityFocusedStyle,
                            target: .integrations,
                            isFocusEnabled: isListFocusEnabled
                        )
                    }
                } header: {
                    SettingsFormSectionHeader(
                        title: "settings.section.ai".localized,
                        icon: "sparkles"
                    )
                }
            }
        }
        .onDeleteCommand(perform: deleteSelectedStyle)
        .accessibilityHidden(!isListFocusEnabled)
    }

    @ViewBuilder
    private var stylesList: some View {
        if viewModel.styles.isEmpty {
            Text("settings.styles.empty".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            SettingsInlineList(
                items: viewModel.styles,
                emptyText: "settings.styles.empty".localized,
                containerStyle: .plain
            ) { style in
                styleRow(style)
            }
        }
    }

    private func styleRow(_ style: DictationStyle) -> some View {
        HStack(spacing: 12) {
            SettingsRowClickSurface(
                onSingleClick: {
                    selectedStyleID = style.id
                },
                onDoubleClick: {
                    selectedStyleID = style.id
                    openEditor(for: style)
                },
                content: {
                    styleRowContent(style, isSelected: selectedStyleID == style.id)
                }
            )

            styleActionsMenu(for: style, isSelected: selectedStyleID == style.id)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selectionBackground(isSelected: selectedStyleID == style.id))
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
        .contextMenu {
            Button {
                selectedStyleID = style.id
                openEditor(for: style)
            } label: {
                Label("settings.styles.edit".localized, systemImage: "pencil")
            }

            Button(role: .destructive) {
                selectedStyleID = style.id
                viewModel.deleteStyle(id: style.id)
            } label: {
                Label("settings.styles.remove".localized, systemImage: "trash")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(styleAccessibilityLabel(style))
        .accessibilityAddTraits(selectedStyleID == style.id ? .isSelected : [])
        .stylesFocus(
            focusedStyle: focusedStyle,
            accessibilityFocusedStyle: accessibilityFocusedStyle,
            styleID: style.id,
            isFocusEnabled: isListFocusEnabled
        )
    }

    private func styleRowContent(_ style: DictationStyle, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            DictationStyleIconView(
                iconSymbol: style.normalizedIconSymbol,
                size: 28,
                accessibilityLabel: styleDisplayName(style)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(styleDisplayName(style))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppDesignSystem.Colors.primaryTextStyle(isSelected: isSelected))

                Text(styleTargetCountText(for: style))
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.secondaryTextStyle(isSelected: isSelected))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            styleTargetIcons(for: style)

            styleSummary(for: style, isSelected: isSelected)
        }
    }

    private func styleActionsMenu(for style: DictationStyle, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Button("settings.styles.edit".localized, systemImage: "pencil") {
                selectedStyleID = style.id
                openEditor(for: style)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .focusable(isListFocusEnabled)
            .help("settings.styles.edit".localized)
            .accessibilityLabel("settings.styles.edit".localized)

            SettingsContextMenuButton(
                accessibilityLabel: "settings.styles.actions".localized,
                symbolColor: isSelected
                    ? AppDesignSystem.Colors.selectedContentSecondaryForeground
                    : .secondary
            ) {
                Button {
                    selectedStyleID = style.id
                    openEditor(for: style)
                } label: {
                    Label("settings.styles.edit".localized, systemImage: "pencil")
                }

                Button(role: .destructive) {
                    selectedStyleID = style.id
                    viewModel.deleteStyle(id: style.id)
                } label: {
                    Label("settings.styles.remove".localized, systemImage: "trash")
                }
            }
            .focusable(isListFocusEnabled)
        }
    }

    private func styleSummary(for style: DictationStyle, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            if style.forceMarkdownOutput {
                Text("settings.styles.summary.markdown".localized)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(AppDesignSystem.Colors.subtleFill2)
                    )
                    .foregroundStyle(AppDesignSystem.Colors.secondaryTextStyle(isSelected: isSelected))
            }

            if style.outputLanguage != .original {
                Text(style.outputLanguage.flagEmoji)
                    .font(.headline)
                    .accessibilityLabel(style.outputLanguage.localizedName)
            }

            Text(style.replaceBasePrompt ? "settings.styles.summary.replace".localized : "settings.styles.summary.append".localized)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(AppDesignSystem.Colors.subtleFill2)
                )
                .foregroundStyle(AppDesignSystem.Colors.secondaryTextStyle(isSelected: isSelected))
        }
    }

    private func styleDisplayName(_ style: DictationStyle) -> String {
        let trimmedName = style.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "settings.styles.untitled".localized : trimmedName
    }

    private func styleTargetCountText(for style: DictationStyle) -> String {
        let count = style.targets.count
        switch count {
        case 0:
            return "settings.styles.empty".localized
        case 1:
            return "settings.styles.targets.count.one".localized
        default:
            return "settings.styles.targets.count.many".localized(with: count)
        }
    }

    private func styleTargetIcons(for style: DictationStyle) -> some View {
        let displayedTargets = Array(style.targets.prefix(3))

        return HStack(spacing: -4) {
            ForEach(Array(displayedTargets.enumerated()), id: \.offset) { _, target in
                styleTargetIcon(for: target)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(AppDesignSystem.Colors.subtleFill2)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(AppDesignSystem.Colors.selectionStroke.opacity(0.4), lineWidth: 0.5)
                    )
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func styleTargetIcon(for target: DictationStyleTarget) -> some View {
        switch target {
        case let .app(bundleIdentifier):
            AppIconView(
                bundleIdentifier: bundleIdentifier,
                fallbackSystemName: "app.fill",
                size: 16,
                cornerRadius: 5
            )
        case .website:
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppDesignSystem.Colors.iconHighlight)
        }
    }

    private func styleAccessibilityLabel(_ style: DictationStyle) -> String {
        [
            styleDisplayName(style),
            styleTargetCountText(for: style),
            style.replaceBasePrompt ? "settings.styles.summary.replace".localized : "settings.styles.summary.append".localized
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    @ViewBuilder
    private func selectionBackground(isSelected: Bool) -> some View {
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

    private func openEditor(for style: DictationStyle) {
        onOpenEditor?(style.id)
    }

    private func deleteSelectedStyle() {
        guard let selectedStyleID else { return }
        viewModel.deleteStyle(id: selectedStyleID)
    }
}

#Preview {
    StylesSettingsPreview()
}

private struct StylesSettingsPreview: View {
    @FocusState private var focusedStyle: DictationStyleFocusTarget?
    @AccessibilityFocusState private var accessibilityFocusedStyle: DictationStyleFocusTarget?

    var body: some View {
        StylesSettingsTab(
            viewModel: DictationStylesSettingsViewModel(),
            aiSettingsViewModel: AISettingsViewModel(settings: AppSettingsStore.shared),
            focusedStyle: $focusedStyle,
            accessibilityFocusedStyle: $accessibilityFocusedStyle
        )
    }
}

private extension View {
    @ViewBuilder
    func stylesTargetFocus(
        focusedStyle: FocusState<DictationStyleFocusTarget?>.Binding?,
        accessibilityFocusedStyle: AccessibilityFocusState<DictationStyleFocusTarget?>.Binding?,
        target: DictationStyleFocusTarget,
        isFocusEnabled: Bool
    ) -> some View {
        // While the editor drawer owns keyboard focus, keep list rows out of the
        // focus cycle so clearing FocusState does not land on the first mode.
        let focusableView = focusable(isFocusEnabled)
            .focusEffectDisabled()

        if !isFocusEnabled {
            focusableView
        } else if let focusedStyle, let accessibilityFocusedStyle {
            focusableView
                .accessibilityFocused(accessibilityFocusedStyle, equals: target)
                .focused(focusedStyle, equals: target)
        } else if let focusedStyle {
            focusableView
                .focused(focusedStyle, equals: target)
        } else if let accessibilityFocusedStyle {
            focusableView
                .accessibilityFocused(accessibilityFocusedStyle, equals: target)
        } else {
            focusableView
        }
    }

    func stylesFocus(
        focusedStyle: FocusState<DictationStyleFocusTarget?>.Binding?,
        accessibilityFocusedStyle: AccessibilityFocusState<DictationStyleFocusTarget?>.Binding?,
        styleID: UUID,
        isFocusEnabled: Bool
    ) -> some View {
        stylesTargetFocus(
            focusedStyle: focusedStyle,
            accessibilityFocusedStyle: accessibilityFocusedStyle,
            target: .style(styleID),
            isFocusEnabled: isFocusEnabled
        )
    }

    func stylesAddFocus(
        focusedStyle: FocusState<DictationStyleFocusTarget?>.Binding?,
        accessibilityFocusedStyle: AccessibilityFocusState<DictationStyleFocusTarget?>.Binding?,
        isFocusEnabled: Bool
    ) -> some View {
        stylesTargetFocus(
            focusedStyle: focusedStyle,
            accessibilityFocusedStyle: accessibilityFocusedStyle,
            target: .addButton,
            isFocusEnabled: isFocusEnabled
        )
    }
}
