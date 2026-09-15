import Foundation

private class BundleFinder {}

public extension Bundle {
    /// Returns a bundle that works safely across SPM, Xcode IDE, and Test environments.
    ///
    /// Notes:
    /// - Prefer using `.safeModule` for all localized UI strings in this project.
    /// - Direct `Bundle.module` usage can be brittle across build/test environments when the
    ///   resource bundle name/location differs (e.g. `xcodebuild` vs `swift test`).
    static var safeModule: Bundle {
        #if SWIFT_PACKAGE
            // Detect if running via `swift test` (CLI) vs `xcodebuild` (Xcode)
            // Xcode usually sets specific environment variables.
            let isXcode = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            if !isXcode {
                return applyLanguageOverride(to: Bundle.module)
            }
        #endif

        let bundleName = "MeetingAssistantCore_MeetingAssistantCore"

        // 1. Candidates for finding the resource bundle
        let candidates = [
            // Bundle should be in the same folder as the code (SPM/Xcode)
            Bundle(for: BundleFinder.self).resourceURL,
            // Bundle should be in the main bundle (App target)
            Bundle.main.resourceURL,
            // Path-based lookup for standard locations
            Bundle(for: BundleFinder.self).bundleURL,
            Bundle.main.bundleURL
        ]

        // 2. Try to find the specific resource bundle (.bundle)
        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return applyLanguageOverride(to: bundle)
            }
        }

        // 3. Fallback: Use the bundle containing the code
        let codeBundle = Bundle(for: BundleFinder.self)

        // Ensure we don't return the test bundle as a resource bundle
        if codeBundle.bundleIdentifier?.contains("MeetingAssistantCoreTests") == true {
            return applyLanguageOverride(to: Bundle.main)
        }

        return applyLanguageOverride(to: codeBundle)
    }

    private static func applyLanguageOverride(to bundle: Bundle) -> Bundle {
        if let languages = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
           let preferredLang = languages.first
        {
            let candidates = [preferredLang, preferredLang.components(separatedBy: "-").first]
                .compactMap(\.self)

            for language in candidates {
                if let path = bundle.path(forResource: language, ofType: "lproj"),
                   let localizedBundle = Bundle(path: path)
                {
                    return localizedBundle
                }
            }
        }
        return bundle
    }
}

// MARK: - String Localization Helper

public extension String {
    /// Localized string using the safe module bundle.
    /// Usage: `"settings.general.language".localized`
    var localized: String {
        NSLocalizedString(self, bundle: .safeModule, comment: "")
    }

    /// Localized string with format arguments.
    /// Usage: `"permissions.granted_count".localized(with: count)`
    func localized(with arguments: CVarArg...) -> String {
        String(format: localized, locale: .current, arguments: arguments)
    }
}
