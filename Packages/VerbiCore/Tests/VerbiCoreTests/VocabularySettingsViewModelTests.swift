@testable import VerbiCore
import XCTest

@MainActor
final class VocabularySettingsViewModelTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    // MARK: - Saving

    func testSaveWord_WithBothEmpty_SetsValidationError() {
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveWord(word: "   ", heardAs: " , ")

        XCTAssertFalse(didSave)
        XCTAssertEqual(viewModel.editorValidationError, .emptyWordAndHeardAs)
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
        XCTAssertTrue(settings.vocabularyReplacementRules.isEmpty)
    }

    func testSaveWord_NormalizesVariantsAndWordBeforeSaving() {
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveWord(
            word: " Raycast ",
            heardAs: " raycast, reycast , recast, raycast "
        )

        XCTAssertTrue(didSave)
        XCTAssertNil(viewModel.editorValidationError)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.find, "raycast, reycast, recast")
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.replace, "Raycast")
    }

    func testSaveWord_KeepsCaseSensitiveWordsApart() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "you ess", replace: "US")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveWord(word: "us", heardAs: "us")

        XCTAssertTrue(didSave)
        XCTAssertEqual(viewModel.words.map(\.word), ["US", "us"])
    }

    func testSaveWord_WithEmptyWordIsValidTextRemoval() {
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveWord(word: "   ", heardAs: "hum, uhm")

        XCTAssertTrue(didSave)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.replace, "")
        XCTAssertEqual(viewModel.words.first?.isTextRemoval, true)
    }

    // MARK: - Conflicts

    func testSaveWord_WhenVariantBelongsToAnotherWord_RequiresExplicitResolution() {
        let existing = VocabularyReplacementRule(find: "raycast, reycast", replace: "Raycast")
        settings.vocabularyReplacementRules = [existing]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveWord(word: "Other", heardAs: "raycast, recast")

        XCTAssertFalse(didSave)
        XCTAssertEqual(viewModel.editorValidationError, .originConflict)
        XCTAssertEqual(viewModel.pendingConflicts.map(\.origin), ["raycast"])
        XCTAssertEqual(viewModel.pendingConflicts.map(\.destination), ["Raycast"])
        XCTAssertEqual(settings.vocabularyReplacementRules, [existing], "Nothing saves before the explicit move")
    }

    func testResolveOriginConflicts_MovesVariantAndDropsEmptiedWord() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "raycast", replace: "Raycast")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        XCTAssertFalse(viewModel.saveWord(word: "Other", heardAs: "raycast, recast"))

        let didResolve = viewModel.resolveOriginConflictsByMoving()

        XCTAssertTrue(didResolve)
        XCTAssertTrue(viewModel.pendingConflicts.isEmpty)
        XCTAssertNil(viewModel.editorValidationError)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.replace, "Other")
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.find, "raycast, recast")
    }

    func testResolveOriginConflicts_KeepsOtherWordWhenItStillHasVariants() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "raycast, reycast", replace: "Raycast")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        XCTAssertFalse(viewModel.saveWord(word: "Other", heardAs: "raycast"))

        XCTAssertTrue(viewModel.resolveOriginConflictsByMoving())

        XCTAssertEqual(settings.vocabularyReplacementRules.count, 2)
        XCTAssertEqual(settings.vocabularyReplacementRules[0].replace, "Raycast")
        XCTAssertEqual(settings.vocabularyReplacementRules[0].find, "reycast")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].replace, "Other")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].find, "raycast")
    }

    func testCancelOriginConflicts_LeavesStoredWordsUntouched() {
        let existing = VocabularyReplacementRule(find: "raycast", replace: "Raycast")
        settings.vocabularyReplacementRules = [existing]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        XCTAssertFalse(viewModel.saveWord(word: "Other", heardAs: "raycast"))

        viewModel.cancelOriginConflicts()

        XCTAssertTrue(viewModel.pendingConflicts.isEmpty)
        XCTAssertNil(viewModel.editorValidationError)
        XCTAssertEqual(settings.vocabularyReplacementRules, [existing])
    }

    func testLegacyConflictingOriginsStayVisibleUntilResolved() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "raycast", replace: "Raycast"),
            VocabularyReplacementRule(find: "raycast", replace: "Ray Cast")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        XCTAssertEqual(viewModel.words.count, 2)
        XCTAssertEqual(viewModel.conflictingOriginCount, 1)
        XCTAssertEqual(viewModel.conflictingOriginKeys, ["raycast"])
    }

    // MARK: - Editing

    func testEditingWordIntoExistingWordIsRejectedAsDuplicate() throws {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "reycast", replace: "Raycast"),
            VocabularyReplacementRule(find: "raycast", replace: "Raycast App")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let word = try XCTUnwrap(viewModel.words.first { $0.word == "Raycast" })

        viewModel.startEditingWord(word)
        let didSave = viewModel.saveWord(word: "Raycast App", heardAs: "reycast")

        XCTAssertFalse(didSave)
        XCTAssertEqual(viewModel.editorValidationError, .duplicateWord("Raycast App"))
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 2)
    }

    // MARK: - Variant removal

    func testRemoveVariant_KeepsTheRestOfTheWord() throws {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "raycast, reycast, recast", replace: "Raycast")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let word = try XCTUnwrap(viewModel.words.first)

        let didRemove = viewModel.removeVariant("ReyCast", from: word)

        XCTAssertTrue(didRemove)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.find, "raycast, recast")
    }

    func testRemoveVariant_RefusesToRemoveTheLastVariant() throws {
        let rule = VocabularyReplacementRule(find: "raycast", replace: "Raycast")
        settings.vocabularyReplacementRules = [rule]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let word = try XCTUnwrap(viewModel.words.first)

        let didRemove = viewModel.removeVariant("raycast", from: word)

        XCTAssertFalse(didRemove)
        XCTAssertEqual(settings.vocabularyReplacementRules, [rule])
    }

    // MARK: - Deletion

    func testDeletingWordRemovesOnlyThatWord() throws {
        let raycast = VocabularyReplacementRule(find: "raycast, reycast", replace: "Raycast")
        let claude = VocabularyReplacementRule(find: "claud", replace: "Claude")
        settings.vocabularyReplacementRules = [raycast, claude]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let word = try XCTUnwrap(viewModel.words.first { $0.word == "Raycast" })

        viewModel.confirmDeleteWord(word)
        XCTAssertTrue(viewModel.showWordDeleteConfirmation)
        viewModel.executeDeleteWord()

        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Claude"])
        XCTAssertFalse(viewModel.showWordDeleteConfirmation)
        XCTAssertNil(viewModel.wordToDelete)
    }

    // MARK: - Reload

    func testGroupsReflectExternalStoreMutation() {
        let viewModel = VocabularySettingsViewModel(settings: settings)
        XCTAssertTrue(viewModel.groups.isEmpty)

        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "external", replace: "External")
        ]

        XCTAssertEqual(viewModel.groups.map(\.destination), ["External"])
    }

    // MARK: - Words

    func testSaveWordWithoutVariantsCreatesOnlyATerm() {
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveWord(word: "Raycast", heardAs: "  ")

        XCTAssertTrue(didSave)
        XCTAssertEqual(settings.vocabularyTerms.map(\.term), ["Raycast"])
        XCTAssertTrue(settings.vocabularyReplacementRules.isEmpty)
        XCTAssertEqual(viewModel.words.map(\.word), ["Raycast"])
        XCTAssertEqual(viewModel.words.first?.heardAs, [])
    }

    func testSaveWordWithVariantsCreatesOnlyRules() {
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveWord(word: "Raycast", heardAs: "raycast, reycast")

        XCTAssertTrue(didSave)
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Raycast"])
        XCTAssertEqual(viewModel.words.map(\.word), ["Raycast"])
        XCTAssertEqual(viewModel.words.first?.heardAs, ["raycast", "reycast"])
    }

    func testSaveWordNormalizesWhitespaceAndUnicode() {
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveWord(word: "  Café  ", heardAs: "  ")

        XCTAssertTrue(didSave)
        XCTAssertEqual(settings.vocabularyTerms.first?.term, "Café")
    }

    func testSaveWordRejectsCaseInsensitiveDuplicateTerm() {
        settings.vocabularyTerms = [VocabularyTerm(term: "SwiftUI", definition: "")]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveWord(word: "swiftui", heardAs: "")

        XCTAssertFalse(didSave)
        XCTAssertEqual(viewModel.editorValidationError, .duplicateWord("swiftui"))
        XCTAssertEqual(settings.vocabularyTerms.map(\.term), ["SwiftUI"])
    }

    func testSaveWordRejectsDuplicateDestination() throws {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "groc", replace: "Groq")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveWord(word: "Groq", heardAs: "grok")

        XCTAssertFalse(didSave)
        XCTAssertEqual(viewModel.editorValidationError, .duplicateWord("Groq"))
        let words = viewModel.words
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(try XCTUnwrap(words.first).heardAs, ["groc"])
    }

    func testEditingWordPreservesTermIdentityAndDefinition() throws {
        let existing = VocabularyTerm(term: "SwiftUI", definition: "Apple's UI framework")
        settings.vocabularyTerms = [existing]
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "swift you eye", replace: "SwiftUI")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let word = try XCTUnwrap(viewModel.words.first)

        viewModel.startEditingWord(word)
        let didSave = viewModel.saveWord(word: "Swift UI", heardAs: "swift you eye")

        XCTAssertTrue(didSave)
        XCTAssertEqual(settings.vocabularyTerms.count, 1)
        XCTAssertEqual(settings.vocabularyTerms.first?.id, existing.id)
        XCTAssertEqual(settings.vocabularyTerms.first?.term, "Swift UI")
        XCTAssertEqual(settings.vocabularyTerms.first?.definition, "Apple's UI framework")
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Swift UI"])
        XCTAssertFalse(viewModel.showWordEditor)
    }

    func testDeletingWordRemovesTermAndRulesInOneWrite() throws {
        settings.vocabularyTerms = [VocabularyTerm(term: "Raycast", definition: "kept")]
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "raycast, reycast", replace: "Raycast"),
            VocabularyReplacementRule(find: "claud", replace: "Claude")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let word = try XCTUnwrap(viewModel.words.first { $0.word == "Raycast" })

        viewModel.confirmDeleteWord(word)
        XCTAssertTrue(viewModel.showWordDeleteConfirmation)
        viewModel.executeDeleteWord()

        XCTAssertEqual(settings.vocabularyTerms.map(\.term), [])
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Claude"])
        XCTAssertEqual(viewModel.words.map(\.word), ["Claude"])
        XCTAssertFalse(viewModel.showWordDeleteConfirmation)
        XCTAssertNil(viewModel.wordToDelete)
    }

    func testDeletingRemovalWordRemovesEveryRemovalRule() throws {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "hum, uhm", replace: ""),
            VocabularyReplacementRule(find: "groc", replace: "Groq")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let word = try XCTUnwrap(viewModel.words.first(where: \.isTextRemoval))

        viewModel.confirmDeleteWord(word)
        viewModel.executeDeleteWord()

        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Groq"])
    }

    func testRemoveVariantFromWordKeepsTheRest() throws {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "raycast, reycast, recast", replace: "Raycast")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let word = try XCTUnwrap(viewModel.words.first)

        let didRemove = viewModel.removeVariant("ReyCast", from: word)

        XCTAssertTrue(didRemove)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.find, "raycast, recast")
    }

    func testWordsProjectFromTermsAndRules() {
        settings.vocabularyTerms = [VocabularyTerm(term: "SwiftUI", definition: "")]
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "groc", replace: "Groq")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        XCTAssertEqual(viewModel.words.map(\.word), ["Groq", "SwiftUI"])
    }
}
