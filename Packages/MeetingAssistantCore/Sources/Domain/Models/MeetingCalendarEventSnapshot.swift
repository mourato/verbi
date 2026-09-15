import Foundation

/// Snapshot of a calendar event linked to a meeting recording.
public struct MeetingCalendarEventSnapshot: Codable, Hashable, Sendable {
    public let eventIdentifier: String
    public let title: String
    public let startDate: Date
    public let endDate: Date
    public let location: String?
    public let notes: String?
    public let attendees: [String]

    public init(
        eventIdentifier: String,
        title: String,
        startDate: Date,
        endDate: Date,
        location: String? = nil,
        notes: String? = nil,
        attendees: [String] = []
    ) {
        self.eventIdentifier = eventIdentifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.attendees = attendees
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
