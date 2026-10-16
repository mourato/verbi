import AppKit
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

    func testMovedStartCancelsOldLeadNotification() {
        let original = makeEvent(startOffset: 30 * 60, eventIdentifier: "moved-event")
        let moved = makeEvent(startOffset: 45 * 60, eventIdentifier: "moved-event")
        var cancelledEvents: [MeetingCalendarEventSnapshot] = []
        scheduler.onCancelLeadNotification = { event in
            cancelledEvents.append(event)
        }
        let config = enabledConfiguration()

        scheduler.reschedule(events: [original], configuration: config, now: now)
        cancelledEvents.removeAll()
        scheduler.reschedule(events: [moved], configuration: config, now: now)

        XCTAssertEqual(cancelledEvents.filter { $0 == original }, [original])
        XCTAssertEqual(scheduledLeadDates.last?.0, moved)
    }

    func testDeletedEventCancelsNotificationAndInvalidatesActiveAlert() {
        let event = makeEvent(startOffset: 20 * 60)
        let config = enabledConfiguration(overlayLeadSeconds: 10 * 60)
        var cancelledEvents: [MeetingCalendarEventSnapshot] = []
        var invalidationCount = 0
        scheduler.onCancelLeadNotification = { event in
            cancelledEvents.append(event)
        }
        scheduler.onActiveAlertInvalidated = { [unowned self] in
            XCTAssertNil(scheduler.activeAlert)
            invalidationCount += 1
        }

        scheduler.reschedule(events: [event], configuration: config, now: now)
        cancelledEvents.removeAll()
        now = event.startDate.addingTimeInterval(-5 * 60)
        scheduler.reschedule(events: [event], configuration: config, now: now)
        XCTAssertEqual(scheduler.activeAlert, event)

        scheduler.reschedule(events: [], configuration: config, now: now)

        XCTAssertEqual(cancelledEvents, [event])
        XCTAssertNil(scheduler.activeAlert)
        XCTAssertEqual(invalidationCount, 1)
    }

    func testUpdatedSnapshotReschedulesLeadNotification() {
        let original = makeEvent(startOffset: 30 * 60, eventIdentifier: "edited-event")
        let edited = makeEvent(startOffset: 30 * 60, eventIdentifier: "edited-event", title: "Updated planning")
        let config = enabledConfiguration()

        scheduler.reschedule(events: [original], configuration: config, now: now)
        scheduledLeadDates.removeAll()
        scheduler.reschedule(events: [edited], configuration: config, now: now)

        XCTAssertEqual(scheduledLeadDates.map(\.0), [edited])
        XCTAssertEqual(scheduledLeadDates.first?.1, edited.startDate.addingTimeInterval(-15 * 60))
    }

    func testWakeInvokesCallback() {
        var wakeCount = 0
        scheduler.onWake = {
            wakeCount += 1
        }
        scheduler.startReliabilityGuards()
        defer { scheduler.stopReliabilityGuards() }

        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)

        XCTAssertEqual(wakeCount, 1)
    }

    func testSnoozeMigratesToMovedOccurrenceWhileStillFuture() {
        let original = makeEvent(startOffset: 30 * 60, eventIdentifier: "snoozed-event")
        let moved = makeEvent(startOffset: 40 * 60, eventIdentifier: "snoozed-event")
        let config = enabledConfiguration(leadMinutes: 0, overlayLeadSeconds: 60)
        scheduler.snooze(original, minutes: 5, allEvents: [original], configuration: config)
        let snoozeFireDate = now.addingTimeInterval(5 * 60)

        now = snoozeFireDate.addingTimeInterval(-30)
        scheduler.reschedule(events: [moved], configuration: config, now: now)

        XCTAssertEqual(firedEvents, [moved])
    }

    func testExpiredSnoozeDoesNotMigrateToMovedOccurrence() {
        let original = makeEvent(startOffset: 30 * 60, eventIdentifier: "expired-snooze-event")
        let moved = makeEvent(startOffset: 40 * 60, eventIdentifier: "expired-snooze-event")
        let config = enabledConfiguration(leadMinutes: 0, overlayLeadSeconds: 60)
        scheduler.snooze(original, minutes: 5, allEvents: [original], configuration: config)
        let snoozeFireDate = now.addingTimeInterval(5 * 60)

        now = snoozeFireDate.addingTimeInterval(30)
        scheduler.reschedule(events: [moved], configuration: config, now: now)

        XCTAssertTrue(firedEvents.isEmpty)
    }

    func testDismissalDoesNotMigrateToMovedOccurrence() {
        let original = makeEvent(startOffset: 30 * 60, eventIdentifier: "dismissed-event")
        let moved = makeEvent(startOffset: 40 * 60, eventIdentifier: "dismissed-event")
        let config = enabledConfiguration()
        scheduler.reschedule(events: [original], configuration: config, now: now)
        scheduler.dismiss(original)

        now = moved.startDate
        scheduler.reschedule(events: [moved], configuration: config, now: now)

        XCTAssertFalse(scheduler.dismissedOccurrenceKeys.contains(MeetingReminderOccurrenceKey.make(for: moved)))
        XCTAssertEqual(firedEvents, [moved])
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
            "meeting-reminder-lead-\(key)"
        )
    }

    private func makeEvent(
        startOffset: TimeInterval,
        duration: TimeInterval = 3600,
        eventIdentifier: String? = nil,
        title: String = "Planning"
    ) -> MeetingCalendarEventSnapshot {
        let start = now.addingTimeInterval(startOffset)
        return MeetingCalendarEventSnapshot(
            eventIdentifier: eventIdentifier ?? "event-\(Int(start.timeIntervalSince1970))",
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(duration),
            location: "https://meet.google.com/abc-defg-hij"
        )
    }

    private func enabledConfiguration(leadMinutes: Int = 15, overlayLeadSeconds: Int = 0) -> MeetingReminderScheduleConfiguration {
        MeetingReminderScheduleConfiguration(
            remindersEnabled: true,
            leadMinutes: leadMinutes,
            overlayLeadSeconds: overlayLeadSeconds,
            overlayEnabled: true
        )
    }

    private func disabledConfiguration() -> MeetingReminderScheduleConfiguration {
        MeetingReminderScheduleConfiguration(
            remindersEnabled: false,
            leadMinutes: 15,
            overlayLeadSeconds: 0,
            overlayEnabled: true
        )
    }
}
