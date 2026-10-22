import Foundation
import MeetingAssistantCoreDomain

extension RecordingManager {
    func applyAutomaticCalendarEventIfAvailable(to meeting: CaptureSession) async -> CaptureSession {
        await calendarIntegrationService.applyAutomaticCalendarEventIfAvailable(to: meeting)
    }

    func linkCurrentMeeting(to event: MeetingCalendarEventSnapshot?) {
        guard var currentMeeting else { return }
        currentMeeting = meetingApplyingCalendarEvent(event, to: currentMeeting, clearTitleWhenRemoving: true)
        synchronizeMeetingNotesWithLinkedCalendarEventIfNeeded(linkedEventIdentifier: event?.eventIdentifier)
    }

    func refreshLinkedCalendarEventIfNeeded() {
        guard let meeting = currentMeeting else { return }
        let updatedMeeting = calendarIntegrationService.refreshingLinkedEvent(in: meeting)
        guard updatedMeeting.linkedCalendarEvent != meeting.linkedCalendarEvent else { return }
        currentMeeting = updatedMeeting
    }

    func meetingApplyingCalendarEvent(
        _ event: MeetingCalendarEventSnapshot?,
        to meeting: CaptureSession,
        clearTitleWhenRemoving: Bool
    ) -> CaptureSession {
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
