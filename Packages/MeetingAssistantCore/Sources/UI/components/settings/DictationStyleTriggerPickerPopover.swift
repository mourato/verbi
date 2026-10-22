import MeetingAssistantCoreInfrastructure
import SwiftUI

struct DictationStyleTriggerPickerPopover: View {
    @Binding var targets: [DictationTrigger]
    let appCatalog: [InstalledApplicationRecord]
    let isLoadingAppCatalog: Bool
    let styleID: UUID?
    let onFindConflictingStyleName: (DictationTrigger, UUID?) -> String?
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TextField("settings.styles.editor.app_search".localized, text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(12)
                .focused($searchFocused)
            Divider()
            if isLoadingAppCatalog {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if let website = websiteCandidate {
                            targetButton(.website(url: website), title: website, icon: "globe")
                        }
                        ForEach(filteredApps) { app in
                            targetButton(.app(bundleIdentifier: app.bundleIdentifier), title: app.displayName, subtitle: app.bundleIdentifier, app: app)
                        }
                        if filteredApps.isEmpty, websiteCandidate == nil {
                            Text("settings.styles.editor.app_search_no_match".localized).font(.caption).foregroundStyle(.secondary).padding()
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(width: 340, height: 440)
        .onAppear { searchFocused = true }
    }

    private var filteredApps: [InstalledApplicationRecord] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return appCatalog.sorted { lhs, rhs in
            rank(lhs, query: value) == rank(rhs, query: value)
                ? lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
                : rank(lhs, query: value) < rank(rhs, query: value)
        }.filter { value.isEmpty || rank($0, query: value) < 5 }
    }

    private var websiteCandidate: String? {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.contains("."), !value.contains(where: \.isWhitespace) else { return nil }
        return value
    }

    private func rank(_ app: InstalledApplicationRecord, query: String) -> Int {
        guard !query.isEmpty else { return 3 }
        if app.displayName.caseInsensitiveCompare(query) == .orderedSame {
            return 0
        }
        if app.displayName.lowercased().hasPrefix(query.lowercased()) {
            return 1
        }
        if app.displayName.localizedCaseInsensitiveContains(query) {
            return 2
        }
        if app.bundleIdentifier.lowercased().hasPrefix(query.lowercased()) {
            return 3
        }
        if app.bundleIdentifier.localizedCaseInsensitiveContains(query) {
            return 4
        }
        return 5
    }

    @ViewBuilder private func targetButton(_ target: DictationTrigger, title: String, subtitle: String? = nil, app: InstalledApplicationRecord? = nil, icon: String? = nil) -> some View {
        let selected = targets.contains(where: { $0.normalizedIdentity == target.normalizedIdentity })
        let conflict = onFindConflictingStyleName(target, styleID)
        Button { toggle(target, conflict: conflict) } label: {
            HStack(spacing: 8) {
                if let app {
                    AppIconView(bundleIdentifier: app.bundleIdentifier, fallbackSystemName: "app.fill", size: 22, cornerRadius: 5)
                } else if let icon {
                    Image(systemName: icon).frame(width: 22)
                }
                VStack(alignment: .leading) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                    }
                    if let conflict {
                        Text(conflict).font(.caption2).foregroundStyle(.red)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle")
            }
            .padding(8)
        }
        .buttonStyle(.plain)
        .disabled(conflict != nil && !selected)
        .accessibilityValue(selected ? "common.selected".localized : "")
    }

    private func toggle(_ target: DictationTrigger, conflict: String?) {
        if let index = targets.firstIndex(where: { $0.normalizedIdentity == target.normalizedIdentity }) {
            targets.remove(at: index)
        } else if conflict == nil {
            targets.append(target)
        }
    }
}

#Preview { DictationStyleTriggerPickerPopover(targets: .constant([]), appCatalog: [InstalledApplicationRecord(bundleIdentifier: "com.apple.Safari", displayName: "Safari")], isLoadingAppCatalog: false, styleID: nil, onFindConflictingStyleName: { _, _ in nil }) }
