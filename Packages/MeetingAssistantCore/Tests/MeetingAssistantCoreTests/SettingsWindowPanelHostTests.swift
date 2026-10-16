import AppKit
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class SettingsWindowPanelHostTests: XCTestCase {
    func testFullWindowBoundsAndToolbarOutsideClick() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        defer { window.close() }
        window.isReleasedWhenClosed = false
        window.toolbar = NSToolbar(identifier: "PanelHostTest")
        let host = SettingsWindowPanelHost()
        host.attach(to: window)
        defer { host.detach() }
        window.contentView?.superview?.layoutSubtreeIfNeeded()
        let content = try XCTUnwrap(window.contentView)
        XCTAssertEqual(host.frame, content.frame)
        XCTAssertGreaterThan(host.frame.maxY, window.contentLayoutRect.maxY)
        XCTAssertTrue(content.superview?.subviews.last === host)
        host.isPresented = true
        host.requestedWidth = 400
        var dismissals = 0
        host.onDismiss = { dismissals += 1 }
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 100, y: content.frame.maxY - 2),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1
        ))
        XCTAssertNil(host.handle(event))
        XCTAssertEqual(dismissals, 1)
        host.isPresented = false
        XCTAssertNotNil(host.handle(event))
        XCTAssertEqual(dismissals, 1)
    }

    func testEscapeUsesEscapeActionAndWidthClamps() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = SettingsWindowPanelHost()
        host.attach(to: window)
        defer { host.detach() }
        host.isPresented = true
        var escapes = 0
        host.onEscape = { escapes += 1 }
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        ))
        XCTAssertNil(host.handle(event))
        XCTAssertEqual(escapes, 1)
        XCTAssertEqual(SettingsSidePanelLayout.resolvedWidth(requested: 1200, available: 900), 900)
        XCTAssertEqual(SettingsSidePanelLayout.resolvedWidth(requested: -1, available: 900), 0)
    }
}
