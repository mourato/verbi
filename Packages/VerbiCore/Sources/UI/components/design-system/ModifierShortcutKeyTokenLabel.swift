import VerbiCoreInfrastructure

extension ModifierShortcutKey {
    func tokenLabel(in selectedKeys: [ModifierShortcutKey]) -> String {
        switch self {
        case .leftCommand:
            selectedKeys.contains(.rightCommand) ? "L⌘" : "⌘"
        case .rightCommand:
            selectedKeys.contains(.leftCommand) ? "R⌘" : "⌘"
        case .leftShift:
            selectedKeys.contains(.rightShift) ? "L⇧" : "⇧"
        case .rightShift:
            selectedKeys.contains(.leftShift) ? "R⇧" : "⇧"
        case .leftOption:
            selectedKeys.contains(.rightOption) ? "L⌥" : "⌥"
        case .rightOption:
            selectedKeys.contains(.leftOption) ? "R⌥" : "⌥"
        case .leftControl:
            selectedKeys.contains(.rightControl) ? "L⌃" : "⌃"
        case .rightControl:
            selectedKeys.contains(.leftControl) ? "R⌃" : "⌃"
        case .fn:
            "Fn"
        case .command:
            "⌘"
        case .shift:
            "⇧"
        case .option:
            "⌥"
        case .control:
            "⌃"
        }
    }
}
