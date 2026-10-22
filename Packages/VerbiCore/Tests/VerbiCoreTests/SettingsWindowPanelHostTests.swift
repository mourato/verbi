import AppKit
import SwiftUI
@testable import VerbiCoreUI
import XCTest

@MainActor
final class SettingsWindowPanelHostTests: XCTestCase {
    func testMonitoringDrawerOwnsDeleteCommandAcrossHostingBoundary() throws {
        // The panel has a separate NSHostingController: an outer handler cannot
        // receive Delete commands from focus inside the monitoring drawer.
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/UI/pages/settings/sections/MeetingSettingsPage.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let contentStart = try XCTUnwrap(source.range(of: "MeetingMonitoringSettingsContent("))
        let panelEnd = try XCTUnwrap(source.range(of: "\n            }", range: contentStart.upperBound ..< source.endIndex))
        let drawerSubtree = source[contentStart.lowerBound ..< panelEnd.lowerBound]
        XCTAssertTrue(
            drawerSubtree.contains(".onDeleteCommand(perform: deleteSelectedWebTarget)"),
            "The monitoring drawer must own its Delete handler inside the panel content closure"
        )
    }

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

    func testModalIsolationAndResponderRestoration() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let trigger = NSTextField(string: "Trigger")
        let content = try XCTUnwrap(window.contentView)
        content.addSubview(trigger)
        window.makeFirstResponder(trigger)
        let host = SettingsWindowPanelHost()
        host.attach(to: window)
        defer { host.detach() }
        let first = NSTextField(string: "First")
        let last = NSTextField(string: "Last")
        host.hostingController.rootView = AnyView(PanelKeyViews(first: first, last: last))
        host.hostingController.view.layoutSubtreeIfNeeded()
        host.hostingController.view.nextKeyView = first
        first.nextKeyView = last
        last.nextKeyView = trigger
        trigger.nextKeyView = first
        host.isPresented = true
        XCTAssertTrue(content.isAccessibilityHidden())
        XCTAssertTrue(host.hostingController.view.isAccessibilityModal())
        XCTAssertTrue(window.firstResponder === first.currentEditor())
        window.makeFirstResponder(last)
        let tab = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48
        ))
        XCTAssertNil(host.handle(tab))
        XCTAssertTrue(window.firstResponder === first.currentEditor())
        let backTab = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.shift], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48
        ))
        XCTAssertNil(host.handle(backTab))
        XCTAssertTrue(window.firstResponder === last.currentEditor())
        host.isPresented = false
        XCTAssertFalse(content.isAccessibilityHidden())
        XCTAssertFalse(host.hostingController.view.isAccessibilityModal())
        XCTAssertTrue(window.firstResponder === trigger.currentEditor())
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
        XCTAssertEqual(SettingsSidePanelLayout.resolvedWidth(requested: 400, available: 0), 0)
        XCTAssertEqual(SettingsSidePanelLayout.resolvedWidth(requested: 400, available: -10), 0)
    }

    func testInstalledMonitorIsRemovedAndReattachmentInstallsOnlyOne() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        var handlers: [UUID: (NSEvent) -> NSEvent?] = [:]
        let host = SettingsWindowPanelHost(eventMonitoring: .init(
            install: { handler in
                let token = UUID()
                handlers[token] = handler
                return token
            },
            remove: { token in
                if let identifier = token as? UUID {
                    handlers.removeValue(forKey: identifier)
                }
            }
        ))
        defer { host.detach() }
        var dismissals = 0
        host.isPresented = true
        host.onEscape = { dismissals += 1 }
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        ))
        for _ in 0 ..< 3 {
            host.attach(to: window)
            XCTAssertEqual(handlers.count, 1)
            for handler in handlers.values {
                XCTAssertNil(handler(event))
            }
            host.detach()
            XCTAssertTrue(handlers.isEmpty)
        }
        XCTAssertEqual(dismissals, 3)
    }

    func testPublicBridgeUpdatesEnvironmentGeometryAndDismantles() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let probe = PanelProbe()
        var dismissals = 0
        let root = NSHostingView(rootView: AnyView(Color.clear))
        window.contentView = root
        defer { root.rootView = AnyView(Color.clear) }
        func update(presented: Bool, width: CGFloat, marker: String) {
            root.rootView = AnyView(
                Color.clear.windowSidePanel(isPresented: presented, width: width, onDismiss: { dismissals += 1 }, content: {
                    PanelMeasurement(probe: probe)
                })
                .environment(\.locale, Locale(identifier: marker))
                .transaction { $0.disablesAnimations = true }
            )
            root.layoutSubtreeIfNeeded()
        }
        update(presented: true, width: 320, marker: "en_US")
        let anchor = try XCTUnwrap(descendant(SettingsWindowPanelAnchor.self, in: root))
        let host = anchor.host
        defer { host.detach() }
        func settle(width: CGFloat, marker: String) {
            let ready = NSPredicate { _, _ in
                MainActor.assumeIsolated {
                    window.contentView?.superview?.layoutSubtreeIfNeeded()
                    return abs(probe.width - width) < 1 && probe.marker == marker
                }
            }
            expectation(for: ready, evaluatedWith: nil)
            waitForExpectations(timeout: 3)
        }
        settle(width: 320, marker: "en_US")
        XCTAssertTrue(host.isPresented)
        XCTAssertEqual(host.requestedWidth, 320)
        XCTAssertEqual(probe.width, 320, accuracy: 1)
        XCTAssertEqual(probe.height, host.bounds.height, accuracy: 1)
        func click(horizontal: CGFloat) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: .leftMouseDown, location: NSPoint(x: horizontal, y: 200),
                modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1
            ))
        }
        let boundary = host.bounds.maxX - probe.width
        XCTAssertNotNil(try host.handle(click(horizontal: boundary + 1)))
        XCTAssertNil(try host.handle(click(horizontal: boundary - 1)))
        XCTAssertEqual(dismissals, 1)
        update(presented: true, width: 1200, marker: "pt_BR")
        settle(width: 900, marker: "pt_BR")
        XCTAssertEqual(host.requestedWidth, 1200)
        window.setContentSize(NSSize(width: 620, height: 520))
        settle(width: 620, marker: "pt_BR")
        XCTAssertEqual(probe.height, host.bounds.height, accuracy: 1)
        window.setContentSize(NSSize(width: 900, height: 700))
        settle(width: 900, marker: "pt_BR")
        XCTAssertEqual(probe.width, host.bounds.width, accuracy: 1)
        XCTAssertNotNil(try host.handle(click(horizontal: 1)))
        XCTAssertEqual(dismissals, 1)
        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        ))
        NSApplication.shared.sendEvent(escape)
        XCTAssertEqual(dismissals, 2)
        update(presented: false, width: 200, marker: "hidden")
        XCTAssertFalse(host.isPresented)
        XCTAssertNil(host.hitTest(NSPoint(x: 10, y: 10)))
        root.rootView = AnyView(Color.clear)
        root.layoutSubtreeIfNeeded()
        let removed = NSPredicate { _, _ in MainActor.assumeIsolated { host.superview == nil } }
        expectation(for: removed, evaluatedWith: nil)
        waitForExpectations(timeout: 3)
        XCTAssertNil(host.superview)
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T {
            return match
        }
        return view.subviews.compactMap { descendant(type, in: $0) }.first
    }
}

@MainActor
private final class PanelProbe {
    var width: CGFloat = 0
    var height: CGFloat = 0
    var marker = ""
}

private struct PanelMeasurement: View {
    @Environment(\.locale) private var locale
    let probe: PanelProbe

    var body: some View {
        Color.clear
            .onGeometryChange(for: CGSize.self) { geometry in geometry.size } action: { size in
                probe.width = size.width
                probe.height = size.height
            }
            .onAppear { probe.marker = locale.identifier }
            .onChange(of: locale) { _, locale in probe.marker = locale.identifier }
    }
}

private struct PanelKeyViews: NSViewRepresentable {
    let first: NSTextField
    let last: NSTextField

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        view.addSubview(first)
        view.addSubview(last)
        first.frame = NSRect(x: 0, y: 0, width: 100, height: 24)
        last.frame = NSRect(x: 0, y: 30, width: 100, height: 24)
        return view
    }

    func updateNSView(_: NSView, context _: Context) {}
}
