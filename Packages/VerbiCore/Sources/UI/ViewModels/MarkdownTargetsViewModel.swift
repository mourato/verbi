import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class InstalledAppsSelectionViewModel: ObservableObject {
    @Published public private(set) var installedApps: [InstalledAppItem] = []

    private let defaultBundleIdentifiers: [String]
    private let protectedBundleIdentifiers: [String]
    private let hasConfigured: () -> Bool
    private let loadBundleIdentifiers: () -> [String]
    private let saveBundleIdentifiers: ([String]) -> Void
    private let workspace: NSWorkspace
    private let openPanelProvider: @MainActor () -> NSOpenPanel

    public init(
        defaultBundleIdentifiers: [String],
        protectedBundleIdentifiers: [String] = [],
        hasConfigured: @escaping () -> Bool,
        loadBundleIdentifiers: @escaping () -> [String],
        saveBundleIdentifiers: @escaping ([String]) -> Void,
        workspace: NSWorkspace = .shared,
        openPanelProvider: @escaping @MainActor () -> NSOpenPanel = { NSOpenPanel() }
    ) {
        self.defaultBundleIdentifiers = defaultBundleIdentifiers
        self.protectedBundleIdentifiers = protectedBundleIdentifiers
        self.hasConfigured = hasConfigured
        self.loadBundleIdentifiers = loadBundleIdentifiers
        self.saveBundleIdentifiers = saveBundleIdentifiers
        self.workspace = workspace
        self.openPanelProvider = openPanelProvider
    }

    public func refreshTargets() {
        let candidates = resolveCandidateBundleIdentifiers()
        let resolved = resolveInstalledApps(from: candidates)
        let resolvedIdentifiers = resolved
            .filter(\.isRemovable)
            .map(\.bundleIdentifier)

        if hasConfigured(), resolvedIdentifiers != loadBundleIdentifiers() {
            saveBundleIdentifiers(resolvedIdentifiers)
        }

        installedApps = resolved
    }

    public func addApp() {
        let panel = openPanelProvider()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.applicationBundle]

        if panel.runModal() == .OK, let url = panel.url {
            addApp(from: url)
        }
    }

    public func addApp(bundleIdentifier: String) {
        let normalized = normalizeBundleIdentifier(bundleIdentifier)
        var identifiers = loadBundleIdentifiers()
        if !identifiers.contains(where: { normalizeBundleIdentifier($0) == normalized }) {
            identifiers.append(bundleIdentifier)
        }
        saveBundleIdentifiers(identifiers)
        refreshTargets()
    }

    public func removeApp(bundleIdentifier: String) {
        let normalized = normalizeBundleIdentifier(bundleIdentifier)
        var identifiers = loadBundleIdentifiers()
        identifiers.removeAll { normalizeBundleIdentifier($0) == normalized }
        saveBundleIdentifiers(identifiers)
        refreshTargets()
    }

    private func resolveCandidateBundleIdentifiers() -> [String] {
        let candidates = hasConfigured() ? loadBundleIdentifiers() : defaultBundleIdentifiers
        return protectedBundleIdentifiers + candidates
    }

    private func addApp(from url: URL) {
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier
        else {
            return
        }

        let normalized = normalizeBundleIdentifier(bundleIdentifier)
        var identifiers = loadBundleIdentifiers()
        if !identifiers.contains(where: { normalizeBundleIdentifier($0) == normalized }) {
            identifiers.append(bundleIdentifier)
        }
        saveBundleIdentifiers(identifiers)
        refreshTargets()
    }

    private func resolveInstalledApps(from bundleIdentifiers: [String]) -> [InstalledAppItem] {
        var seen = Set<String>()
        var resolved: [InstalledAppItem] = []

        for bundleIdentifier in bundleIdentifiers {
            let normalized = normalizeBundleIdentifier(bundleIdentifier)
            guard seen.insert(normalized).inserted else { continue }
            let trimmed = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let appURL = workspace.urlForApplication(withBundleIdentifier: trimmed) else { continue }

            let icon = workspace.icon(forFile: appURL.path)
            icon.size = NSSize(width: 20, height: 20)

            let displayName = bundleDisplayName(from: appURL)
            resolved.append(
                InstalledAppItem(
                    bundleIdentifier: bundleIdentifier,
                    displayName: displayName,
                    icon: icon,
                    isRemovable: !isProtectedBundleIdentifier(bundleIdentifier)
                )
            )
        }

        return resolved
    }

    private func bundleDisplayName(from url: URL) -> String {
        if let bundle = Bundle(url: url) {
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                return displayName
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                return name
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func normalizeBundleIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func isProtectedBundleIdentifier(_ value: String) -> Bool {
        let normalized = normalizeBundleIdentifier(value)
        return protectedBundleIdentifiers.contains { normalizeBundleIdentifier($0) == normalized }
    }
}

public struct InstalledAppItem: Identifiable {
    public let bundleIdentifier: String
    public let displayName: String
    public let icon: NSImage
    public let isRemovable: Bool

    public var id: String {
        bundleIdentifier
    }
}
