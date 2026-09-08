import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Monitored apps and web targets editor hosted in a footerless `ModeEditorDrawer` side panel.
public struct MeetingMonitoringSettingsContent: View {
    @ObservedObject private var monitoredAppsViewModel: InstalledAppsSelectionViewModel
    @ObservedObject private var webTargetsViewModel: WebMeetingTargetsViewModel
    @Binding private var selectedWebTargetID: UUID?
    private let fallbackBrowserBundleIdentifiers: [String]
    private let onAddApp: () -> Void
    private let onClose: () -> Void

    public init(
        monitoredAppsViewModel: InstalledAppsSelectionViewModel,
        webTargetsViewModel: WebMeetingTargetsViewModel,
        selectedWebTargetID: Binding<UUID?>,
        fallbackBrowserBundleIdentifiers: [String],
        onAddApp: @escaping () -> Void,
        onClose: @escaping () -> Void,
    ) {
        self.monitoredAppsViewModel = monitoredAppsViewModel
        self.webTargetsViewModel = webTargetsViewModel
        _selectedWebTargetID = selectedWebTargetID
        self.fallbackBrowserBundleIdentifiers = fallbackBrowserBundleIdentifiers
        self.onAddApp = onAddApp
        self.onClose = onClose
    }

    public var body: some View {
        ModeEditorDrawer(
            headerStyle: .close,
            title: "settings.meetings.monitoring_access.title".localized,
            iconSymbol: "app.badge.checkmark",
            onClose: onClose,
        ) {
            Form {
                Section {
                    monitoringTargetsContent
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var monitoringTargetsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstalledAppsSelectionSection(
                titleKey: "settings.general.monitored_apps",
                descriptionKey: "settings.general.monitored_apps_desc",
                emptyKey: "settings.general.monitored_apps_empty",
                addButtonKey: "settings.general.monitored_apps_add",
                icon: "app.badge",
                onAddApp: onAddApp,
                viewModel: monitoredAppsViewModel,
            )

            webTargetsSection
        }
    }

    private var webTargetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(AppDesignSystem.Colors.accent)
                Text("settings.meetings.web_targets.title".localized)
                    .font(.headline)
                Spacer()
                DSInfoPopoverButton(
                    title: "settings.meetings.web_targets.title".localized,
                    message: "settings.meetings.web_targets.desc".localized,
                )
            }

            SettingsInlineList(
                items: webTargetsViewModel.targets,
                emptyText: "settings.meetings.web_targets.empty".localized,
                containerStyle: .plain,
            ) { target in
                webTargetRow(target)
            }

            HStack {
                Spacer()
                Button {
                    webTargetsViewModel.addTarget()
                } label: {
                    Label("settings.meetings.web_targets.add".localized, systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
    }

    private func webTargetRow(_ target: WebMeetingTarget) -> some View {
        let isSelected = selectedWebTargetID == target.id

        return HStack(spacing: 12) {
            SettingsRowClickSurface(
                onSingleClick: {
                    selectedWebTargetID = target.id
                },
                onDoubleClick: {
                    selectedWebTargetID = target.id
                    webTargetsViewModel.editTarget(target)
                },
                content: {
                    webTargetRowContent(target: target, isSelected: isSelected)
                },
            )

            SettingsContextMenuButton(
                accessibilityLabel: "settings.rules_per_app.actions".localized,
                symbolColor: isSelected
                    ? AppDesignSystem.Colors.selectedContentSecondaryForeground
                    : .secondary,
                menuContent: {
                    webTargetMenuButtons(for: target)
                },
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selectionBackground(isSelected: isSelected))
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
        .contextMenu {
            webTargetMenuButtons(for: target)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(webTargetAccessibilityLabel(for: target))
        .accessibilityHint("settings.rules_per_app.actions".localized)
    }

    private func webTargetRowContent(target: WebMeetingTarget, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: target.app.icon)
                .font(.title3)
                .foregroundStyle(target.app.color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(target.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(AppDesignSystem.Colors.primaryTextStyle(isSelected: isSelected))
                Text(target.urlPatterns.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.secondaryTextStyle(isSelected: isSelected))
                Text(browserNames(from: target.browserBundleIdentifiers))
                    .font(.caption2)
                    .foregroundStyle(AppDesignSystem.Colors.secondaryTextStyle(isSelected: isSelected))
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func webTargetMenuButtons(for target: WebMeetingTarget) -> some View {
        Button {
            selectedWebTargetID = target.id
            webTargetsViewModel.editTarget(target)
        } label: {
            Label("settings.meetings.web_targets.edit".localized, systemImage: "pencil")
        }

        Button(role: .destructive) {
            selectedWebTargetID = target.id
            webTargetsViewModel.confirmDelete(target)
        } label: {
            Label("settings.meetings.web_targets.delete".localized, systemImage: "trash")
        }
    }

    private func browserNames(from bundleIdentifiers: [String]) -> String {
        WebTargetBrowserNamesFormatter.formattedNames(
            bundleIdentifiers: bundleIdentifiers,
            fallbackBundleIdentifiers: fallbackBrowserBundleIdentifiers,
            localizedListKey: "settings.meetings.web_targets.browsers",
        )
    }

    @ViewBuilder
    private func selectionBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                .fill(AppDesignSystem.Colors.selectionFill)
                .overlay(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                        .stroke(AppDesignSystem.Colors.selectionStroke, lineWidth: 1),
                )
        } else {
            Color.clear
        }
    }

    private func webTargetAccessibilityLabel(for target: WebMeetingTarget) -> String {
        [target.displayName, target.urlPatterns.joined(separator: ", "), browserNames(from: target.browserBundleIdentifiers)]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

#Preview("Meeting Monitoring Drawer") {
    MeetingMonitoringSettingsContent(
        monitoredAppsViewModel: InstalledAppsSelectionViewModel(
            defaultBundleIdentifiers: [],
            hasConfigured: { false },
            loadBundleIdentifiers: { [] },
            saveBundleIdentifiers: { _ in },
        ),
        webTargetsViewModel: WebMeetingTargetsViewModel(),
        selectedWebTargetID: .constant(nil),
        fallbackBrowserBundleIdentifiers: [],
        onAddApp: {},
        onClose: {},
    )
    .frame(width: 400, height: 640)
}
