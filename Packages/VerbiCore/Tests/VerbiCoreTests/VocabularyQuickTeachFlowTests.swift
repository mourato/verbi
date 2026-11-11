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
            destination: "Verbi"
        )

        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(runningSnapshot, .empty)

        let nextSnapshot = currentSnapshot()
        XCTAssertEqual(nextSnapshot.replacementRules.map(\.replace), ["Verbi"])
        XCTAssertEqual(nextSnapshot.terms.map(\.term), ["Verbi"])
        XCTAssertEqual(
            VocabularyReplacementRule.apply(rules: nextSnapshot.replacementRules, to: "abri o verby de novo"),
            "abri o Verbi de novo"
        )
    }

    func testTeachingCorrectionDoesNotCreateASavedTerm() {
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let outcome = viewModel.saveQuickTeach(
            origins: "verby",
            destination: "Verbi"
        )

        XCTAssertEqual(outcome, .saved)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
        // The corrected spelling still reaches the next snapshot as a hint.
        XCTAssertEqual(currentSnapshot().terms.map(\.term), ["Verbi"])
    }

    func testTeachingDuplicateKeepsOneEntry() {
        let viewModel = VocabularySettingsViewModel(settings: settings)
        _ = viewModel.saveQuickTeach(origins: "verby", destination: "Verbi")

        let duplicate = viewModel.saveQuickTeach(
            origins: "VERBY",
            destination: "Verbi"
        )

        XCTAssertEqual(duplicate, .saved)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        // Consolidation keeps the latest taught spelling first.
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.normalizedFindVariants, ["VERBY"])
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
    }

    func testCancellingConflictDraftLeavesDictionaryUntouched() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "verby", replace: "Verby")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        XCTAssertEqual(
            viewModel.saveQuickTeach(origins: "verby", destination: "Verbi"),
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
            destination: "Verbi"
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

        let outcome = viewModel.saveQuickTeach(origins: "verby", destination: "Verbi")

        XCTAssertEqual(outcome, .conflicts)
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Verby"])

        XCTAssertTrue(viewModel.stageQuickTeachConflictMove())
        XCTAssertTrue(viewModel.hasPendingQuickMove)
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Verby"])
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)

        let saved = viewModel.saveQuickTeach(
            origins: "verby",
            destination: "Verbi"
        )

        XCTAssertEqual(saved, .saved)
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Verbi"])
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.normalizedFindVariants, ["verby"])
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
    }

    private func currentSnapshot() -> VocabularySnapshot {
        VocabularySnapshot(
            terms: VocabularyTerm.hints(
                savedTerms: settings.vocabularyTerms,
                replacementRules: settings.vocabularyReplacementRules
            ),
            replacementRules: settings.vocabularyReplacementRules
        )
    }
}
