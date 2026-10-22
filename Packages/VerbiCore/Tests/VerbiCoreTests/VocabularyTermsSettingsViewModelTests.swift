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
            VocabularyTerm(term: "Drop", definition: ""),
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
}
