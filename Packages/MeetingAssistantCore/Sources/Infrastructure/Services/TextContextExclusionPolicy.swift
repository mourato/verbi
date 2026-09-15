import Foundation

public struct TextContextExclusionPolicy: Sendable, Equatable {
    public let baseExcludedBundleIDs: [String]

    public init(baseExcludedBundleIDs: [String] = Self.defaultBundleIDs) {
        self.baseExcludedBundleIDs = baseExcludedBundleIDs
    }

    public static let defaultBundleIDs: [String] = [
        "com.apple.keychainaccess",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPass",
        "proton.pass.mac"
    ]

    public func isExcluded(bundleIdentifier: String, customExcludedBundleIDs: [String]) -> Bool {
        let normalizedBundleID = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let custom = customExcludedBundleIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let combined = Set(baseExcludedBundleIDs.map { $0.lowercased() } + custom)
        return combined.contains(normalizedBundleID)
    }

    public func mergedExcludedBundleIDs(customExcludedBundleIDs: [String]) -> [String] {
        let normalizedCustom = customExcludedBundleIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let combined = Set(baseExcludedBundleIDs.map { $0.lowercased() } + normalizedCustom)
        return combined.sorted()
    }
}
