@testable import MeetingAssistantCore
import XCTest

final class DictionaryArchiveTests: XCTestCase {

    // MARK: - Round-trip

    func testArchiveRoundTrip() throws {
        let terms = [
            VocabularyTerm(term: "SwiftUI", definition: "UI framework"),
            VocabularyTerm(term: "Metal", definition: "GPU framework"),
        ]
        let rules = [
            VocabularyReplacementRule(find: "macos", replace: "macOS"),
        ]

        let archive = DictionaryArchive(
            vocabularyTerms: terms,
            substitutionRules: rules,
        )

        let data = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(DictionaryArchive.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, DictionaryArchive.currentSchemaVersion)
        XCTAssertEqual(decoded.sourceApp, "Verbi")
        XCTAssertEqual(decoded.vocabularyTerms.count, 2)
        XCTAssertEqual(decoded.substitutionRules.count, 1)
        XCTAssertEqual(decoded.vocabularyTerms[0].term, "SwiftUI")
        XCTAssertEqual(decoded.substitutionRules[0].find, "macos")
    }

    func testLegacySourceAppRemainsDecodable() throws {
        let legacyArchive = DictionaryArchive(
            sourceApp: "Prisma",
            vocabularyTerms: [],
            substitutionRules: [],
        )
        let data = try JSONEncoder().encode(legacyArchive)

        let result = DictionaryArchive.validate(data: data)

        guard case let .success(decoded) = result else {
            return XCTFail("Legacy Prisma archive should remain decodable")
        }
        XCTAssertEqual(decoded.sourceApp, "Prisma")
    }

    // MARK: - Empty collections

    func testArchiveWithEmptyCollections() throws {
        let archive = DictionaryArchive(
            vocabularyTerms: [],
            substitutionRules: [],
        )

        let data = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(DictionaryArchive.self, from: data)

        XCTAssertTrue(decoded.vocabularyTerms.isEmpty)
        XCTAssertTrue(decoded.substitutionRules.isEmpty)
    }

    // MARK: - Validation

