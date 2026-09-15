import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct InstalledAppsSelectionSection: View {
    private let titleKey: String
    private let descriptionKey: String
    private let emptyKey: String
    private let addButtonKey: String
    private let removeButtonKey: String
    private let protectedBadgeKey: String?
    private let icon: String
    private let onAddApp: (() -> Void)?
    @ObservedObject private var viewModel: InstalledAppsSelectionViewModel

    public init(
        titleKey: String,
        descriptionKey: String,
        emptyKey: String,
        addButtonKey: String,
        removeButtonKey: String = "settings.markdown_targets.remove",
        protectedBadgeKey: String? = nil,
        icon: String,
        onAddApp: (() -> Void)? = nil,
        viewModel: InstalledAppsSelectionViewModel
    ) {
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.emptyKey = emptyKey
        self.addButtonKey = addButtonKey
        self.removeButtonKey = removeButtonKey
        self.protectedBadgeKey = protectedBadgeKey
        self.icon = icon
        self.onAddApp = onAddApp
        self.viewModel = viewModel
    }

    public var body: some View {
        // Form-hosted collection: title + list only. No DSCard plate — the
        // owning Form/Section (or expandable) already supplies hierarchy.
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(AppDesignSystem.Colors.accent)

                Text(titleKey.localized)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                if !descriptionKey.localized.isEmpty {
                    DSInfoPopoverButton(
                        title: titleKey.localized,
                        message: descriptionKey.localized
                    )
                }
            }
            .padding(.leading, 4)

            InstalledAppsSelectionList(
                emptyKey: emptyKey,
                addButtonKey: addButtonKey,
                removeButtonKey: removeButtonKey,
                protectedBadgeKey: protectedBadgeKey,
                onAddApp: onAddApp,
                viewModel: viewModel
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

public struct InstalledAppsSelectionList: View {
    private let emptyKey: String
    private let addButtonKey: String
    private let removeButtonKey: String
    private let protectedBadgeKey: String?
    private let onAddApp: (() -> Void)?
    @ObservedObject private var viewModel: InstalledAppsSelectionViewModel

    public init(
        emptyKey: String,
        addButtonKey: String,
        removeButtonKey: String = "settings.markdown_targets.remove",
        protectedBadgeKey: String? = nil,
        onAddApp: (() -> Void)? = nil,
        viewModel: InstalledAppsSelectionViewModel
    ) {
        self.emptyKey = emptyKey
        self.addButtonKey = addButtonKey
        self.removeButtonKey = removeButtonKey
        self.protectedBadgeKey = protectedBadgeKey
        self.onAddApp = onAddApp
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.installedApps.isEmpty {
                Text(emptyKey.localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.installedApps.enumerated()), id: \.element.id) { index, app in
                        appRow(app)

                        if index < viewModel.installedApps.count - 1 {
                            Divider()
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
            }

            HStack {
                Spacer()
                Button {
                    if let onAddApp {
                        onAddApp()
                    } else {
                        viewModel.addApp()
                    }
                } label: {
                    Label(addButtonKey.localized, systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .onAppear {
            viewModel.refreshTargets()
        }
    }

    private func appRow(_ app: InstalledAppItem) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .padding(AppDesignSystem.Layout.compactInset)
                .background(AppDesignSystem.Colors.subtleFill)
                .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if app.isRemovable {
                Button(role: .destructive) {
                    viewModel.removeApp(bundleIdentifier: app.bundleIdentifier)
                } label: {
                    Image(systemName: "minus.circle")
                        .accessibilityLabel(removeButtonKey.localized)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppDesignSystem.Colors.error)
                .controlSize(.regular)
            } else if let protectedBadgeKey {
                DSBadge(protectedBadgeKey.localized, kind: .neutral)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#Preview {
    PreviewStateContainer(AppSettingsStore.defaultMarkdownTargetBundleIdentifiers) { identifiers in
        InstalledAppsSelectionSection(
            titleKey: "settings.markdown_targets.title",
            descriptionKey: "settings.markdown_targets.description",
            emptyKey: "settings.markdown_targets.empty",
            addButtonKey: "settings.markdown_targets.add",
            icon: "textformat",
            viewModel: InstalledAppsSelectionViewModel(
                defaultBundleIdentifiers: identifiers.wrappedValue,
                hasConfigured: { true },
                loadBundleIdentifiers: { identifiers.wrappedValue },
                saveBundleIdentifiers: { identifiers.wrappedValue = $0 }
            )
        )
        .padding()
    }
}

#Preview {
    PreviewStateContainer(AppSettingsStore.defaultMarkdownTargetBundleIdentifiers) { identifiers in
        InstalledAppsSelectionList(
            emptyKey: "settings.markdown_targets.empty",
            addButtonKey: "settings.markdown_targets.add",
            viewModel: InstalledAppsSelectionViewModel(
                defaultBundleIdentifiers: identifiers.wrappedValue,
                hasConfigured: { true },
                loadBundleIdentifiers: { identifiers.wrappedValue },
                saveBundleIdentifiers: { identifiers.wrappedValue = $0 }
            )
        )
        .padding()
    }
}
