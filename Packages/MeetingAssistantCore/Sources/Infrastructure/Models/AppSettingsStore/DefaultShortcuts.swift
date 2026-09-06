import Foundation

public extension AppSettingsStore {
    static var defaultDictationShortcutDefinition: ShortcutDefinition {
        ShortcutDefinition(
            modifiers: [.option, .command],
            primaryKey: .letter("D", keyCode: 0x02),
            trigger: .singleTap,
        )
    }

    static var defaultAssistantShortcutDefinition: ShortcutDefinition {
        ShortcutDefinition(
            modifiers: [.option, .command],
            primaryKey: .letter("A", keyCode: 0x00),
            trigger: .singleTap,
        )
    }

    static var defaultMeetingShortcutDefinition: ShortcutDefinition {
        ShortcutDefinition(
            modifiers: [.option, .command],
            primaryKey: .letter("M", keyCode: 0x2e),
            trigger: .singleTap,
        )
    }

    /// Default notes-panel hotkey (⌃⌥N), matching the previous KeyboardShortcuts default.
    static var defaultMeetingNotesShortcutDefinition: ShortcutDefinition {
        ShortcutDefinition(
            modifiers: [.control, .option],
            primaryKey: .letter("N", keyCode: 0x2d),
            trigger: .singleTap,
        )
    }
}
