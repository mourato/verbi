@testable import VerbiCore
import XCTest

@MainActor
final class AppSettingsVocabularyTermsTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testDefaultTermsEmpty() {
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
    }

    func testSaveAndLoadTerms() {
        let terms = [
            VocabularyTerm(term: "OpenAI", definition: "Artificial intelligence research company"),
            VocabularyTerm(term: "SwiftUI", definition: "Apple's declarative UI framework"),
        ]

        settings.vocabularyTerms = terms
        XCTAssertEqual(settings.vocabularyTerms.count, 2)
        XCTAssertEqual(settings.vocabularyTerms.map(\.term), ["OpenAI", "SwiftUI"])
        XCTAssertEqual(settings.vocabularyTerms[0].definition, "Artificial intelligence research company")
    }

    func testReplaceTerms() {
        settings.vocabularyTerms = [
            VocabularyTerm(term: "old term", definition: ""),
        ]

        settings.vocabularyTerms = [
            VocabularyTerm(term: "new term", definition: "replacement"),
        ]

        XCTAssertEqual(settings.vocabularyTerms.count, 1)
        XCTAssertEqual(settings.vocabularyTerms[0].term, "new term")
    }

    func testClearTerms() {
        settings.vocabularyTerms = [
            VocabularyTerm(term: "temporary", definition: "will be removed"),
        ]

        settings.vocabularyTerms = []
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
    }

    func testEmptyDefinitionIsAllowed() {
        settings.vocabularyTerms = [
            VocabularyTerm(term: "acronym", definition: ""),
        ]

        XCTAssertEqual(settings.vocabularyTerms.count, 1)
        XCTAssertEqual(settings.vocabularyTerms[0].definition, "")
    }

    func testStoreNormalizesDuplicatesAndEmptyTerms() {
        settings.vocabularyTerms = [
            VocabularyTerm(term: "  test  ", definition: " first "),
            VocabularyTerm(term: "TEST", definition: "second"),
            VocabularyTerm(term: "   ", definition: "empty"),
            VocabularyTerm(term: "Other", definition: ""),
        ]

        XCTAssertEqual(settings.vocabularyTerms.map(\.term), ["Other", "test"])
        XCTAssertEqual(settings.vocabularyTerms.first(where: { $0.term == "test" })?.definition, "first")
    }

    func testTermsAreCodable() {
        let terms = [
            VocabularyTerm(term: "API", definition: "Application Programming Interface"),
            VocabularyTerm(term: "JSON", definition: "JavaScript Object Notation"),
        ]

        guard let data = try? JSONEncoder().encode(terms) else {
            XCTFail("Failed to encode terms")
            return
        }

        let decoded = try? JSONDecoder().decode([VocabularyTerm].self, from: data)
        XCTAssertEqual(decoded?.count, 2)
        XCTAssertEqual(decoded?.first?.term, "API")
    }

    func testTermSortOrder() {
        let terms = [
            VocabularyTerm(term: "Zebra", definition: ""),
            VocabularyTerm(term: "Alpha", definition: ""),
            VocabularyTerm(term: "Bravo", definition: ""),
        ]

        let sorted = VocabularyTerm.normalized(terms)
        XCTAssertEqual(sorted.map(\.term), ["Alpha", "Bravo", "Zebra"])
    }

    func testTermHashable() {
        let term1 = VocabularyTerm(id: UUID(), term: "test", definition: "def")
        let term2 = VocabularyTerm(id: term1.id, term: "test", definition: "def")

        XCTAssertEqual(term1, term2)
        XCTAssertEqual(term1.hashValue, term2.hashValue)
    }
}
