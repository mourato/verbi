import Foundation
import MeetingAssistantCoreDomain

public struct WebMeetingTarget: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let app: MeetingApp
    public let displayName: String
    public let urlPatterns: [String]
    public let browserBundleIdentifiers: [String]

    public init(
        id: UUID = UUID(),
        app: MeetingApp,
        displayName: String,
        urlPatterns: [String],
        browserBundleIdentifiers: [String]
    ) {
        self.id = id
        self.app = app
        self.displayName = displayName
        self.urlPatterns = urlPatterns
        self.browserBundleIdentifiers = browserBundleIdentifiers
    }
}
