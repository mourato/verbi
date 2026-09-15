import MeetingAssistantCoreInfrastructure
import SwiftUI

struct DictationStyleTriggerSection: View {
    @Binding var targets: [DictationStyleTarget]
    let appCatalog: [InstalledApplicationRecord]
    let isLoadingAppCatalog: Bool
    let styleID: UUID?
    let onEnsureAppCatalogLoaded: () -> Void
    let onFindConflictingStyleName: (DictationStyleTarget, UUID?) -> String?
    @State private var isPickerPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("settings.styles.editor.targets_hint".localized).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("settings.styles.add".localized, systemImage: "plus") {
                    onEnsureAppCatalogLoaded()
                    isPickerPresented = true
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $isPickerPresented) {
                    DictationStyleTriggerPickerPopover(
                        targets: $targets,
                        appCatalog: appCatalog,
                        isLoadingAppCatalog: isLoadingAppCatalog,
                        styleID: styleID,
                        onFindConflictingStyleName: onFindConflictingStyleName
                    )
                }
            }
            if targets.isEmpty {
                Text("settings.styles.editor.no_targets".localized).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                    HStack(spacing: 8) {
                        targetIcon(target)
                        Text(displayName(target)).lineLimit(1)
                        Spacer()
                        Button("settings.styles.editor.remove_target_format".localized(with: displayName(target)), systemImage: "minus.circle") {
                            targets.remove(at: index)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    @ViewBuilder private func targetIcon(_ target: DictationStyleTarget) -> some View {
        switch target {
        case let .app(bundleIdentifier): AppIconView(bundleIdentifier: bundleIdentifier, fallbackSystemName: "app.fill", size: 22, cornerRadius: 5)
        case .website: Image(systemName: "globe").foregroundStyle(.tint)
        }
    }

    private func displayName(_ target: DictationStyleTarget) -> String {
        switch target {
        case let .app(bundleIdentifier):
            appCatalog.first(where: { $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame })?.displayName ?? bundleIdentifier
        case let .website(value): value
        }
    }
}

#Preview { DictationStyleTriggerSection(targets: .constant([]), appCatalog: [], isLoadingAppCatalog: false, styleID: nil, onEnsureAppCatalogLoaded: {}, onFindConflictingStyleName: { _, _ in nil }) }
