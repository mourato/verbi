import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public final class MeetingCalendarIntegrationService {
    private let calendarEventService: any CalendarEventServiceProtocol
    private let ignoredEventIdentifiers: () -> Set<String>

    public init(
        calendarEventService: any CalendarEventServiceProtocol,
        ignoredEventIdentifiers: @escaping () -> Set<String> = {
            AppSettingsStore.shared.ignoredCalendarEventIdentifiers()
        }
    ) {
        self.calendarEventService = calendarEventService
        self.ignoredEventIdentifiers = ignoredEventIdentifiers
    }

    public func applyAutomaticCalendarEventIfAvailable(to meeting: Meeting) -> Meeting {
        guard meeting.supportsMeetingConversation else {
            return meeting.sanitizedForPersistence()
        }

        guard calendarEventService.authorizationState().isAuthorized else {
            return meeting
        }

        do {
            let events = try calendarEventService.fetchUpcomingEvents(
                limit: 10,
                now: meeting.startTime,
                window: 24 * 60 * 60,
                ignoredEventIdentifiers: ignoredEventIdentifiers()
            )
            let selectedEvent = calendarEventService.bestMatchingEvent(at: meeting.startTime, in: events)
            return meetingApplyingCalendarEvent(selectedEvent, to: meeting, clearTitleWhenRemoving: false)
        } catch {
            AppLogger.error("Failed to fetch upcoming calendar events", category: .recordingManager, error: error)
            return meeting
        }
    }

    func refreshedLinkedEvent(for meeting: Meeting) -> MeetingCalendarEventSnapshot? {
        guard meeting.supportsMeetingConversation,
              let linkedEventIdentifier = meeting.linkedCalendarEvent?.eventIdentifier,
              calendarEventService.authorizationState().isAuthorized
        else { return nil }

        let searchRadius: TimeInterval = 24 * 60 * 60
        let searchStart = meeting.startTime.addingTimeInterval(-searchRadius)

        do {
            let matchingEvents = try calendarEventService.fetchUpcomingEvents(
                limit: Int.max,
                now: searchStart,
                window: searchRadius * 2,
                ignoredEventIdentifiers: []
            ).filter { $0.eventIdentifier == linkedEventIdentifier }

            if let overlappingEvent = matchingEvents.first(where: {
                $0.startDate <= meeting.startTime && $0.endDate >= meeting.startTime
            }) {
                return overlappingEvent
            }

            return matchingEvents.min {
                abs($0.startDate.timeIntervalSince(meeting.startTime))
                    < abs($1.startDate.timeIntervalSince(meeting.startTime))
            }
        } catch {
            AppLogger.error("Failed to refresh linked calendar event", category: .recordingManager, error: error)
            return nil
        }
    }

    public func meetingApplyingCalendarEvent(
        _ event: MeetingCalendarEventSnapshot?,
        to meeting: Meeting,
        clearTitleWhenRemoving: Bool
    ) -> Meeting {
        var updatedMeeting = meeting.sanitizedForPersistence()
        guard updatedMeeting.supportsMeetingConversation else { return updatedMeeting }

        updatedMeeting.linkedCalendarEvent = event

        if let event {
            let trimmedTitle = event.trimmedTitle
            updatedMeeting.title = trimmedTitle.isEmpty ? nil : trimmedTitle
        } else if clearTitleWhenRemoving {
            updatedMeeting.title = nil
        }

        return updatedMeeting
    }

    public func calendarContextBlock(for event: MeetingCalendarEventSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var lines = [
            "CONTEXT_CALENDAR_EVENT",
            "- Title: \(event.trimmedTitle.isEmpty ? "Untitled event" : event.trimmedTitle)",
            "- Start: \(formatter.string(from: event.startDate))",
            "- End: \(formatter.string(from: event.endDate))"
        ]

        if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            lines.append("- Location: \(location)")
        }

        if let notes = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            lines.append("- Description:")
            lines.append(notes)
        }

        if !event.attendees.isEmpty {
            lines.append("- Attendees: \(event.attendees.joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }
}
