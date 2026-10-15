import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreInfrastructure
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class MeetingReminderCoordinatorTests: XCTestCase {
    func testOffNotifyOffRestartsPollingAndSchedulesThenCancels() throws {
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
        let calendar = DetectionCalendarService()
        let scheduler = MeetingReminderScheduler()
        let coordinator = MeetingReminderCoordinator(calendarEventService: calendar, scheduler: scheduler)
        coordinator.attach()
        defer { coordinator.detach() }
        var scheduled = 0
        var cancelled = 0
        scheduler.onScheduleLeadNotification = { _, _ in scheduled += 1 }
        scheduler.onCancelLeadNotification = { _ in cancelled += 1 }
        XCTAssertFalse(coordinator.isPolling)

        settings.meetingDetectionMode = .notify
        XCTAssertTrue(coordinator.isPolling)
        XCTAssertEqual(scheduled, 1)

        settings.meetingDetectionMode = .off
        XCTAssertFalse(coordinator.isPolling)
        XCTAssertEqual(cancelled, 1)
        settings.meetingDetectionMode = .notify
        XCTAssertTrue(coordinator.isPolling)
        XCTAssertEqual(scheduled, 2)
    }
}

private struct DetectionCalendarService: CalendarEventServiceProtocol {
    func authorizationState() -> PermissionState {
        .granted
    }

    func requestAccess() async -> PermissionState {
        await Task.yield()
        return .granted
    }

    func openSystemSettings() {}

    func fetchUpcomingEvents(
        limit _: Int,
        now: Date,
        window _: TimeInterval,
        ignoredEventIdentifiers _: Set<String>
    ) throws -> [MeetingCalendarEventSnapshot] {
        [MeetingCalendarEventSnapshot(
            eventIdentifier: "detection-transition",
            title: "Meeting",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(1200)
        )]
    }

    func bestMatchingEvent(at _: Date, in events: [MeetingCalendarEventSnapshot]) -> MeetingCalendarEventSnapshot? {
        events.first
    }
}
