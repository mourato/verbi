import Combine
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

@MainActor
public final class MeetingReminderCoordinator {
    public static let shared = MeetingReminderCoordinator()

    private let calendarEventService: any CalendarEventServiceProtocol
    private let settingsStore: AppSettingsStore
    private let notificationService: NotificationService
    public let scheduler: MeetingReminderScheduler
    public let overlayController: MeetingReminderOverlayController
    private var meetingNotesPaneController: MeetingNotesPaneController
    public private(set) var actionHandler: MeetingReminderActionHandler?

    private var pollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var attached = false
    private var cachedEvents: [MeetingCalendarEventSnapshot] = []

    public init(
        calendarEventService: any CalendarEventServiceProtocol = CalendarEventService.shared,
        settingsStore: AppSettingsStore = .shared,
        notificationService: NotificationService = .shared,
        scheduler: MeetingReminderScheduler? = nil,
        overlayController: MeetingReminderOverlayController? = nil,
        meetingNotesPaneController: MeetingNotesPaneController? = nil
    ) {
        self.calendarEventService = calendarEventService
        self.settingsStore = settingsStore
        self.notificationService = notificationService
        self.scheduler = scheduler ?? MeetingReminderScheduler(
            dismissedOccurrenceKeys: settingsStore.meetingReminderDismissedOccurrenceKeys()
        )
        self.overlayController = overlayController ?? MeetingReminderOverlayController()
        self.meetingNotesPaneController = meetingNotesPaneController ?? MeetingNotesPaneController()
    }

    public func attach(meetingNotesPaneController: MeetingNotesPaneController? = nil) {
        guard !attached else { return }
        attached = true

        if let meetingNotesPaneController {
            self.meetingNotesPaneController = meetingNotesPaneController
        }

        actionHandler = MeetingReminderActionHandler(
            meetingNotesPaneController: self.meetingNotesPaneController,
            overlayController: overlayController,
            scheduler: scheduler,
            upcomingEventsProvider: { [weak self] in
                self?.cachedEvents ?? []
            },
            persistDismissedOccurrence: { [weak self] event in
                self?.settingsStore.dismissMeetingReminderOccurrence(for: event)
            }
        )

        scheduler.onScheduleLeadNotification = { [weak self] event, fireDate in
            self?.scheduleLeadNotification(for: event, at: fireDate)
        }
        scheduler.onMeetingStartFire = { [weak self] event in
            self?.presentOverlay(for: event)
        }
        scheduler.onCancelLeadNotification = { [weak self] event in
            let key = AppSettingsStore.meetingReminderOccurrenceKey(for: event)
            self?.notificationService.cancelMeetingLeadNotification(occurrenceKey: key)
        }
        scheduler.onWatchdogTick = { [weak self] in
            self?.refreshSchedule()
        }

        notificationService.registerMeetingReminderCategories()

        settingsStore.$meetingRemindersEnabled
            .sink { [weak self] enabled in
                guard let self else { return }
                if enabled {
                    notificationService.requestAuthorization()
                }
                startPollingIfNeeded()
            }
            .store(in: &cancellables)

        settingsStore.$meetingReminderLeadMinutes
            .combineLatest(
                settingsStore.$meetingReminderOverlayLeadSeconds,
                settingsStore.$meetingReminderOverlayEnabled
            )
            .sink { [weak self] _, _, _ in
                self?.refreshSchedule(forceCacheBust: true)
            }
            .store(in: &cancellables)

        startPollingIfNeeded()
    }

    public func detach() {
        attached = false
        pollTimer?.invalidate()
        pollTimer = nil
        scheduler.stopReliabilityGuards()
        scheduler.cancelAllScheduling()
        overlayController.hide()
        cancellables.removeAll()
    }

    private func startPollingIfNeeded() {
        pollTimer?.invalidate()
        guard settingsStore.meetingRemindersEnabled else {
            scheduler.stopReliabilityGuards()
            scheduler.cancelAllScheduling()
            return
        }

        scheduler.startReliabilityGuards()
        refreshSchedule()

        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshSchedule()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func refreshSchedule(forceCacheBust: Bool = false) {
        guard settingsStore.meetingRemindersEnabled else {
            scheduler.cancelAllScheduling()
            return
        }

        guard calendarEventService.authorizationState().isAuthorized else {
            scheduler.cancelAllScheduling()
            return
        }

        do {
            cachedEvents = try calendarEventService.fetchUpcomingEvents(
                limit: 20,
                now: Date(),
                window: 24 * 60 * 60,
                ignoredEventIdentifiers: settingsStore.ignoredCalendarEventIdentifiers()
            )
            if forceCacheBust {
                scheduler.cancelAllScheduling()
            }
            scheduler.reschedule(events: cachedEvents, configuration: currentConfiguration())
        } catch {
            AppLogger.error("Failed to refresh meeting reminders", category: .recordingManager, error: error)
        }
    }

    private func presentOverlay(for event: MeetingCalendarEventSnapshot) {
        guard settingsStore.meetingReminderOverlayEnabled,
              let actionHandler
        else { return }

        overlayController.show(
            event: event,
            prefersRecordPrimary: settingsStore.isMeetingTranscriptionEnabled,
            mirrorOnAllScreens: settingsStore.meetingReminderMirrorAllScreens,
            playAlertSound: settingsStore.meetingReminderAlertSoundEnabled,
            actionHandler: actionHandler
        )
    }

    private func scheduleLeadNotification(for event: MeetingCalendarEventSnapshot, at fireDate: Date) {
        guard settingsStore.meetingReminderLeadMinutes > 0 else { return }

        let occurrenceKey = AppSettingsStore.meetingReminderOccurrenceKey(for: event)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        let startTime = formatter.string(from: event.startDate)
        let title = event.trimmedTitle.isEmpty ? "meeting_reminder.notification.lead.title".localized : event.trimmedTitle
        let body = "meeting_reminder.notification.lead.body".localized(with: title, startTime)

        notificationService.scheduleMeetingLeadNotification(
            occurrenceKey: occurrenceKey,
            at: fireDate,
            title: "meeting_reminder.notification.lead.title".localized,
            body: body,
            joinURL: event.joinURL
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
