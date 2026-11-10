import Foundation
import Testing
@testable import VerbiCore
@testable import VerbiCoreDomain
import XCTest

@MainActor
private final class MockDictionaryStore: DictionaryPersistenceStore {
    var vocabularyTerms: [VocabularyTerm]
    var vocabularyReplacementRules: [VocabularyReplacementRule]
    var shouldFailPersist: Bool = false
    var persistCallCount: Int = 0

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
final class DictionaryImportCoordinatorTests: XCTestCase {
    // MARK: - Successful Import Confirmation

    func testConfirmImportSucceedsAndPersistsToStore() throws {
        let store = MockDictionaryStore(
            terms: [VocabularyTerm(term: "ExistingTerm", definition: "Old")],
            rules: [VocabularyReplacementRule(find: "old", replace: "OldDestination")]
        )

        let incomingArchive = DictionaryArchive(
            vocabularyTerms: [
                VocabularyTerm(term: "NewTerm", definition: "New")
            ],
            substitutionRules: [
                VocabularyReplacementRule(find: "new_var", replace: "NewDestination")
            ]
        )
        let archiveData = try JSONEncoder().encode(incomingArchive)

        let coordinator = DictionaryImportCoordinator()
        let preview = try coordinator.prepareImportPreview(
            from: archiveData,
            store: store
        )

        XCTAssertTrue(preview.hasImportableChanges)
        let result = try coordinator.confirmImport(preview: preview, into: store)

        XCTAssertEqual(result.importedTermsCount, 1)
        XCTAssertEqual(result.importedVariantsCount, 1)
        XCTAssertEqual(result.duplicatesCount, 0)
        XCTAssertEqual(result.conflictsCount, 0)

        XCTAssertEqual(store.persistCallCount, 1)
        XCTAssertEqual(store.vocabularyTerms.map(\.term), ["ExistingTerm", "NewTerm"])
        XCTAssertEqual(store.vocabularyReplacementRules.map(\.replace), ["OldDestination", "NewDestination"])
    }

    // MARK: - M1: Persistence Failure Reports Error And Preserves Store

    func testConfirmImportWithPersistenceFailureAbortsAndPreservesStore() throws {
        let originalTerms = [VocabularyTerm(term: "Initial", definition: "KeepMe")]
        let originalRules = [VocabularyReplacementRule(find: "init", replace: "Initial")]
        let store = MockDictionaryStore(terms: originalTerms, rules: originalRules)
        store.shouldFailPersist = true

        let incomingArchive = DictionaryArchive(
            vocabularyTerms: [VocabularyTerm(term: "ShouldFail", definition: "")],
            substitutionRules: [VocabularyReplacementRule(find: "sf", replace: "ShouldFail")]
        )
        let preview = incomingArchive.createPreview(
            existingTerms: store.vocabularyTerms,
            existingRules: store.vocabularyReplacementRules
        )

        let coordinator = DictionaryImportCoordinator()

        XCTAssertThrowsError(
            try coordinator.confirmImport(preview: preview, into: store)
        ) { error in
            guard let importError = error as? DictionaryImportError else {
                return XCTFail("Expected DictionaryImportError, got \(error)")
            }
            if case let .persistenceFailed(reason) = importError {
                XCTAssertFalse(reason.isEmpty)
            } else {
                XCTFail("Expected persistenceFailed case, got \(importError)")
            }
        }

        XCTAssertEqual(store.persistCallCount, 1)
        // Store must remain completely unmodified
        XCTAssertEqual(store.vocabularyTerms, originalTerms)
        XCTAssertEqual(store.vocabularyReplacementRules, originalRules)
    }

    // MARK: - M2: Stale Store Refuses Without Writing

    func testConfirmImportWithStaleStoreRefusesWithoutWriting() throws {
        let initialTerms = [VocabularyTerm(term: "Initial", definition: "")]
        let initialRules = [VocabularyReplacementRule(find: "init", replace: "Initial")]
        let store = MockDictionaryStore(terms: initialTerms, rules: initialRules)

        let incomingArchive = DictionaryArchive(
            vocabularyTerms: [VocabularyTerm(term: "Incoming", definition: "")],
            substitutionRules: []
        )
        let preview = incomingArchive.createPreview(
            existingTerms: store.vocabularyTerms,
            existingRules: store.vocabularyReplacementRules
        )

        // Concurrent background modification occurs while preview is open:
        store.vocabularyTerms.append(VocabularyTerm(term: "ConcurrentTerm", definition: ""))

        let coordinator = DictionaryImportCoordinator()

        XCTAssertThrowsError(
            try coordinator.confirmImport(preview: preview, into: store)
        ) { error in
            guard let importError = error as? DictionaryImportError else {
                return XCTFail("Expected DictionaryImportError, got \(error)")
            }
            XCTAssertEqual(importError, .staleDictionary)
        }

        // Must refuse before touching persist
        XCTAssertEqual(store.persistCallCount, 0)
        // Store terms should only have initial + concurrent, NOT incoming
        XCTAssertFalse(store.vocabularyTerms.contains { $0.term == "Incoming" })
    }

    // MARK: - M2: Cancellation Leaves Store Completely Intact

    func testCancelImportLeavesStoreUntouched() throws {
        let originalTerms = [VocabularyTerm(term: "Keep1", definition: "")]
        let originalRules = [VocabularyReplacementRule(find: "k1", replace: "Keep1")]
        let store = MockDictionaryStore(terms: originalTerms, rules: originalRules)

        let incomingArchive = DictionaryArchive(
            vocabularyTerms: [VocabularyTerm(term: "Discarded", definition: "")],
            substitutionRules: [VocabularyReplacementRule(find: "d", replace: "Discarded")]
        )
        let preview = incomingArchive.createPreview(
            existingTerms: store.vocabularyTerms,
            existingRules: store.vocabularyReplacementRules
        )

        let coordinator = DictionaryImportCoordinator()
        coordinator.cancelImport(preview: preview)

        XCTAssertEqual(store.persistCallCount, 0)
        XCTAssertEqual(store.vocabularyTerms, originalTerms)
        XCTAssertEqual(store.vocabularyReplacementRules, originalRules)
    }

    // MARK: - M2: Invalid Archive Rejects Without Store Modification

    func testInvalidArchiveRejectsWithoutStoreModification() {
        let originalTerms = [VocabularyTerm(term: "Safe", definition: "")]
        let originalRules = [VocabularyReplacementRule(find: "s", replace: "Safe")]
        let store = MockDictionaryStore(terms: originalTerms, rules: originalRules)

        let corruptData = Data("<<CORRUPT NOT JSON>>".utf8)
        let coordinator = DictionaryImportCoordinator()

        XCTAssertThrowsError(
            try coordinator.prepareImportPreview(from: corruptData, store: store)
        ) { error in
            XCTAssertTrue(error is DictionaryArchiveError)
        }

        XCTAssertEqual(store.persistCallCount, 0)
        XCTAssertEqual(store.vocabularyTerms, originalTerms)
        XCTAssertEqual(store.vocabularyReplacementRules, originalRules)
    }
}
