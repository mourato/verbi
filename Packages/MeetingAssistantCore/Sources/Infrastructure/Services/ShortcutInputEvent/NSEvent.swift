import AppKit
import Foundation

public extension ShortcutInputEvent {
    init(systemEvent: NSEvent) {
        let kind: ShortcutInputEventKind = switch systemEvent.type {
        case .flagsChanged:
            .flagsChanged
        case .keyDown:
            .keyDown
        case .keyUp:
            .keyUp
        default:
            .keyDown
        }

        let isRepeat: Bool
        let charactersIgnoringModifiers: String?

        switch kind {
        case .flagsChanged:
            // AppKit may vend synthetic flagsChanged events from menu bar interaction
            // that do not support key-event accessors like isARepeat.
            isRepeat = false
            charactersIgnoringModifiers = nil
        case .keyDown, .keyUp:
            isRepeat = systemEvent.isARepeat
            charactersIgnoringModifiers = systemEvent.charactersIgnoringModifiers
        }

        self.init(
            kind: kind,
            keyCode: systemEvent.keyCode,
            modifierFlagsRawValue: systemEvent.modifierFlags.rawValue,
            isRepeat: isRepeat,
            charactersIgnoringModifiers: charactersIgnoringModifiers
        )
    }
}
