import Foundation

private class BundleFinder {}

public extension Bundle {
    static var safeModule: Bundle {
        #if SWIFT_PACKAGE
            return applyLanguageOverride(to: Bundle.module)
        #endif

        let bundleName = "VerbiCore_VerbiCoreCommon"

        let candidates = [
            Bundle(for: BundleFinder.self).resourceURL,
            Bundle.main.resourceURL,
            Bundle(for: BundleFinder.self).bundleURL,
            Bundle.main.bundleURL
        ]

        for candidate in candidates {
            let bundlePath = candidate?.appendingPathComponent(bundleName + ".bundle")
            if let bundle = bundlePath.flatMap(Bundle.init(url:)) {
                return applyLanguageOverride(to: bundle)
            }
        }

        let codeBundle = Bundle(for: BundleFinder.self)

        if codeBundle.bundleIdentifier?.contains("VerbiCoreTests") == true {
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

public extension String {
    var localized: String {
        NSLocalizedString(self, bundle: .safeModule, comment: "")
    }

    func localized(with arguments: CVarArg...) -> String {
        String(format: localized, locale: .current, arguments: arguments)
    }
}
