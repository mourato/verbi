import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreInfrastructure
@testable import MeetingAssistantCoreUI
import XCTest

/// Calls `openNotes` on the real notes pane, which presents a window. Runs only in `make test-appkit`.
/// `tearDown` dismisses the pane without flushing notes.
@MainActor
final class MeetingReminderActionHandlerTests: XCTestCase {
    private var now: Date!
    private var scheduler: MeetingReminderScheduler!
    private var notesController: MeetingNotesPaneController!
    private var handler: MeetingReminderActionHandler!
    private var firedEvents: [MeetingCalendarEventSnapshot] = []

    override func setUp() async throws {
        now = Date(timeIntervalSince1970: 1_700_000_000)
        firedEvents = []
        scheduler = MeetingReminderScheduler(now: { [unowned self] in now })
        scheduler.onMeetingStartFire = { [unowned self] event in
            firedEvents.append(event)
        }
        notesController = MeetingNotesPaneController()
        handler = MeetingReminderActionHandler(
            meetingNotesPaneController: notesController,
            overlayController: MeetingReminderOverlayController(),
            scheduler: scheduler,
            upcomingEventsProvider: { [] },
            persistDismissedOccurrence: { _ in }
        )
    }

    override func tearDown() async throws {
        notesController.dismiss(flushPendingSave: false)
    }

    func testOpenNotesFromOverlayReleasesAlertSoNextReminderFires() {
        let first = makeEvent(startOffset: 0, duration: 5 * 60)
        let second = makeEvent(startOffset: 6 * 60)
        let config = enabledConfiguration()

        scheduler.reschedule(events: [first], configuration: config, now: now)
        XCTAssertEqual(firedEvents, [first])

        handler.openNotes(for: first)

        now = second.startDate
        scheduler.reschedule(events: [second], configuration: config, now: now)

        XCTAssertEqual(firedEvents, [first, second])
    }

    private func makeEvent(startOffset: TimeInterval, duration: TimeInterval = 3_600) -> MeetingCalendarEventSnapshot {
        let start = now.addingTimeInterval(startOffset)
        return MeetingCalendarEventSnapshot(
            eventIdentifier: "event-\(Int(start.timeIntervalSince1970))",
            title: "Planning",
            startDate: start,
            endDate: start.addingTimeInterval(duration),
        )
    }

    private func enabledConfiguration() -> MeetingReminderScheduleConfiguration {
        MeetingReminderScheduleConfiguration(
            remindersEnabled: true,
            leadMinutes: 15,
            overlayLeadSeconds: 0,
            overlayEnabled: true,
        )
    }
}
