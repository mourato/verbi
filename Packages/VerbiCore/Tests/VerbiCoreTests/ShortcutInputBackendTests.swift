import AppKit
import VerbiCore
import XCTest

/// Tests for the pluggable input backend architecture.
/// These tests verify that the ShortcutInputBackend protocol and its implementations
/// work correctly for routing events.
@MainActor
final class ShortcutInputBackendTests: XCTestCase {

    // MARK: - Mock Backend Tests

    func testMockBackendQueuesEvents() {
        let backend = MockShortcutInputBackend()

        let event1 = ShortcutInputEvent.keyDown(keyCode: 0x24) // Return key
        let event2 = ShortcutInputEvent.keyUp(keyCode: 0x24)

        backend.queueEvent(event1)
        backend.queueEvent(event2)

        XCTAssertEqual(backend.queuedEventCount, 2)
    }

    func testMockBackendInjectsEvents() {
        let backend = MockShortcutInputBackend()

        var receivedEvents: [ShortcutInputEvent] = []

        backend.setKeyDownHandler { event in
            receivedEvents.append(event)
        }

        backend.startKeyDownMonitoring(shouldReturnLocalEvent: nil)

        let event = ShortcutInputEvent.keyDown(keyCode: 0x24)
        backend.injectEvent(event)

        XCTAssertEqual(receivedEvents.count, 1)
        XCTAssertEqual(receivedEvents.first?.keyCode, 0x24)
    }

    func testMockBackendReplaySequence() {
        let backend = MockShortcutInputBackend()

        var receivedEvents: [ShortcutInputEvent] = []

        backend.setKeyDownHandler { event in
            receivedEvents.append(event)
        }

        backend.setKeyUpHandler { event in
            receivedEvents.append(event)
        }

        backend.startKeyDownMonitoring(shouldReturnLocalEvent: nil)
        backend.startKeyUpMonitoring()

        // Queue a key press sequence
        let sequence = ShortcutTestSequence.keyPress(keyCode: 0x24)
        backend.queueEvents(sequence)

        // Replay all
        backend.replayAllEvents()

        XCTAssertEqual(receivedEvents.count, 2)
        XCTAssertEqual(receivedEvents[0].kind, .keyDown)
        XCTAssertEqual(receivedEvents[1].kind, .keyUp)
    }

    func testMockBackendClearQueue() {
        let backend = MockShortcutInputBackend()

        backend.queueEvent(.keyDown(keyCode: 0x24))
        backend.queueEvent(.keyUp(keyCode: 0x24))

        XCTAssertEqual(backend.queuedEventCount, 2)

        backend.clearQueue()

        XCTAssertEqual(backend.queuedEventCount, 0)
    }

    // MARK: - Event Factory Tests

    func testEventFactoryKeyDown() {
        let event = ShortcutInputEvent.keyDown(
            keyCode: 0x24,
            modifiers: .command,
            isRepeat: false,
            characters: "s",
        )

        XCTAssertEqual(event.kind, .keyDown)
        XCTAssertEqual(event.keyCode, 0x24)
        XCTAssertEqual(event.modifierFlagsRawValue, NSEvent.ModifierFlags.command.rawValue)
        XCTAssertFalse(event.isRepeat)
    }

    func testEventFactoryKeyUp() {
        let event = ShortcutInputEvent.keyUp(
            keyCode: 0x24,
            modifiers: .command,
            characters: "s",
        )

        XCTAssertEqual(event.kind, .keyUp)
        XCTAssertEqual(event.keyCode, 0x24)
    }

    func testEventFactoryFlagsChanged() {
        let event = ShortcutInputEvent.flagsChanged(
            modifiers: [.command, .shift],
        )

        XCTAssertEqual(event.kind, .flagsChanged)
        XCTAssertEqual(event.modifierFlagsRawValue, NSEvent.ModifierFlags.command.union(.shift).rawValue)
    }

    func testSystemFlagsChangedEventDoesNotReadKeyOnlyFields() throws {
        let systemEvent = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 55,
            ),
        )

        let event = ShortcutInputEvent(systemEvent: systemEvent)

        XCTAssertEqual(event.kind, .flagsChanged)
        XCTAssertEqual(event.keyCode, 55)
        XCTAssertEqual(event.modifierFlagsRawValue, NSEvent.ModifierFlags.command.rawValue)
        XCTAssertFalse(event.isRepeat)
        XCTAssertNil(event.charactersIgnoringModifiers)
    }

    // MARK: - Test Sequence Tests

    func testModifierPressSequence() {
        let sequence = ShortcutTestSequence.modifierPress(
            keyCode: 0x3b, // Control key
            flags: .control,
        )

        XCTAssertEqual(sequence.count, 4)
        XCTAssertEqual(sequence[0].kind, .flagsChanged)
        XCTAssertEqual(sequence[1].kind, .keyDown)
        XCTAssertEqual(sequence[1].keyCode, 0x3b)
        XCTAssertEqual(sequence[2].kind, .keyUp)
        XCTAssertEqual(sequence[3].kind, .flagsChanged)
    }

    func testShortcutPressSequence() {
        let sequence = ShortcutTestSequence.shortcutPress(
            keyCode: 0x01, // S key
            modifiers: .command,
        )

        XCTAssertEqual(sequence.count, 4)
        XCTAssertEqual(sequence[0].kind, .flagsChanged) // Cmd down
        XCTAssertEqual(sequence[1].kind, .keyDown) // S down
        XCTAssertEqual(sequence[1].modifierFlagsRawValue, NSEvent.ModifierFlags.command.rawValue)
        XCTAssertEqual(sequence[2].kind, .keyUp) // S up
        XCTAssertEqual(sequence[3].kind, .flagsChanged) // Cmd up
    }

    // MARK: - Backend Integration Tests

    func testBackendWithPresetEvents() {
        let events = ShortcutTestSequence.shortcutPress(
            keyCode: 0x01,
            modifiers: .command,
        )

        let backend = MockShortcutInputBackend.withEvents(events)

        XCTAssertEqual(backend.queuedEventCount, 4)

        backend.replayAllEvents()

        XCTAssertEqual(backend.queuedEventCount, 0)
    }
}
