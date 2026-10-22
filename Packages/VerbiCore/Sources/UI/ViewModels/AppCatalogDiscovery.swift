import AppKit
import Foundation

enum AppCatalogDiscovery {
    private static let applicationSearchDirectories: [URL] = {
        let fileManager = FileManager.default
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
    }()

    static func discoverInstalledApplications() -> [InstalledApplicationRecord] {
        let fileManager = FileManager.default
        var seenBundleIdentifiers = Set<String>()
        var discovered: [InstalledApplicationRecord] = []

        for rootDirectory in applicationSearchDirectories {
            guard let enumerator = fileManager.enumerator(
                at: rootDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            while let item = enumerator.nextObject() as? URL {
                guard item.pathExtension.lowercased() == "app" else { continue }
                guard let bundle = Bundle(url: item),
                      let bundleIdentifier = bundle.bundleIdentifier
                else {
                    continue
                }

                let normalizedBundleIdentifier = bundleIdentifier
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()

                guard !normalizedBundleIdentifier.isEmpty else { continue }
                guard seenBundleIdentifiers.insert(normalizedBundleIdentifier).inserted else { continue }

                discovered.append(
                    InstalledApplicationRecord(
                        bundleIdentifier: bundleIdentifier,
                        displayName: Self.appDisplayName(from: bundle, fallbackURL: item)
                    )
                )
            }
        }

        return discovered.sorted { lhs, rhs in
            lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private static func appDisplayName(from bundle: Bundle, fallbackURL: URL) -> String {
        if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return fallbackURL.deletingPathExtension().lastPathComponent
    }
}
