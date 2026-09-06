@testable import MeetingAssistantCore
import XCTest

@MainActor
final class MeetingNotesShortcutVMTests: XCTestCase {
    private var settings: AppSettingsStore!

    override func setUp() async throws {
        settings = .shared
        settings.resetToDefaults()
    }

    override func tearDown() async throws {
        settings.resetToDefaults()
        settings = nil
    }

    func testValidShortcutPersistsMeetingNotesShortcutDefinition() async {
        let viewModel = MeetingNotesShortcutSettingsViewModel()
        let shortcut = ShortcutDefinition(
            modifiers: [.control, .option],
            primaryKey: .letter("N", keyCode: 0x2d),
            trigger: .singleTap,
        )

        viewModel.meetingNotesShortcutDefinition = shortcut
        await Task.yield()

        XCTAssertEqual(settings.meetingNotesShortcutDefinition, shortcut)
        XCTAssertNil(viewModel.meetingNotesShortcutConflictMessage)
    }

    func testConfiguredShortcutBindingsIncludesMeetingNotesShortcut() {
        let shortcut = ShortcutDefinition(
            modifiers: [.control, .option],
            primaryKey: .letter("N", keyCode: 0x2d),
            trigger: .singleTap,
        )

        settings.meetingNotesShortcutDefinition = shortcut

        XCTAssertTrue(
            settings.configuredShortcutBindings.contains(where: { binding in
                binding.actionID == .meetingNotes && binding.shortcut == shortcut
            }),
        )
    }

    func testFnShortcutIsRejectedForMeetingNotesHotkey() async {
        let viewModel = MeetingNotesShortcutSettingsViewModel()
        let shortcut = ShortcutDefinition(
            modifiers: [.fn, .command],
            primaryKey: .letter("N", keyCode: 0x2d),
            trigger: .singleTap,
        )

        viewModel.meetingNotesShortcutDefinition = shortcut
        await Task.yield()

        XCTAssertEqual(
            settings.meetingNotesShortcutDefinition,
            AppSettingsStore.defaultMeetingNotesShortcutDefinition,
        )
        XCTAssertEqual(
            viewModel.meetingNotesShortcutConflictMessage,
            "settings.general.cancel_recording_shortcut_unsupported".localized,
        )
    }
}
