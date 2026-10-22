import Foundation
import XCTest

final class LocalizationKeyIntegrityTests: XCTestCase {
    func testLocalizedResourceFilesContainSameKeys() throws {
        let enKeys = try localizationKeys(locale: "en")
        let ptKeys = try localizationKeys(locale: "pt")

        XCTAssertEqual(
            enKeys,
            ptKeys,
            """
            Localizable.strings files must stay symmetric.
            Missing from en: \(ptKeys.subtracting(enKeys).sorted())
            Missing from pt: \(enKeys.subtracting(ptKeys).sorted())
            """,
        )
    }

    func testLiteralLocalizedKeysAreRegisteredInSupportedLocales() throws {
        let supportedKeys = try localizationKeys(locale: "en")
        let usedKeys = try literalLocalizedKeys(in: [
            repositoryRoot.appendingPathComponent("App"),
            packageRoot.appendingPathComponent("Sources"),
        ])

        let missingKeys = usedKeys.subtracting(supportedKeys)
        XCTAssertTrue(
            missingKeys.isEmpty,
            "Register every literal .localized key in all locale files: \(missingKeys.sorted())",
        )
    }

    private var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var repositoryRoot: URL {
        packageRoot
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func localizationKeys(locale: String) throws -> Set<String> {
        let fileURL = packageRoot
            .appendingPathComponent("Sources/Common/Resources")
            .appendingPathComponent("\(locale).lproj/Localizable.strings")
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: #"^"([^"]+)""#, options: [.anchorsMatchLines])

        return Set(regex.matches(in: contents, range: NSRange(contents.startIndex..., in: contents)).compactMap { match in
            Range(match.range(at: 1), in: contents).map { String(contents[$0]) }
        })
    }

    private func literalLocalizedKeys(in roots: [URL]) throws -> Set<String> {
        let fileManager = FileManager.default
        let regex = try NSRegularExpression(pattern: #""([A-Za-z0-9_.-]+)"\.localized(?:\(|\b)"#)
        var keys = Set<String>()

        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles],
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }

                let contents = try String(contentsOf: fileURL, encoding: .utf8)
                for match in regex.matches(in: contents, range: NSRange(contents.startIndex..., in: contents)) {
                    if let range = Range(match.range(at: 1), in: contents) {
                        keys.insert(String(contents[range]))
                    }
                }
            }
        }

        return keys
    }
}
