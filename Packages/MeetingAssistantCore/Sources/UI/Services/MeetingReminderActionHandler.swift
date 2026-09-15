import AppKit
import Combine
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public protocol MeetingReminderActionHandling: AnyObject {
    func joinMeeting(for event: MeetingCalendarEventSnapshot)
    func recordMeeting(for event: MeetingCalendarEventSnapshot) async
    func openNotes(for event: MeetingCalendarEventSnapshot)
    func dismissReminder(for event: MeetingCalendarEventSnapshot)
    func snoozeReminder(for event: MeetingCalendarEventSnapshot, minutes: Int)
    func snoozeReminderUntilEnd(for event: MeetingCalendarEventSnapshot)
}

@MainActor
public final class MeetingReminderActionHandler: MeetingReminderActionHandling {
    private let recordingManager: RecordingManager
    private let settingsStore: AppSettingsStore
    private let meetingNotesPaneController: MeetingNotesPaneController
    private let overlayController: MeetingReminderOverlayController
    private let scheduler: MeetingReminderScheduler
    private let upcomingEventsProvider: () -> [MeetingCalendarEventSnapshot]
    private let persistDismissedOccurrence: (MeetingCalendarEventSnapshot) -> Void

    public init(
        recordingManager: RecordingManager = .shared,
        settingsStore: AppSettingsStore = .shared,
        meetingNotesPaneController: MeetingNotesPaneController,
        overlayController: MeetingReminderOverlayController,
        scheduler: MeetingReminderScheduler,
        upcomingEventsProvider: @escaping () -> [MeetingCalendarEventSnapshot],
        persistDismissedOccurrence: @escaping (MeetingCalendarEventSnapshot) -> Void
    ) {
        self.recordingManager = recordingManager
        self.settingsStore = settingsStore
        self.meetingNotesPaneController = meetingNotesPaneController
        self.overlayController = overlayController
        self.scheduler = scheduler
        self.upcomingEventsProvider = upcomingEventsProvider
        self.persistDismissedOccurrence = persistDismissedOccurrence
    }

    public func joinMeeting(for event: MeetingCalendarEventSnapshot) {
        guard let url = event.joinURL else { return }
        NSWorkspace.shared.open(url)
        dismissReminder(for: event)
    }

    public func recordMeeting(for event: MeetingCalendarEventSnapshot) async {
        if !recordingManager.isRecording, !recordingManager.isStartingRecording {
            await recordingManager.startCapture(purpose: .meeting)
        }
        recordingManager.linkCurrentMeeting(to: event)
        dismissReminder(for: event)
    }

    public func openNotes(for event: MeetingCalendarEventSnapshot) {
        meetingNotesPaneController.summon(scope: .calendarEvent(eventIdentifier: event.eventIdentifier))
        overlayController.hide()
    }

    public func dismissReminder(for event: MeetingCalendarEventSnapshot) {
        scheduler.dismiss(event)
        persistDismissedOccurrence(event)
        overlayController.hide()
        scheduler.overlayDidHide(
            allEvents: upcomingEventsProvider(),
            configuration: currentConfiguration()
        )
    }

    public func snoozeReminder(for event: MeetingCalendarEventSnapshot, minutes: Int) {
        overlayController.hide()
        scheduler.snooze(
            event,
            minutes: minutes,
            allEvents: upcomingEventsProvider(),
            configuration: currentConfiguration()
        )
    }

    public func snoozeReminderUntilEnd(for event: MeetingCalendarEventSnapshot) {
        overlayController.hide()
        scheduler.snoozeUntilEnd(
            event,
            allEvents: upcomingEventsProvider(),
            configuration: currentConfiguration()
        )
    }

    private func currentConfiguration() -> MeetingReminderScheduleConfiguration {
        MeetingReminderScheduleConfiguration(
            remindersEnabled: settingsStore.meetingRemindersEnabled,
            leadMinutes: settingsStore.meetingReminderLeadMinutes,
            overlayLeadSeconds: settingsStore.meetingReminderOverlayLeadSeconds,
            overlayEnabled: settingsStore.meetingReminderOverlayEnabled
        )
    }
}
