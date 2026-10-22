import Foundation

public struct HotkeyRegistration {
    public let id: String
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let onKeyDown: @MainActor () -> Void
    public let onKeyUp: @MainActor () -> Void

    public init(
        id: String,
        keyCode: UInt32,
        modifiers: UInt32,
        onKeyDown: @escaping @MainActor () -> Void,
        onKeyUp: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
    }
}

@MainActor
public protocol GlobalHotkeyBackend: AnyObject {
    var registeredHotkeyCount: Int { get }

    @discardableResult
    func register(_ registration: HotkeyRegistration) -> Bool

    func registerAll(_ registrations: [HotkeyRegistration])
    func unregisterAll()
}
