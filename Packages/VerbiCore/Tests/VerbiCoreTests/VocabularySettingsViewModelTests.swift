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

    func testSaveEntry_WithEmptyOrigins_SetsValidationError() {
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveEntry(origins: "   ", destination: "OpenAI")

        XCTAssertFalse(didSave)
        XCTAssertEqual(viewModel.editorValidationError, .emptyOrigins)
        XCTAssertTrue(settings.vocabularyReplacementRules.isEmpty)
    }

    func testSaveEntry_NormalizesVariantsAndDestinationBeforeSaving() {
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveEntry(
            origins: " raycast, reycast , recast, raycast ",
            destination: " Raycast "
        )

        XCTAssertTrue(didSave)
        XCTAssertNil(viewModel.editorValidationError)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.find, "raycast, reycast, recast")
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.replace, "Raycast")
    }

    func testSaveEntry_ConsolidatesVariantsIntoExistingDestination() {
        let existing = VocabularyReplacementRule(find: "raycast", replace: "Raycast")
        settings.vocabularyReplacementRules = [existing]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveEntry(origins: "reycast, recast", destination: "Raycast")

        XCTAssertTrue(didSave)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.id, existing.id)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.find, "reycast, recast, raycast")
    }

    func testSaveEntry_KeepsCaseSensitiveDestinationsApart() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "you ess", replace: "US")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveEntry(origins: "us", destination: "us")

        XCTAssertTrue(didSave)
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["US", "us"])
        XCTAssertEqual(viewModel.groups.map(\.destination), ["US", "us"])
    }

    func testSaveEntry_WithEmptyDestinationIsValidTextRemoval() {
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveEntry(origins: "hum, uhm", destination: "   ")

        XCTAssertTrue(didSave)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.replace, "")
        XCTAssertTrue(viewModel.groups.first?.isTextRemoval == true)
    }

    // MARK: - Conflicts

    func testSaveEntry_WhenOriginBelongsToAnotherDestination_RequiresExplicitResolution() {
        let existing = VocabularyReplacementRule(find: "raycast, reycast", replace: "Raycast")
        settings.vocabularyReplacementRules = [existing]
        let viewModel = VocabularySettingsViewModel(settings: settings)

        let didSave = viewModel.saveEntry(origins: "raycast, recast", destination: "Other")

        XCTAssertFalse(didSave)
        XCTAssertEqual(viewModel.editorValidationError, .originConflict)
        XCTAssertEqual(viewModel.pendingConflicts.map(\.origin), ["raycast"])
        XCTAssertEqual(viewModel.pendingConflicts.map(\.destination), ["Raycast"])
        XCTAssertEqual(settings.vocabularyReplacementRules, [existing], "Nothing saves before the explicit move")
    }

    func testResolveOriginConflicts_MovesOriginAndDropsEmptiedEntry() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "raycast", replace: "Raycast")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        XCTAssertFalse(viewModel.saveEntry(origins: "raycast, recast", destination: "Other"))

        let didResolve = viewModel.resolveOriginConflictsByMoving()

        XCTAssertTrue(didResolve)
        XCTAssertTrue(viewModel.pendingConflicts.isEmpty)
        XCTAssertNil(viewModel.editorValidationError)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.replace, "Other")
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.find, "raycast, recast")
    }

    func testResolveOriginConflicts_KeepsOtherEntryWhenItStillHasVariants() {
        settings.vocabularyReplacementRules = [
            VocabularyReplacementRule(find: "raycast, reycast", replace: "Raycast")
        ]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        XCTAssertFalse(viewModel.saveEntry(origins: "raycast", destination: "Other"))

        XCTAssertTrue(viewModel.resolveOriginConflictsByMoving())

        XCTAssertEqual(settings.vocabularyReplacementRules.count, 2)
        XCTAssertEqual(settings.vocabularyReplacementRules[0].replace, "Raycast")
        XCTAssertEqual(settings.vocabularyReplacementRules[0].find, "reycast")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].replace, "Other")
        XCTAssertEqual(settings.vocabularyReplacementRules[1].find, "raycast")
    }

    func testCancelOriginConflicts_LeavesStoredEntriesUntouched() {
        let existing = VocabularyReplacementRule(find: "raycast", replace: "Raycast")
        settings.vocabularyReplacementRules = [existing]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        XCTAssertFalse(viewModel.saveEntry(origins: "raycast", destination: "Other"))

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

        XCTAssertEqual(viewModel.groups.count, 2)
        XCTAssertEqual(viewModel.conflictingOriginCount, 1)
        XCTAssertEqual(viewModel.conflictingOriginKeys, ["raycast"])
    }

    // MARK: - Editing

    func testEditingEntry_PreservesIdentityAndPosition() throws {
        let first = VocabularyReplacementRule(find: "raycast", replace: "Raycast")
        let second = VocabularyReplacementRule(find: "claud", replace: "Claude")
        settings.vocabularyReplacementRules = [first, second]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let entry = try XCTUnwrap(viewModel.groups.first { $0.destination == "Raycast" })

        viewModel.startEditingEntry(entry)
        let didSave = viewModel.saveEntry(origins: "reycast, recast", destination: "Raycast App")

        XCTAssertTrue(didSave)
        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.id), [first.id, second.id])
        XCTAssertEqual(settings.vocabularyReplacementRules[0].find, "reycast, recast")
        XCTAssertEqual(settings.vocabularyReplacementRules[0].replace, "Raycast App")
    }

    func testEditingEntryIntoExistingDestinationConsolidatesAndKeepsEditedIdentity() throws {
        let edited = VocabularyReplacementRule(find: "reycast", replace: "Raycast")
        let destination = VocabularyReplacementRule(find: "raycast", replace: "Raycast App")
        settings.vocabularyReplacementRules = [edited, destination]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let entry = try XCTUnwrap(viewModel.groups.first { $0.destination == "Raycast" })

        viewModel.startEditingEntry(entry)
        let didSave = viewModel.saveEntry(origins: "reycast", destination: "Raycast App")

        XCTAssertTrue(didSave)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.id, edited.id)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.find, "reycast, raycast")
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.replace, "Raycast App")
    }

    // MARK: - Variant removal

    func testRemoveOrigin_KeepsTheRestOfTheEntry() throws {
        let rule = VocabularyReplacementRule(find: "raycast, reycast, recast", replace: "Raycast")
        settings.vocabularyReplacementRules = [rule]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let entry = try XCTUnwrap(viewModel.groups.first)

        let didRemove = viewModel.removeOrigin("ReyCast", from: entry)

        XCTAssertTrue(didRemove)
        XCTAssertEqual(settings.vocabularyReplacementRules.count, 1)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.id, rule.id)
        XCTAssertEqual(settings.vocabularyReplacementRules.first?.find, "raycast, recast")
    }

    func testRemoveOrigin_RefusesToRemoveTheLastVariant() throws {
        let rule = VocabularyReplacementRule(find: "raycast", replace: "Raycast")
        settings.vocabularyReplacementRules = [rule]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let entry = try XCTUnwrap(viewModel.groups.first)

        let didRemove = viewModel.removeOrigin("raycast", from: entry)

        XCTAssertFalse(didRemove)
        XCTAssertEqual(settings.vocabularyReplacementRules, [rule])
    }

    // MARK: - Deletion

    func testDeletingEntryRemovesEveryVariantOfThatDestinationOnly() throws {
        let raycast = VocabularyReplacementRule(find: "raycast, reycast", replace: "Raycast")
        let claude = VocabularyReplacementRule(find: "claud", replace: "Claude")
        settings.vocabularyReplacementRules = [raycast, claude]
        let viewModel = VocabularySettingsViewModel(settings: settings)
        let entry = try XCTUnwrap(viewModel.groups.first { $0.destination == "Raycast" })

        viewModel.confirmDelete(entry)
        XCTAssertTrue(viewModel.showDeleteConfirmation)
        viewModel.executeDelete()

        XCTAssertEqual(settings.vocabularyReplacementRules.map(\.replace), ["Claude"])
        XCTAssertFalse(viewModel.showDeleteConfirmation)
        XCTAssertNil(viewModel.entryToDelete)
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
}
