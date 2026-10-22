import Combine
import Foundation
@testable import VerbiCore
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class MeetingReminderCoordinatorTests: XCTestCase {
    func testOffNotifyOffRestartsSingleSafetyNetPollAndSchedulesAgain() throws {
        try AppSettingsTestIsolationLock.acquire()
        defer { AppSettingsTestIsolationLock.release() }
        let settings = AppSettingsStore.shared
        let originalMode = settings.meetingDetectionMode
        let originalLead = settings.meetingReminderLeadMinutes
        defer {
            settings.meetingDetectionMode = originalMode
            settings.meetingReminderLeadMinutes = originalLead
        }
        settings.meetingDetectionMode = .off
        settings.meetingReminderLeadMinutes = 5
        let calendar = MockCalendarEventService()
        calendar.eventsToReturn = [makeEvent(startDate: Date().addingTimeInterval(20 * 60), title: "Meeting")]
        let scheduler = MeetingReminderScheduler()
        let coordinator = MeetingReminderCoordinator(calendarEventService: calendar, scheduler: scheduler)
        coordinator.attach()
        defer { coordinator.detach() }
        var scheduled = 0
        scheduler.onScheduleLeadNotification = { _, _ in scheduled += 1 }
        XCTAssertFalse(coordinator.isPolling)

        settings.meetingDetectionMode = .notify
        XCTAssertTrue(coordinator.isPolling)
        XCTAssertNil(scheduler.onWatchdogTick)
        XCTAssertEqual(scheduled, 1)

        settings.meetingDetectionMode = .off
        XCTAssertFalse(coordinator.isPolling)
        XCTAssertEqual(scheduled, 1)
        let fetchCountWhileOff = calendar.fetchCount
        calendar.eventStoreChangesSubject.send()
        XCTAssertEqual(calendar.fetchCount, fetchCountWhileOff)
        settings.meetingDetectionMode = .notify
        XCTAssertTrue(coordinator.isPolling)
        XCTAssertNil(scheduler.onWatchdogTick)
        XCTAssertEqual(scheduled, 2)
    }

    func testEventStoreChangesRefreshScheduleAfterDebounce() async throws {
        try AppSettingsTestIsolationLock.acquire()
        defer { AppSettingsTestIsolationLock.release() }
        let settings = AppSettingsStore.shared
        let originalMode = settings.meetingDetectionMode
        let originalLead = settings.meetingReminderLeadMinutes
        defer {
            settings.meetingDetectionMode = originalMode
            settings.meetingReminderLeadMinutes = originalLead
        }
        settings.meetingDetectionMode = .notify
        settings.meetingReminderLeadMinutes = 5

        let calendar = MockCalendarEventService()
        let startDate = Date().addingTimeInterval(20 * 60)
        let initialEvent = makeEvent(startDate: startDate, title: "Planning")
        let updatedEvent = makeEvent(startDate: startDate, title: "Updated planning")
        calendar.eventsToReturn = [initialEvent]

        let scheduler = MeetingReminderScheduler()
        let coordinator = MeetingReminderCoordinator(calendarEventService: calendar, scheduler: scheduler)
        coordinator.attach()
        defer { coordinator.detach() }

        var scheduledEvents: [MeetingCalendarEventSnapshot] = []
        scheduler.onScheduleLeadNotification = { event, _ in scheduledEvents.append(event) }
        let initialFetchCount = calendar.fetchCount
        let refreshCompleted = expectation(description: "calendar change refreshes reminder schedule")
        calendar.onFetch = {
            if calendar.fetchCount > initialFetchCount {
                refreshCompleted.fulfill()
            }
        }
        calendar.eventsToReturn = [updatedEvent]

        calendar.eventStoreChangesSubject.send()
        await fulfillment(of: [refreshCompleted], timeout: 2)

        XCTAssertEqual(calendar.fetchCount, initialFetchCount + 1)
        XCTAssertEqual(scheduledEvents, [updatedEvent])
    }

    func testWakeRefreshesCalendarSourcesBeforeSchedule() throws {
        try AppSettingsTestIsolationLock.acquire()
        defer { AppSettingsTestIsolationLock.release() }
        let settings = AppSettingsStore.shared
        let originalMode = settings.meetingDetectionMode
        defer { settings.meetingDetectionMode = originalMode }
        settings.meetingDetectionMode = .notify

        let calendar = MockCalendarEventService()
        let scheduler = MeetingReminderScheduler()
        let coordinator = MeetingReminderCoordinator(calendarEventService: calendar, scheduler: scheduler)
        coordinator.attach()
        defer { coordinator.detach() }

        calendar.clearOperations()
        let fetchCountBeforeWake = calendar.fetchCount
        scheduler.onWake?()

        XCTAssertEqual(calendar.operations, ["refreshSources", "fetch"])
        XCTAssertEqual(calendar.fetchCount, fetchCountBeforeWake + 1)
    }

    private func makeEvent(startDate: Date, title: String) -> MeetingCalendarEventSnapshot {
        MeetingCalendarEventSnapshot(
            eventIdentifier: "detection-transition",
            title: title,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1200)
        )
    }
}
