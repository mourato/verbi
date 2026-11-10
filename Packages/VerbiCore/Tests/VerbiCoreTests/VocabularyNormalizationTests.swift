@testable import VerbiCore
import XCTest

final class VocabularyNormalizationTests: XCTestCase {
    func testSpellingTrimsOuterWhitespaceOnly() {
        XCTAssertEqual(VocabularyNormalization.spelling("  ray cast \n"), "ray cast")
        XCTAssertEqual(VocabularyNormalization.spelling("ra  y"), "ra  y")
        XCTAssertEqual(VocabularyNormalization.spelling("US"), "US")
    }

    func testSpellingComposesCanonicallyEquivalentUnicode() {
        let decomposed = "Cafe\u{301}"
        let composed = "Café"

        XCTAssertNotEqual(
            decomposed.unicodeScalars.count,
            composed.unicodeScalars.count,
            "The fixture must actually use a decomposed spelling"
        )
        XCTAssertEqual(VocabularyNormalization.spelling(decomposed), composed)
        XCTAssertEqual(
            VocabularyNormalization.spelling(decomposed).unicodeScalars.count,
            composed.unicodeScalars.count
        )
    }

    func testDestinationKeyKeepsSignificantCase() {
        XCTAssertEqual(VocabularyNormalization.destinationKey(" US "), "US")
        XCTAssertNotEqual(
            VocabularyNormalization.destinationKey("US"),
            VocabularyNormalization.destinationKey("us")
        )
    }

    func testOriginAndTermKeysIgnoreCase() {
        XCTAssertEqual(VocabularyNormalization.originKey(" ReyCast "), "reycast")
        XCTAssertEqual(VocabularyNormalization.termKey("SwiftUI"), "swiftui")
        XCTAssertEqual(
            VocabularyNormalization.originKey("Cafe\u{301}"),
            VocabularyNormalization.originKey("café")
        )
    }
}
