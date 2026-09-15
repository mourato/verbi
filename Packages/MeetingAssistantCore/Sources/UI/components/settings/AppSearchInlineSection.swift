import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

// preview-check: ignore — inline search requires the owning Settings search state.

public struct AppSearchInlineSection: View {
    private let appCatalog: [InstalledApplicationRecord]
    private let isLoading: Bool
    private let selectedBundleIdentifiers: [String]
    private let searchPlaceholderKey: String
    private let loadingKey: String
    private let emptyResultsKey: String
    private let addButtonKey: String
    private let maxVisibleResults: Int
    private let onAdd: (String) -> Void

    @State private var searchText = ""

    public init(
        appCatalog: [InstalledApplicationRecord],
        isLoading: Bool,
        selectedBundleIdentifiers: [String],
        searchPlaceholderKey: String = "settings.styles.editor.app_search",
        loadingKey: String = "settings.styles.editor.loading_apps",
        emptyResultsKey: String = "settings.styles.editor.app_results_empty",
        addButtonKey: String = "settings.styles.editor.add_app_target",
        maxVisibleResults: Int = 8,
        onAdd: @escaping (String) -> Void
    ) {
        self.appCatalog = appCatalog
        self.isLoading = isLoading
        self.selectedBundleIdentifiers = selectedBundleIdentifiers
        self.searchPlaceholderKey = searchPlaceholderKey
        self.loadingKey = loadingKey
        self.emptyResultsKey = emptyResultsKey
        self.addButtonKey = addButtonKey
        self.maxVisibleResults = maxVisibleResults
        self.onAdd = onAdd
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                        ForEach(filteredCatalog.prefix(maxVisibleResults)) { app in
                            appRow(app)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private var filteredCatalog: [InstalledApplicationRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        let selectedKeys = Set(
            selectedBundleIdentifiers.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
                onAdd(app.bundleIdentifier)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(AppDesignSystem.Colors.subtleFill2)
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
    }
}
