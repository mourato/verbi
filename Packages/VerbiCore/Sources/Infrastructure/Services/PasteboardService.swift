import AppKit
import Foundation

/// Protocol abstraction for system pasteboard operations.
@MainActor
public protocol PasteboardServiceProtocol {
    func clearContents()
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType)
}

/// Concrete implementation using NSPasteboard.general.
@MainActor
public final class PasteboardService: PasteboardServiceProtocol {
    public static let shared = PasteboardService()
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public func clearContents() {
        pasteboard.clearContents()
    }

    public func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) {
        pasteboard.setString(string, forType: dataType)
    }
}
