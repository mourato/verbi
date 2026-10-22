import AppKit
import VerbiCore

extension ShortcutInputEvent {
    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }
}
