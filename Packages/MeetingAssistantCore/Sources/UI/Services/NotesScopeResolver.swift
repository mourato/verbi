import Foundation
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public enum NotesScopeResolver {
    private enum Constants {
        static let imminentEventWindow: TimeInterval = 30 * 60
    }

    public struct Context {
        public let isRecordingMeeting: Bool
        public let currentMeetingID: UUID?
        public let lastEditedCalendarEventIdentifier: String?
        public let ignoredCalendarEventIdentifiers: Set<String>
        public let fetchUpcomingEvents: () throws -> [MeetingCalendarEventSnapshot]

        public init(
            isRecordingMeeting: Bool,
            currentMeetingID: UUID?,
            lastEditedCalendarEventIdentifier: String?,
            ignoredCalendarEventIdentifiers: Set<String>,
            fetchUpcomingEvents: @escaping () throws -> [MeetingCalendarEventSnapshot]
        ) {
            self.isRecordingMeeting = isRecordingMeeting
            self.currentMeetingID = currentMeetingID
            self.lastEditedCalendarEventIdentifier = lastEditedCalendarEventIdentifier
            self.ignoredCalendarEventIdentifiers = ignoredCalendarEventIdentifiers
            self.fetchUpcomingEvents = fetchUpcomingEvents
        }
    }

    /// Resolves which note scope to open when the pane is summoned without an explicit scope.
    public static func resolve(context: Context, now: Date = Date()) -> NotesScope? {
        if context.isRecordingMeeting, let meetingID = context.currentMeetingID {
            return .meetingSession(meetingID: meetingID)
        }

        if let event = imminentCalendarEvent(in: context, now: now) {
            return .calendarEvent(eventIdentifier: event.eventIdentifier)
        }

        if let lastEdited = normalizedEventIdentifier(context.lastEditedCalendarEventIdentifier) {
            return .calendarEvent(eventIdentifier: lastEdited)
        }

        return nil
    }

    private static func imminentCalendarEvent(
        in context: Context,
        now: Date
    ) -> MeetingCalendarEventSnapshot? {
        guard let events = try? context.fetchUpcomingEvents() else { return nil }

        return events.first { event in
            guard !context.ignoredCalendarEventIdentifiers.contains(event.eventIdentifier) else {
                return false
            }

            if event.startDate <= now, event.endDate >= now {
                return true
            }

            let lead = event.startDate.timeIntervalSince(now)
            return lead > 0 && lead <= Constants.imminentEventWindow
        }
    }

    private static func normalizedEventIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let normalized = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
