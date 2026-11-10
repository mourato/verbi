import Foundation
import Testing
@testable import VerbiCore
@testable import VerbiCoreDomain
import XCTest

@MainActor
private final class FailingDictionaryStore: DictionaryPersistenceStore {
    var vocabularyTerms: [VocabularyTerm] = []
    var vocabularyReplacementRules: [VocabularyReplacementRule] = []
    private(set) var persistCallCount = 0

    func persistDictionary(
        terms _: [VocabularyTerm],
        rules _: [VocabularyReplacementRule]
    ) throws {
        persistCallCount += 1
        throw DictionaryPersistenceError.saveVerificationFailed
    }
}

@MainActor
final class VocabularyQuickTeachFlowTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testCorrectionAppliesToNextDictationAndKeepsRunningSnapshot() {
        let runningSnapshot = currentSnapshot()
        let firstResult = "enviei o arquivo para o verby"
        XCTAssertEqual(
            VocabularyReplacementRule.apply(rules: settings.vocabularyReplacementRules, to: firstResult),
            firstResult
        )

        let viewModel = VocabularySettingsViewModel(settings: settings)
        let outcome = viewModel.saveQuickTeach(
            origins: "verby",
            destination: "Verbi",
            alsoAddVocabularyTerm: true
        )

        XCTAssertEqual(outcome, .saved(vocabularyTermAdded: true))
        XCTAssertEqual(runningSnapshot, .empty)

        let nextSnapshot = currentSnapshot()
        XCTAssertEqual(nextSnapshot.replacementRules.map(\.replace), ["Verbi"])
        XCTAssertEqual(nextSnapshot.terms.map(\.term), ["Verbi"])
        XCTAssertEqual(
            VocabularyReplacementRule.apply(rules: nextSnapshot.replacementRules, to: "abri o verby de novo"),
            "abri o Verbi de novo"
        )
    }

    func testTeachingOnlySubstitutionDoesNotAddVocabularyTerm() {
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let outcome = viewModel.saveQuickTeach(
            origins: "verby",
            destination: "Verbi",
            alsoAddVocabularyTerm: false
        )

        XCTAssertEqual(outcome, .saved(vocabularyTermAdded: false))
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
    }

    func testTeachingDuplicateKeepsOneEntryAndOneTerm() {
        let viewModel = VocabularySettingsViewModel(settings: settings)
        _ = viewModel.saveQuickTeach(origins: "verby", destination: "Verbi", alsoAddVocabularyTerm: true)

        let duplicate = viewModel.saveQuickTeach(
            origins: "VERBY",
            destination: "Verbi",
            alsoAddVocabularyTerm: true
        )

        XCTAssertEqual(duplicate, .saved(vocabularyTermAdded: false))
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.normalizedFindVariants.count, 1)
        XCTAssertEqual(settings.vocabularyTerms.count, 1)
    }

    func testCancellingConflictDraftLeavesDictionaryUntouched() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "verby", replace: "Verby")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        XCTAssertEqual(
            viewModel.saveQuickTeach(origins: "verby", destination: "Verbi", alsoAddVocabularyTerm: true),
            .conflicts
        )
        XCTAssertTrue(viewModel.stageQuickTeachConflictMove())
        XCTAssertTrue(viewModel.hasPendingQuickMove)

        viewModel.cancelQuickTeachDraft()

        XCTAssertFalse(viewModel.hasPendingQuickMove)
        XCTAssertTrue(viewModel.pendingConflicts.isEmpty)
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Verby"])
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
    }

    func testPersistenceFailureReportsErrorAndLeavesDictionaryUntouched() {
        let store = FailingDictionaryStore()
        let viewModel = VocabularySettingsViewModel(settings: settings, quickTeachStore: store)

        let outcome = viewModel.saveQuickTeach(
            origins: "verby",
            destination: "Verbi",
            alsoAddVocabularyTerm: true
        )

        guard case let .failed(error) = outcome else {
            return XCTFail("Expected a persistence failure, got \(outcome)")
        }
        XCTAssertEqual(store.persistCallCount, 1)
        XCTAssertTrue(store.vocabularyReplacementRules.isEmpty)
        XCTAssertTrue(store.vocabularyTerms.isEmpty)
        XCTAssertTrue(settings.vocabularyReplacementRules.isEmpty)
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)

        let description = error.errorDescription ?? ""
        XCTAssertFalse(description.contains("verby"))
        XCTAssertFalse(description.contains("Verbi"))
    }

    func testConflictMoveStaysInDraftUntilSave() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "verby", replace: "Verby")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let outcome = viewModel.saveQuickTeach(
            origins: "verby",
            destination: "Verbi",
            alsoAddVocabularyTerm: true
        )

        XCTAssertEqual(outcome, .conflicts)
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Verby"])

        XCTAssertTrue(viewModel.stageQuickTeachConflictMove())
        XCTAssertTrue(viewModel.hasPendingQuickMove)
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Verby"])
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)

        let saved = viewModel.saveQuickTeach(
            origins: "verby",
            destination: "Verbi",
            alsoAddVocabularyTerm: true
        )

        XCTAssertEqual(saved, .saved(vocabularyTermAdded: true))
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Verbi"])
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.normalizedFindVariants, ["verby"])
        XCTAssertEqual(settings.vocabularyTerms.map(\.term), ["Verbi"])
    }

    private func currentSnapshot() -> VocabularySnapshot {
        VocabularySnapshot(
            terms: settings.vocabularyTerms,
            replacementRules: settings.vocabularyReplacementRules
        )
    }
}
