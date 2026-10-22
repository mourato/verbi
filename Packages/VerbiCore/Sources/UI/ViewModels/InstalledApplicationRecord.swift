import Foundation

public struct InstalledApplicationRecord: Identifiable, Hashable, Sendable {
    public let bundleIdentifier: String
    public let displayName: String

    public init(bundleIdentifier: String, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }

    public var id: String {
        bundleIdentifier
    }
}
