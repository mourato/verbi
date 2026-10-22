import AppKit
import Foundation

struct WebTargetBrowserOption: Identifiable {
    let name: String
    let bundleIdentifier: String

    var id: String {
        bundleIdentifier
    }
}

enum WebTargetEditorSupport {
    static let browserOptions: [WebTargetBrowserOption] = [
        WebTargetBrowserOption(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        WebTargetBrowserOption(name: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
        WebTargetBrowserOption(name: "Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac")
    ]

    static func browserDisplayName(for bundleIdentifier: String) -> String {
        if let knownName = browserOptions.first(where: { $0.bundleIdentifier == bundleIdentifier })?.name {
            return knownName
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier),
           let bundle = Bundle(url: appURL)
        {
            if let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
                return displayName
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
                return name
            }
            return appURL.deletingPathExtension().lastPathComponent
        }

        return bundleIdentifier
    }

    static func parseURLPatterns(from text: String) -> [String] {
        text
            .replacingOccurrences(of: ",", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
