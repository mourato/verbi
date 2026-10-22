import Foundation

public enum ShortcutInputEventKind: String, Codable, Equatable, Sendable {
    case flagsChanged
    case keyDown
    case keyUp
}

public struct ShortcutInputEvent: Codable, Equatable, Sendable {
    public let kind: ShortcutInputEventKind
    public let keyCode: UInt16
    public let modifierFlagsRawValue: UInt
    public let isRepeat: Bool
    public let charactersIgnoringModifiers: String?

    public init(
        kind: ShortcutInputEventKind,
        keyCode: UInt16,
        modifierFlagsRawValue: UInt,
        isRepeat: Bool,
        charactersIgnoringModifiers: String? = nil
    ) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifierFlagsRawValue
        self.isRepeat = isRepeat
        self.charactersIgnoringModifiers = charactersIgnoringModifiers
    }
}

@MainActor
public protocol ShortcutInputBackend: AnyObject {
    typealias EventHandler = (ShortcutInputEvent) -> Void
    typealias LocalPropagationPolicy = (ShortcutInputEvent) -> Bool

    var isFlagsChangedMonitoringActive: Bool { get }
    var isKeyDownMonitoringActive: Bool { get }
    var isKeyUpMonitoringActive: Bool { get }

    func setFlagsChangedHandler(_ handler: EventHandler?)
    func setKeyDownHandler(_ handler: EventHandler?)
    func setKeyUpHandler(_ handler: EventHandler?)

    func startFlagsChangedMonitoring()
    func stopFlagsChangedMonitoring()

    func startKeyDownMonitoring(shouldReturnLocalEvent: LocalPropagationPolicy?)
    func stopKeyDownMonitoring()

    func startKeyUpMonitoring()
    func stopKeyUpMonitoring()

    func stopAllMonitoring()
}
