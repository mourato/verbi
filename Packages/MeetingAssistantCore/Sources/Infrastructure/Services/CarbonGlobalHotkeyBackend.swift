import Carbon
import Foundation
import MeetingAssistantCoreCommon

@MainActor
public final class CarbonGlobalHotkeyBackend: GlobalHotkeyBackend {
    private static let signatureSeed: OSType = fourCharCode(AppIdentity.hotkeySignatureSeed)
    private static var signatureCounter: OSType = 0
    private let signature: OSType

    private var nextHotkeyID: UInt32 = 1
    private var eventHandlerRef: EventHandlerRef?
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var registrationsByID: [UInt32: HotkeyRegistration] = [:]
    private var logicalToInternalID: [String: UInt32] = [:]

    public init() {
        signature = Self.nextSignature()
    }

    public var registeredHotkeyCount: Int {
        hotkeyRefs.count
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.unregisterAll()
        }
    }

    @discardableResult
    public func register(_ registration: HotkeyRegistration) -> Bool {
        ensureEventHandlerInstalled()
        unregisterHotkey(withLogicalID: registration.id)

        let internalID = nextInternalID()
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: internalID)
        let status = RegisterEventHotKey(
            registration.keyCode,
            registration.modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            AppLogger.warning(
                "Failed to register global hotkey",
                category: .assistant,
                extra: [
                    "id": registration.id,
                    "keyCode": registration.keyCode,
                    "modifiers": registration.modifiers,
                    "status": status
                ]
            )
            return false
        }

        logicalToInternalID[registration.id] = internalID
        hotkeyRefs[internalID] = hotKeyRef
        registrationsByID[internalID] = registration
        return true
    }

    public func registerAll(_ registrations: [HotkeyRegistration]) {
        unregisterAll()
        for registration in registrations {
            _ = register(registration)
        }
    }

    public func unregisterAll() {
        for ref in hotkeyRefs.values {
            UnregisterEventHotKey(ref)
        }

        hotkeyRefs.removeAll()
        registrationsByID.removeAll()
        logicalToInternalID.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func unregisterHotkey(withLogicalID logicalID: String) {
        guard let internalID = logicalToInternalID[logicalID] else {
            return
        }

        if let ref = hotkeyRefs.removeValue(forKey: internalID) {
            UnregisterEventHotKey(ref)
        }

        registrationsByID.removeValue(forKey: internalID)
        logicalToInternalID.removeValue(forKey: logicalID)
    }

    private func nextInternalID() -> UInt32 {
        defer { nextHotkeyID &+= 1 }
        return nextHotkeyID
    }

    private func ensureEventHandlerInstalled() {
        guard eventHandlerRef == nil else {
            return
        }

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = eventTypes.withUnsafeMutableBufferPointer { bufferPointer in
            InstallEventHandler(
                GetEventDispatcherTarget(),
                Self.hotkeyEventHandler,
                bufferPointer.count,
                bufferPointer.baseAddress,
                userData,
                &eventHandlerRef
            )
        }

        if status != noErr {
            AppLogger.warning(
                "Failed to install global hotkey event handler",
                category: .assistant,
                extra: ["status": status]
            )
        }
    }

    @discardableResult
    private func handleEvent(_ event: EventRef?) -> Bool {
        guard let event else {
            return false
        }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr,
              hotKeyID.signature == signature,
              let registration = registrationsByID[hotKeyID.id]
        else {
            return false
        }

        switch GetEventKind(event) {
        case UInt32(kEventHotKeyPressed):
            Task { @MainActor in
                registration.onKeyDown()
            }
            return true
        case UInt32(kEventHotKeyReleased):
            Task { @MainActor in
                registration.onKeyUp()
            }
            return true
        default:
            return false
        }
    }

    private static let hotkeyEventHandler: EventHandlerUPP = { _, event, userData in
        guard let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let backend = Unmanaged<CarbonGlobalHotkeyBackend>
            .fromOpaque(userData)
            .takeUnretainedValue()
        return backend.handleEvent(event) ? noErr : OSStatus(eventNotHandledErr)
    }

    private static func nextSignature() -> OSType {
        defer { signatureCounter &+= 1 }
        return signatureSeed &+ signatureCounter
    }

    private static func fourCharCode(_ string: String) -> OSType {
        let scalars = Array(string.utf8.prefix(4))
        return scalars.reduce(into: OSType(0)) { result, scalar in
            result = (result << 8) + OSType(scalar)
        }
    }
}
