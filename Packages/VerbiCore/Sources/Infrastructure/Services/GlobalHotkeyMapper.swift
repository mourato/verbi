import Carbon
import Foundation

public struct GlobalHotkeyDescriptor {
    public let keyCode: UInt32
    public let modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

public enum GlobalHotkeyMapper {
    public static func descriptor(for definition: ShortcutDefinition) -> GlobalHotkeyDescriptor? {
        guard definition.trigger == .singleTap,
              let primaryKey = definition.primaryKey
        else {
            return nil
        }

        var modifiers: UInt32 = 0
        for modifier in definition.modifiers {
            switch modifier {
            case .leftCommand, .rightCommand, .command:
                modifiers |= UInt32(cmdKey)
            case .leftShift, .rightShift, .shift:
                modifiers |= UInt32(shiftKey)
            case .leftOption, .rightOption, .option:
                modifiers |= UInt32(optionKey)
            case .leftControl, .rightControl, .control:
                modifiers |= UInt32(controlKey)
            case .fn:
                return nil
            }
        }

        return GlobalHotkeyDescriptor(
            keyCode: UInt32(primaryKey.keyCode),
            modifiers: modifiers
        )
    }
}
