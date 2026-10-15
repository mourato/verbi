import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreInfrastructure
import XCTest

@MainActor
final class MeetingReminderSchedulerTests: XCTestCase {
    private var now: Date!
    private var scheduler: MeetingReminderScheduler!
    private var firedEvents: [MeetingCalendarEventSnapshot] = []
    private var scheduledLeadDates: [(MeetingCalendarEventSnapshot, Date)] = []

    override func setUp() async throws {
        now = Date(timeIntervalSince1970: 1_700_000_000)
        firedEvents = []
        scheduledLeadDates = []
        scheduler = MeetingReminderScheduler(now: { [unowned self] in now })
        scheduler.onMeetingStartFire = { [unowned self] event in
            firedEvents.append(event)
        }
        scheduler.onScheduleLeadNotification = { [unowned self] event, date in
            scheduledLeadDates.append((event, date))
        }
    }

    func testSchedulesLeadNotificationAtConfiguredOffset() {
        let event = makeEvent(startOffset: 20 * 60)
        let config = enabledConfiguration(leadMinutes: 15)

        scheduler.reschedule(events: [event], configuration: config, now: now)

        XCTAssertEqual(scheduledLeadDates.count, 1)
        XCTAssertEqual(scheduledLeadDates[0].1, event.startDate.addingTimeInterval(-15 * 60))
    }

    func testDismissSuppressesFutureFires() {
        let event = makeEvent(startOffset: 5 * 60)
        let config = enabledConfiguration()

        scheduler.reschedule(events: [event], configuration: config, now: now)
        scheduler.dismiss(event)

        now = event.startDate
        scheduler.reschedule(events: [event], configuration: config, now: now)

        XCTAssertTrue(firedEvents.isEmpty)
        XCTAssertTrue(scheduler.dismissedOccurrenceKeys.contains(AppSettingsStore.meetingReminderOccurrenceKey(for: event)))
    }

    func testSnoozeReschedulesEffectiveStart() {
        let event = makeEvent(startOffset: 2 * 60)
        let config = enabledConfiguration()

        scheduler.reschedule(events: [event], configuration: config, now: now)
        scheduler.snooze(event, minutes: 5, allEvents: [event], configuration: config)

        let snoozeFireDate = now.addingTimeInterval(5 * 60)
        now = snoozeFireDate.addingTimeInterval(-30)
        scheduler.reschedule(events: [event], configuration: config, now: now)
        XCTAssertTrue(firedEvents.isEmpty)

        now = snoozeFireDate.addingTimeInterval(5)
        scheduler.reschedule(events: [event], configuration: config, now: now)
        XCTAssertEqual(firedEvents.count, 1)
    }

    func testSnoozeActiveAlertDrainsPendingAlert() {
        let first = makeEvent(startOffset: 0)
        let second = makeEvent(startOffset: -60)
        let config = enabledConfiguration()

        scheduler.reschedule(events: [first, second], configuration: config, now: now)
        XCTAssertEqual(firedEvents, [first])

        scheduler.snooze(first, minutes: 5, allEvents: [first, second], configuration: config)
        XCTAssertEqual(firedEvents, [first, second])
    }

    func testMissedFireCatchUpWithinGraceWindow() {
        let event = makeEvent(startOffset: -2 * 60, duration: 30 * 60)
        let config = enabledConfiguration()

        scheduler.reschedule(events: [event], configuration: config, now: now)

        XCTAssertEqual(firedEvents.count, 1)
    }

    func testDisabledConfigurationCancelsScheduling() {
        let event = makeEvent(startOffset: 20 * 60)
        scheduler.reschedule(events: [event], configuration: enabledConfiguration(), now: now)
        XCTAssertFalse(scheduledLeadDates.isEmpty)

        scheduledLeadDates.removeAll()
        firedEvents.removeAll()
        scheduler.reschedule(events: [event], configuration: disabledConfiguration(), now: now)
        XCTAssertTrue(scheduledLeadDates.isEmpty)
        XCTAssertTrue(firedEvents.isEmpty)
        XCTAssertNil(scheduler.activeAlert)
    }

    func testNotificationIdentifierNamespacing() {
        let event = makeEvent(startOffset: 600)
        let key = AppSettingsStore.meetingReminderOccurrenceKey(for: event)
        XCTAssertEqual(
            NotificationService.meetingLeadNotificationIdentifier(for: key),
            "meeting-reminder-lead-\(key)",
        )
    }

    private func makeEvent(startOffset: TimeInterval, duration: TimeInterval = 3_600) -> MeetingCalendarEventSnapshot {
        let start = now.addingTimeInterval(startOffset)
        return MeetingCalendarEventSnapshot(
            eventIdentifier: "event-\(Int(start.timeIntervalSince1970))",
            title: "Planning",
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            location: "https://meet.google.com/abc-defg-hij",
        )
    }

    private func enabledConfiguration(leadMinutes: Int = 15) -> MeetingReminderScheduleConfiguration {
        MeetingReminderScheduleConfiguration(
            remindersEnabled: true,
            leadMinutes: leadMinutes,
            overlayLeadSeconds: 0,
            overlayEnabled: true,
        )
    }

    private func disabledConfiguration() -> MeetingReminderScheduleConfiguration {
        MeetingReminderScheduleConfiguration(
            remindersEnabled: false,
            leadMinutes: 15,
            overlayLeadSeconds: 0,
            overlayEnabled: true,
        )
    }
}
