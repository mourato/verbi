import Foundation
import MeetingAssistantCoreDomain

extension RecordingManager {
    func applyAutomaticCalendarEventIfAvailable(to meeting: Meeting) async -> Meeting {
        await calendarIntegrationService.applyAutomaticCalendarEventIfAvailable(to: meeting)
    }

    func linkCurrentMeeting(to event: MeetingCalendarEventSnapshot?) {
        guard var currentMeeting else { return }
        currentMeeting = meetingApplyingCalendarEvent(event, to: currentMeeting, clearTitleWhenRemoving: true)
        synchronizeMeetingNotesWithLinkedCalendarEventIfNeeded(linkedEventIdentifier: event?.eventIdentifier)
    }

    func meetingApplyingCalendarEvent(
        _ event: MeetingCalendarEventSnapshot?,
        to meeting: Meeting,
        clearTitleWhenRemoving: Bool
    ) -> Meeting {
        calendarIntegrationService.meetingApplyingCalendarEvent(
            event,
            to: meeting,
            clearTitleWhenRemoving: clearTitleWhenRemoving
        )
    }

    func calendarContextBlock(for event: MeetingCalendarEventSnapshot) -> String {
        calendarIntegrationService.calendarContextBlock(for: event)
    }
}
