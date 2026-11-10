@testable import VerbiCore
import XCTest

@MainActor
final class VocabularyTeachShortcutTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testNoDefaultShortcutIsAssigned() {
        XCTAssertNil(settings.vocabularyTeachShortcutDefinition)
    }

    func testShortcutConflictingWithNotesPanelIsRejected() async {
        let viewModel = VocabularyTeachShortcutSettingsViewModel()
        viewModel.vocabularyTeachShortcutDefinition = AppSettingsStore.defaultMeetingNotesShortcutDefinition
        await Task.yield()

        XCTAssertNil(settings.vocabularyTeachShortcutDefinition)
        XCTAssertNotNil(viewModel.vocabularyTeachShortcutConflictMessage)
    }

    func testFreeShortcutPersistsAndJoinsConflictBindings() async {
        let shortcut = ShortcutDefinition(
            modifiers: [.control, .option],
            primaryKey: .letter("T", keyCode: 0x11),
            trigger: .singleTap
        )
        let viewModel = VocabularyTeachShortcutSettingsViewModel()

        viewModel.vocabularyTeachShortcutDefinition = shortcut
        await Task.yield()

        XCTAssertEqual(settings.vocabularyTeachShortcutDefinition, shortcut)
        XCTAssertNil(viewModel.vocabularyTeachShortcutConflictMessage)
        XCTAssertTrue(
            settings.configuredShortcutBindings.contains { binding in
                binding.actionID == .vocabularyTeach && binding.shortcut == shortcut
            }
        )
    }
}
