@testable import VerbiCore
import XCTest

@MainActor
final class VocabularyTermsSettingsViewModelTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testAddTermsFromBulkInputAddsCommaSeparatedTerms() {
        let viewModel = VocabularyTermsSettingsViewModel(settings: settings)
        viewModel.bulkInputText = " SwiftUI , Metal, CoreML "

        let added = viewModel.addTermsFromBulkInput()

        XCTAssertEqual(added, 3)
        XCTAssertEqual(viewModel.terms.map(\.term), ["CoreML", "Metal", "SwiftUI"])
        XCTAssertTrue(viewModel.bulkInputText.isEmpty)
        XCTAssertNil(viewModel.validationError)
    }

    func testAddTermsFromBulkInputRejectsEmptyInput() {
        let viewModel = VocabularyTermsSettingsViewModel(settings: settings)
        viewModel.bulkInputText = " , , "

        XCTAssertEqual(viewModel.addTermsFromBulkInput(), 0)
        XCTAssertEqual(viewModel.validationError, .emptyTerm)
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
    }

    func testAddTermsFromBulkInputSkipsDuplicatesAndReportsLast() {
        settings.vocabularyTerms = [VocabularyTerm(term: "SwiftUI", definition: "")]
        let viewModel = VocabularyTermsSettingsViewModel(settings: settings)
        viewModel.bulkInputText = "swiftui, Metal, metal"

        let added = viewModel.addTermsFromBulkInput()

        XCTAssertEqual(added, 1)
        XCTAssertEqual(Set(viewModel.terms.map(\.term)), Set(["Metal", "SwiftUI"]))
        XCTAssertEqual(viewModel.validationError, .duplicatedTerm("metal"))
    }

    func testClearEditorStateOnDelete() throws {
        settings.vocabularyTerms = [
            VocabularyTerm(term: "Keep", definition: ""),
            VocabularyTerm(term: "Drop", definition: "")
        ]
        let viewModel = VocabularyTermsSettingsViewModel(settings: settings)
        let drop = try XCTUnwrap(viewModel.terms.first(where: { $0.term == "Drop" }))

        viewModel.confirmDelete(drop)
        viewModel.executeDelete()

        XCTAssertEqual(viewModel.terms.map(\.term), ["Keep"])
        XCTAssertNil(viewModel.termToDelete)
        XCTAssertFalse(viewModel.showDeleteConfirmation)
    }

    func testReloadFromStoreReflectsExternalMutation() {
        let viewModel = VocabularyTermsSettingsViewModel(settings: settings)
        settings.vocabularyTerms = [VocabularyTerm(term: "External", definition: "")]

        viewModel.reloadFromStore()

        XCTAssertEqual(viewModel.terms.map(\.term), ["External"])
    }

    // MARK: - Editing

    func testEditingTermPreservesIdentityAndDefinition() throws {
        let existing = VocabularyTerm(term: "SwiftUI", definition: "")
        settings.vocabularyTerms = [existing]
        let viewModel = VocabularyTermsSettingsViewModel(settings: settings)
        let term = try XCTUnwrap(viewModel.terms.first)

        viewModel.startEditingTerm(term)
        let didSave = viewModel.saveTerm(term: "Swift UI", definition: " Apple's UI framework ")

        XCTAssertTrue(didSave)
        XCTAssertEqual(settings.vocabularyTerms.count, 1)
        XCTAssertEqual(settings.vocabularyTerms.first?.id, existing.id)
        XCTAssertEqual(settings.vocabularyTerms.first?.term, "Swift UI")
        XCTAssertEqual(settings.vocabularyTerms.first?.definition, "Apple's UI framework")
        XCTAssertFalse(viewModel.showTermEditor)
    }

    func testSavingTermRejectsEmptyTerm() {
        let viewModel = VocabularyTermsSettingsViewModel(settings: settings)

        let didSave = viewModel.saveTerm(term: "   ", definition: "unused")

        XCTAssertFalse(didSave)
        XCTAssertEqual(viewModel.validationError, .emptyTerm)
        XCTAssertTrue(settings.vocabularyTerms.isEmpty)
    }

    func testSavingTermRejectsCaseInsensitiveDuplicate() {
        settings.vocabularyTerms = [VocabularyTerm(term: "SwiftUI", definition: "")]
        let viewModel = VocabularyTermsSettingsViewModel(settings: settings)

        let didSave = viewModel.saveTerm(term: "swiftui", definition: "")

        XCTAssertFalse(didSave)
        XCTAssertEqual(viewModel.validationError, .duplicatedTerm("swiftui"))
        XCTAssertEqual(settings.vocabularyTerms.map(\.term), ["SwiftUI"])
    }

    func testSavingTermNormalizesWhitespaceAndUnicode() {
        let viewModel = VocabularyTermsSettingsViewModel(settings: settings)

        let didSave = viewModel.saveTerm(term: "  Cafe\u{301}  ", definition: " coffee ")

        XCTAssertTrue(didSave)
        XCTAssertEqual(settings.vocabularyTerms.first?.term, "Café")
        XCTAssertEqual(settings.vocabularyTerms.first?.definition, "coffee")
    }
}
