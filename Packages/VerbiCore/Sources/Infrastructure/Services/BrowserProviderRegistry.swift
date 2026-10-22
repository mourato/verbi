import AppKit
import Foundation

public enum BrowserProviderRegistry {
    public static func defaultProviders() -> [String: BrowserActiveTabURLProviding] {
        let providers: [String: BrowserActiveTabURLProviding?] = [
            "com.apple.Safari": provider(
                applicationName: "Safari",
                templates: [BrowserScriptTemplates.safariFrontDocument, BrowserScriptTemplates.safariCurrentTab]
            ),
            "com.google.Chrome": BrowserActiveTabURLProvider(
                applicationName: "Google Chrome",
                scriptTemplate: BrowserScriptTemplates.chromium
            ),
            "company.thebrowser.Browser": BrowserActiveTabURLProvider(
                applicationName: "Arc",
                scriptTemplate: BrowserScriptTemplates.chromium
            ),
            "com.brave.Browser": BrowserActiveTabURLProvider(
                applicationName: "Brave Browser",
                scriptTemplate: BrowserScriptTemplates.chromium
            ),
            "com.vivaldi.Vivaldi": BrowserActiveTabURLProvider(
                applicationName: "Vivaldi",
                scriptTemplate: BrowserScriptTemplates.chromium
            ),
            "com.operasoftware.Opera": BrowserActiveTabURLProvider(
                applicationName: "Opera",
                scriptTemplate: BrowserScriptTemplates.chromium
            ),
            "com.operasoftware.OperaNext": BrowserActiveTabURLProvider(
                applicationName: "Opera",
                scriptTemplate: BrowserScriptTemplates.chromium
            ),
            "com.microsoft.edgemac": BrowserActiveTabURLProvider(
                applicationName: "Microsoft Edge",
                scriptTemplate: BrowserScriptTemplates.chromium
            )
        ]

        var resolved: [String: BrowserActiveTabURLProviding] = [:]
        for (bundleId, provider) in providers {
            if let provider {
                resolved[normalizeBundleIdentifier(bundleId)] = provider
            }
        }
        return resolved
    }

    public static func provider(for bundleIdentifier: String) -> BrowserActiveTabURLProviding? {
        let normalizedBundleIdentifier = normalizeBundleIdentifier(bundleIdentifier)
        guard !normalizedBundleIdentifier.isEmpty else { return nil }

        if isFirefoxBundleIdentifier(normalizedBundleIdentifier) {
            return nil
        }

        if let knownProvider = defaultProviders()[normalizedBundleIdentifier] {
            return knownProvider
        }

        guard isLikelyBrowserBundleIdentifier(normalizedBundleIdentifier) else {
            return nil
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: normalizedBundleIdentifier) else {
            return nil
        }

        let applicationName = appURL.deletingPathExtension().lastPathComponent
        return provider(
            applicationName: applicationName,
            templates: [
                BrowserScriptTemplates.chromium,
                BrowserScriptTemplates.safariFrontDocument,
                BrowserScriptTemplates.safariCurrentTab
            ]
        )
    }

    public static func isLikelyBrowserBundleIdentifier(_ bundleIdentifier: String) -> Bool {
        let normalizedBundleIdentifier = normalizeBundleIdentifier(bundleIdentifier)
        guard !normalizedBundleIdentifier.isEmpty else { return false }

        if defaultProviders()[normalizedBundleIdentifier] != nil {
            return true
        }

        if isFirefoxBundleIdentifier(normalizedBundleIdentifier) {
            return true
        }

        return [
            "chromium",
            "chrome",
            "brave",
            "vivaldi",
            "opera",
            "edge",
            "arc",
            "browser"
        ].contains { normalizedBundleIdentifier.contains($0) }
    }

    private static func normalizeBundleIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isFirefoxBundleIdentifier(_ normalizedBundleIdentifier: String) -> Bool {
        normalizedBundleIdentifier.hasPrefix("org.mozilla.")
            || normalizedBundleIdentifier.contains("firefox")
    }

    private static func provider(
        applicationName: String,
        templates: [String]
    ) -> BrowserActiveTabURLProviding? {
        let providers = templates.compactMap {
            BrowserActiveTabURLProvider(applicationName: applicationName, scriptTemplate: $0)
        }

        guard !providers.isEmpty else { return nil }
        if providers.count == 1 {
            return providers[0]
        }

        return FallbackBrowserActiveTabURLProvider(providers: providers)
    }
}