    func testValidateValidArchive() throws {
        let archive = DictionaryArchive(
            vocabularyTerms: [VocabularyTerm(term: "test", definition: "")],
            substitutionRules: [],
        )

        let data = try JSONEncoder().encode(archive)
        let result = DictionaryArchive.validate(data: data)

        switch result {
        case .success:
            break
        case let .failure(error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    func testValidateUnsupportedSchemaVersion() throws {
        let archive = DictionaryArchive(
            schemaVersion: "dictionary_v0",
            vocabularyTerms: [],
            substitutionRules: [],
        )

        let data = try JSONEncoder().encode(archive)
        let result = DictionaryArchive.validate(data: data)

        switch result {
        case .success:
            XCTFail("Expected failure for unsupported schema version")
        case let .failure(error):
            guard case DictionaryArchiveError.unsupportedSchemaVersion = error else {
                XCTFail("Expected unsupportedSchemaVersion error, got: \(error)")
                return
            }
        }
    }

    func testValidateCorruptData() {
        let corruptData = Data("not-json-at-all".utf8)
        let result = DictionaryArchive.validate(data: corruptData)

        switch result {
        case .success:
            XCTFail("Expected failure for corrupt data")
        case .failure:
            break
        }
    }

    // MARK: - Merge outcomes

    func testMergeWithEmptyExistingAppliesCollections() {
        let terms = [VocabularyTerm(term: "Swift", definition: "Language")]
        let rules = [VocabularyReplacementRule(find: "app le", replace: "Apple")]

        let archive = DictionaryArchive(
            vocabularyTerms: terms,
            substitutionRules: rules,
        )

        let outcome = archive.merge(into: [], existingRules: [])

        XCTAssertEqual(outcome.result.termsImported, 1)
        XCTAssertEqual(outcome.result.rulesImported, 1)
        XCTAssertEqual(outcome.result.duplicateTermCount, 0)
        XCTAssertEqual(outcome.result.duplicateRuleCount, 0)
        XCTAssertEqual(outcome.terms.map(\.term), ["Swift"])
        XCTAssertEqual(outcome.rules.map(\.find), ["app le"])
    }

    func testMergeSkipsDuplicateTermsAndPreservesExisting() {
        let existingTerms = [VocabularyTerm(term: "Swift", definition: "Existing")]
        let existingRules = [VocabularyReplacementRule(find: "macos", replace: "macOS")]

        let archive = DictionaryArchive(
            vocabularyTerms: [VocabularyTerm(term: "Swift", definition: "Duplicate")],
            substitutionRules: [VocabularyReplacementRule(find: "macos", replace: "macOS")],
        )

        let outcome = archive.merge(
            into: existingTerms,
            existingRules: existingRules,
        )

        XCTAssertEqual(outcome.result.termsImported, 0)
        XCTAssertEqual(outcome.result.rulesImported, 0)
        XCTAssertEqual(outcome.result.duplicateTermCount, 1)
        XCTAssertEqual(outcome.result.duplicateRuleCount, 1)
        XCTAssertEqual(outcome.terms.map(\.term), ["Swift"])
        XCTAssertEqual(outcome.terms.first?.definition, "Existing")
        XCTAssertEqual(outcome.rules.count, 1)
    }

    func testMergeWithPartialDuplicatesReturnsMergedArrays() {
        let existingTerms = [VocabularyTerm(term: "Swift", definition: "")]
        let existingRules: [VocabularyReplacementRule] = []

        let archive = DictionaryArchive(
            vocabularyTerms: [
                VocabularyTerm(term: "Swift", definition: "Duplicate"),
                VocabularyTerm(term: "Kotlin", definition: "New"),
            ],
            substitutionRules: [
                VocabularyReplacementRule(find: "kotlin", replace: "Kotlin"),
            ],
        )

        let outcome = archive.merge(
            into: existingTerms,
            existingRules: existingRules,
        )

        XCTAssertEqual(outcome.result.termsImported, 1)
        XCTAssertEqual(outcome.result.duplicateTermCount, 1)
        XCTAssertEqual(outcome.result.rulesImported, 1)
        XCTAssertEqual(outcome.result.duplicateRuleCount, 0)
        XCTAssertEqual(Set(outcome.terms.map(\.term)), Set(["Swift", "Kotlin"]))
        XCTAssertEqual(outcome.rules.map(\.find), ["kotlin"])
    }

    func testMergeDeduplicatesWithinArchive() {
        let archive = DictionaryArchive(
            vocabularyTerms: [
                VocabularyTerm(term: "Swift", definition: "first"),
                VocabularyTerm(term: "swift", definition: "second"),
                VocabularyTerm(term: "  ", definition: "empty"),
            ],
            substitutionRules: [
                VocabularyReplacementRule(find: "macos", replace: "macOS"),
                VocabularyReplacementRule(find: "MacOS", replace: "macOS"),
            ],
        )

        let outcome = archive.merge(into: [], existingRules: [])

        // Term duplicates are collapsed by VocabularyTerm.normalized before merge counting.
        XCTAssertEqual(outcome.terms.map(\.term), ["Swift"])
        XCTAssertEqual(outcome.terms.first?.definition, "first")
        XCTAssertEqual(outcome.result.termsImported, 1)
        XCTAssertEqual(outcome.result.duplicateTermCount, 0)
        XCTAssertEqual(outcome.rules.count, 1)
        XCTAssertEqual(outcome.result.rulesImported, 1)
        XCTAssertEqual(outcome.result.duplicateRuleCount, 1)
    }

    func testMergeCountsIncomingDuplicatesAgainstExisting() {
        let existing = [VocabularyTerm(term: "Swift", definition: "kept")]
        let archive = DictionaryArchive(
            vocabularyTerms: [
                VocabularyTerm(term: "swift", definition: "dup"),
                VocabularyTerm(term: "Kotlin", definition: ""),
            ],
            substitutionRules: [],
        )

        let outcome = archive.merge(into: existing, existingRules: [])

        XCTAssertEqual(Set(outcome.terms.map(\.term)), Set(["Swift", "Kotlin"]))
        XCTAssertEqual(outcome.terms.first(where: { $0.term == "Swift" })?.definition, "kept")
        XCTAssertEqual(outcome.result.termsImported, 1)
        XCTAssertEqual(outcome.result.duplicateTermCount, 1)
    }

    func testMergeAllDuplicates() {
        let existingTerms = [VocabularyTerm(term: "Apple", definition: "")]
        let existingRules = [VocabularyReplacementRule(find: "app le, aple", replace: "Apple")]

        let archive = DictionaryArchive(
            vocabularyTerms: [VocabularyTerm(term: "Apple", definition: "Fruit")],
            substitutionRules: [VocabularyReplacementRule(find: "aple", replace: "Apple")],
        )

        let outcome = archive.merge(
            into: existingTerms,
            existingRules: existingRules,
        )

        XCTAssertEqual(outcome.result.termsImported, 0)
        XCTAssertEqual(outcome.result.rulesImported, 0)
        XCTAssertEqual(outcome.result.duplicateTermCount, 1)
        XCTAssertEqual(outcome.result.duplicateRuleCount, 1)
        XCTAssertEqual(outcome.terms, VocabularyTerm.normalized(existingTerms))
        XCTAssertEqual(outcome.rules.count, 1)
    }

    func testCurrentTimestampISO8601() {
        let timestamp = DictionaryArchive.currentTimestamp()
        let formatter = ISO8601DateFormatter()
        XCTAssertNotNil(formatter.date(from: timestamp), "Timestamp must be valid ISO 8601")
    }
}
