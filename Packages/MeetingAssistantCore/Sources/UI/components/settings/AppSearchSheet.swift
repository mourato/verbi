import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

// preview-check: ignore — app search sheet requires the owning catalog fixture.

public struct AppSearchSheet: View {
    @ObservedObject private var viewModel: InstalledAppsSelectionViewModel
    @Binding private var isPresented: Bool

    private let titleKey: String
    private let descriptionKey: String?
    private let addButtonKey: String
    private let searchPlaceholderKey: String
    private let loadingKey: String
    private let emptyResultsKey: String

    @State private var appCatalog: [InstalledApplicationRecord] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var hasLoaded = false

    public init(
        viewModel: InstalledAppsSelectionViewModel,
        isPresented: Binding<Bool>,
        titleKey: String,
        descriptionKey: String? = nil,
        addButtonKey: String,
        searchPlaceholderKey: String = "settings.styles.editor.app_search",
        loadingKey: String = "settings.styles.editor.loading_apps",
        emptyResultsKey: String = "settings.styles.editor.app_results_empty"
    ) {
        self.viewModel = viewModel
        _isPresented = isPresented
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.addButtonKey = addButtonKey
        self.searchPlaceholderKey = searchPlaceholderKey
        self.loadingKey = loadingKey
        self.emptyResultsKey = emptyResultsKey
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(titleKey.localized)
                    .font(.headline)
                Spacer()
                Button("common.cancel".localized) {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Divider()

            if let descriptionKey {
                Text(descriptionKey.localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField(searchPlaceholderKey.localized, text: $searchText)
                .textFieldStyle(.roundedBorder)

            if isLoading {
                SettingsStateBlock(
                    kind: .loading,
                    title: loadingKey.localized,
                    message: nil
                )
            } else if filteredCatalog.isEmpty {
                Text(emptyResultsKey.localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredCatalog.prefix(12)) { app in
                            appRow(app)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }

            Spacer()
        }
        .padding()
        .frame(width: 480, height: 440)
        .onAppear {
            loadIfNeeded()
        }
    }

    private var filteredCatalog: [InstalledApplicationRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let selectedKeys = Set(
            viewModel.installedApps.map {
                $0.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )

        let candidates = appCatalog.filter { app in
            !selectedKeys.contains(app.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }

        guard !query.isEmpty else { return candidates }
        return candidates.filter { app in
            app.displayName.localizedCaseInsensitiveContains(query)
                || app.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    private func appRow(_ app: InstalledApplicationRecord) -> some View {
        HStack(spacing: 10) {
            AppIconView(
                bundleIdentifier: app.bundleIdentifier,
                fallbackSystemName: "app.fill",
                size: 24,
                cornerRadius: 6
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(app.displayName)
                    .font(.subheadline)
                Text(app.bundleIdentifier)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(addButtonKey.localized) {
                viewModel.addApp(bundleIdentifier: app.bundleIdentifier)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppDesignSystem.Colors.subtleFill2)
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true

        Task {
            let discovered = await Task.detached(priority: .userInitiated) {
                AppCatalogDiscovery.discoverInstalledApplications()
            }.value
            appCatalog = discovered
            isLoading = false
        }
    }
}
