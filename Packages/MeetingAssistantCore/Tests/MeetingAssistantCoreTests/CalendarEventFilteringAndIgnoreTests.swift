import Combine
import EventKit
import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreInfrastructure
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class CalendarEventFilteringAndIgnoreTests: XCTestCase {
    private var settings: AppSettingsStore!
    private var originalIgnoredIdentifiers: Set<String> = []

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        settings = AppSettingsStore.shared
        originalIgnoredIdentifiers = settings.ignoredCalendarEventIdentifiers()
    }

    override func tearDown() async throws {
        restoreIgnoredIdentifiers()
        settings = nil
        AppSettingsTestIsolationLock.release()
        try await super.tearDown()
    }

    func testUpcomingEventEligibilityFiltersSoloEventsWithoutCallLinks() {
        XCTAssertFalse(
            CalendarEventService.isEligibleUpcomingEvent(
                attendeeCount: 1,
                searchableValues: [],
            ),
        )

        XCTAssertTrue(
            CalendarEventService.isEligibleUpcomingEvent(
                attendeeCount: 1,
                searchableValues: ["https://meet.google.com/abc-defg-hij"],
            ),
        )

        XCTAssertTrue(
            CalendarEventService.isEligibleUpcomingEvent(
                attendeeCount: 3,
                searchableValues: [],
            ),
        )
    }

    func testActiveForCurrentUserDropsCanceledAndDeclinedEvents() {
        XCTAssertTrue(CalendarEventService.isActiveForCurrentUser(isCanceled: false, currentUserDeclined: false))
        XCTAssertFalse(CalendarEventService.isActiveForCurrentUser(isCanceled: true, currentUserDeclined: false))
        XCTAssertFalse(CalendarEventService.isActiveForCurrentUser(isCanceled: false, currentUserDeclined: true))
        XCTAssertFalse(CalendarEventService.isActiveForCurrentUser(isCanceled: true, currentUserDeclined: true))
    }

    func testEventStoreChangesPublishOnMainWhenOwnEventStoreChanges() {
        let eventStore = EKEventStore()
        let service = CalendarEventService(eventStore: eventStore)
        let changed = expectation(description: "event store change published")

        let cancellable = service.eventStoreChanges.sink { _ in
            XCTAssertTrue(Thread.isMainThread)
            changed.fulfill()
        }

        NotificationCenter.default.post(name: .EKEventStoreChanged, object: eventStore)

        wait(for: [changed], timeout: 1)
        cancellable.cancel()
    }

    func testIgnoredEventIdentifiersPersistAndRoundTrip() {
        let eventA = "event-a-\(UUID().uuidString)"
        let eventB = "event-b-\(UUID().uuidString)"
        settings.ignoreCalendarEventIdentifier(eventA)
        settings.ignoreCalendarEventIdentifier(eventB)

        var ignored = settings.ignoredCalendarEventIdentifiers()
        XCTAssertTrue(ignored.contains(eventA))
        XCTAssertTrue(ignored.contains(eventB))

        settings.unignoreCalendarEventIdentifier(eventA)

        ignored = settings.ignoredCalendarEventIdentifiers()
        XCTAssertFalse(ignored.contains(eventA))
        XCTAssertTrue(ignored.contains(eventB))
    }

    func testDashboardRefreshPassesIgnoredIdentifiersToCalendarService() async {
        let ignoredIdentifier = "calendar-event-ignored-\(UUID().uuidString)"
        let allowedIdentifier = "calendar-event-team-sync-\(UUID().uuidString)"
        settings.ignoreCalendarEventIdentifier(ignoredIdentifier)

        let calendarService = MockCalendarEventService()
        calendarService.eventsToReturn = [
            MeetingCalendarEventSnapshot(
                eventIdentifier: ignoredIdentifier,
                title: "Lunch break",
                startDate: Date(),
                endDate: Date().addingTimeInterval(3_600),
                attendees: [],
            ),
            MeetingCalendarEventSnapshot(
                eventIdentifier: allowedIdentifier,
                title: "Team Sync",
                startDate: Date(),
                endDate: Date().addingTimeInterval(3_600),
                attendees: ["Alice", "Bob"],
            ),
        ]

        let viewModel = MetricsDashboardViewModel(
            storage: MockStorageService(),
            calendarEventService: calendarService,
            recordingManager: .shared,
            settingsStore: settings,
        )

        await viewModel.load()

        XCTAssertTrue(calendarService.lastIgnoredIdentifiers.contains(ignoredIdentifier))
        XCTAssertFalse(viewModel.upcomingEvents.map(\.eventIdentifier).contains(ignoredIdentifier))
        XCTAssertTrue(viewModel.upcomingEvents.map(\.eventIdentifier).contains(allowedIdentifier))
    }

    private func restoreIgnoredIdentifiers() {
        let current = settings.ignoredCalendarEventIdentifiers()

        for identifier in current.subtracting(originalIgnoredIdentifiers) {
            settings.unignoreCalendarEventIdentifier(identifier)
        }

        for identifier in originalIgnoredIdentifiers.subtracting(current) {
            settings.ignoreCalendarEventIdentifier(identifier)
        }
    }
}

@MainActor
private final class MockCalendarEventService: CalendarEventServiceProtocol, @unchecked Sendable {
    let eventStoreChangesSubject = PassthroughSubject<Void, Never>()
    var eventsToReturn: [MeetingCalendarEventSnapshot] = []
    var lastIgnoredIdentifiers: Set<String> = []

    var eventStoreChanges: AnyPublisher<Void, Never> {
        eventStoreChangesSubject.eraseToAnyPublisher()
    }

    func authorizationState() -> PermissionState {
        .granted
    }

    func requestAccess() async -> PermissionState {
        .granted
    }

    func openSystemSettings() {}

    func refreshSources() {}

    func fetchUpcomingEvents(
        limit _: Int,
        now _: Date,
        window _: TimeInterval,
        ignoredEventIdentifiers: Set<String>,
    ) throws -> [MeetingCalendarEventSnapshot] {
        lastIgnoredIdentifiers = ignoredEventIdentifiers
        return eventsToReturn.filter { !ignoredEventIdentifiers.contains($0.eventIdentifier) }
    }

    func bestMatchingEvent(
        at _: Date,
        in events: [MeetingCalendarEventSnapshot],
    ) -> MeetingCalendarEventSnapshot? {
        events.first
    }
}
