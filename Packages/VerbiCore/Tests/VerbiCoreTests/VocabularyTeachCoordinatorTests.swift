import Foundation
import Testing
@testable import VerbiCore
@testable import VerbiCoreDomain
import XCTest

@MainActor
private final class MockDictionaryStore: DictionaryPersistenceStore {
    var vocabularyTerms: [VocabularyTerm]
    var vocabularyReplacementRules: [VocabularyReplacementRule]
    var shouldFailPersist = false
    private(set) var persistCallCount = 0

    init(
        terms: [VocabularyTerm] = [],
        rules: [VocabularyReplacementRule] = []
    ) {
        vocabularyTerms = terms
        vocabularyReplacementRules = rules
    }

    func persistDictionary(
        terms: [VocabularyTerm],
        rules: [VocabularyReplacementRule]
    ) throws {
        persistCallCount += 1
        if shouldFailPersist {
            throw DictionaryPersistenceError.saveVerificationFailed
        }
        vocabularyTerms = terms
        vocabularyReplacementRules = rules
    }
}

@MainActor
final class VocabularyTeachCoordinatorTests: XCTestCase {
    private let coordinator = VocabularyTeachCoordinator()

    func testPrepareAndConfirmPersistSubstitutionAndVocabularyTerm() throws {
        let store = MockDictionaryStore()

        let plan = try coordinator.prepare(
            origins: ["verby"],
            destination: "Verbi",
            alsoAddVocabularyTerm: true,
            store: store
        )
        XCTAssertTrue(plan.addedVocabularyTerm)

        let added = try coordinator.confirm(plan, into: store)

        XCTAssertTrue(added)
        XCTAssertEqual(store.persistCallCount, 1)
        XCTAssertEqual(store.vocabularyReplacementRules.map(\.find), ["verby"])
        XCTAssertEqual(store.vocabularyReplacementRules.map(\.replace), ["Verbi"])
        XCTAssertEqual(store.vocabularyTerms.map(\.term), ["Verbi"])
    }

    func testWithoutVocabularyChoiceLeavesTermsUntouched() throws {
        let existingTerm = VocabularyTerm(term: "SwiftUI", definition: "UI framework")
        let store = MockDictionaryStore(terms: [existingTerm])

        let plan = try coordinator.prepare(
            origins: ["verby"],
            destination: "Verbi",
            alsoAddVocabularyTerm: false,
            store: store
        )
        _ = try coordinator.confirm(plan, into: store)

        XCTAssertFalse(plan.addedVocabularyTerm)
        XCTAssertEqual(store.vocabularyTerms, [existingTerm])
    }

    func testDuplicateOriginIsConsolidatedIntoOneEntry() throws {
        let store = MockDictionaryStore(
            rules: [VocabularyReplacementRule(find: "verby", replace: "Verbi")]
        )

        let plan = try coordinator.prepare(
            origins: ["verby", "VERBY"],
            destination: "Verbi",
            alsoAddVocabularyTerm: false,
            store: store
        )
        _ = try coordinator.confirm(plan, into: store)

        XCTAssertEqual(store.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(store.vocabularyReplacementRules.first?.normalizedFindVariants, ["verby"])
    }

    func testPersistenceFailureThrowsAndPreservesStore() throws {
        let originalTerm = VocabularyTerm(term: "SwiftUI", definition: "Keep me")
        let originalRule = VocabularyReplacementRule(find: "swift you eye", replace: "SwiftUI")
        let store = MockDictionaryStore(terms: [originalTerm], rules: [originalRule])
        store.shouldFailPersist = true

        let plan = try coordinator.prepare(
            origins: ["verby"],
            destination: "Verbi",
            alsoAddVocabularyTerm: true,
            store: store
        )

        XCTAssertThrowsError(try coordinator.confirm(plan, into: store)) { error in
            guard let teachError = error as? VocabularyTeachError,
                  case .persistenceFailed = teachError
            else {
                return XCTFail("Expected persistenceFailed, got \(error)")
            }
        }

        XCTAssertEqual(store.persistCallCount, 1)
        XCTAssertEqual(store.vocabularyTerms, [originalTerm])
        XCTAssertEqual(store.vocabularyReplacementRules, [originalRule])
    }

    func testStaleDictionaryIsRejectedWithoutWriting() throws {
        let store = MockDictionaryStore()
        let plan = try coordinator.prepare(
            origins: ["verby"],
            destination: "Verbi",
            alsoAddVocabularyTerm: false,
            store: store
        )

        store.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "other", replace: "Other")
        ]

        XCTAssertThrowsError(try coordinator.confirm(plan, into: store)) { error in
            XCTAssertEqual(error as? VocabularyTeachError, .staleDictionary)
        }
        XCTAssertEqual(store.persistCallCount, 0)
    }

    func testMovingConflictRelocatesOriginInOneWrite() throws {
        let store = MockDictionaryStore(
            rules: [VocabularyReplacementRule(find: "verby, other", replace: "Verby")]
        )

        let plan = try coordinator.prepare(
            origins: ["verby"],
            destination: "Verbi",
            alsoAddVocabularyTerm: false,
            movingOriginKeys: [VocabularyNormalization.originKey("verby")],
            store: store
        )
        _ = try coordinator.confirm(plan, into: store)

        XCTAssertEqual(store.persistCallCount, 1)
        XCTAssertEqual(store.vocabularyReplacementRules.map(\.replace), ["Verby", "Verbi"])
        XCTAssertEqual(store.vocabularyReplacementRules.first?.normalizedFindVariants, ["other"])
        XCTAssertEqual(store.vocabularyReplacementRules.last?.normalizedFindVariants, ["verby"])
    }
}
