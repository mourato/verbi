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
    private var originalIgnoredIdentifiersData: Data?
    private var originalIgnoredOccurrencesData: Data?

    override func setUp() async throws {
        try await super.setUp()
        try AppSettingsTestIsolationLock.acquire()
        settings = AppSettingsStore.shared
        originalIgnoredIdentifiersData = UserDefaults.standard.data(forKey: AppSettingsStore.Keys.ignoredCalendarEventIdentifiers)
        originalIgnoredOccurrencesData = UserDefaults.standard.data(forKey: AppSettingsStore.Keys.ignoredCalendarEventOccurrenceEndDates)
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

    func testIgnoringOneOccurrenceKeepsNextOccurrenceOfSameSeries() {
        let seriesID = "series-\(UUID().uuidString)"
        let now = Date()
        let current = makeOccurrence(seriesID: seriesID, start: now)
        let next = makeOccurrence(seriesID: seriesID, start: now.addingTimeInterval(86400))

        settings.ignoreCalendarEventOccurrence(current)

        let ignored = settings.ignoredCalendarEventIdentifiers()
        XCTAssertTrue(current.isIgnored(by: ignored))
        XCTAssertFalse(next.isIgnored(by: ignored))
        XCTAssertFalse(ignored.contains(seriesID))
    }

    func testLegacyRawIdentifierStillHidesWholeSeries() {
        let seriesID = "series-\(UUID().uuidString)"
        let now = Date()
        let current = makeOccurrence(seriesID: seriesID, start: now)
        let next = makeOccurrence(seriesID: seriesID, start: now.addingTimeInterval(86400))

        settings.ignoreCalendarEventIdentifier(seriesID)

        let ignored = settings.ignoredCalendarEventIdentifiers()
        XCTAssertTrue(current.isIgnored(by: ignored))
        XCTAssertTrue(next.isIgnored(by: ignored))
    }

    func testUnignoringOccurrenceRestoresOnlyThatOccurrence() {
        let seriesID = "series-\(UUID().uuidString)"
        let now = Date()
        let current = makeOccurrence(seriesID: seriesID, start: now)
        let next = makeOccurrence(seriesID: seriesID, start: now.addingTimeInterval(86400))
        settings.ignoreCalendarEventOccurrence(current)
        settings.ignoreCalendarEventOccurrence(next)

        settings.unignoreCalendarEventOccurrence(current)

        let ignored = settings.ignoredCalendarEventIdentifiers()
        XCTAssertFalse(current.isIgnored(by: ignored))
        XCTAssertTrue(next.isIgnored(by: ignored))
    }

    func testExpiredOccurrencesArePrunedOnWrite() {
        let seriesID = "series-\(UUID().uuidString)"
        let now = Date()
        let expired = makeOccurrence(seriesID: seriesID, start: now.addingTimeInterval(-9 * 86400))
        let fresh = makeOccurrence(seriesID: seriesID, start: now)

        settings.ignoreCalendarEventOccurrence(expired)
        XCTAssertFalse(expired.isIgnored(by: settings.ignoredCalendarEventIdentifiers()))

        settings.ignoreCalendarEventOccurrence(fresh)

        let storedEndDates = storedIgnoredOccurrenceEndDates()
        XCTAssertNil(storedEndDates[MeetingReminderOccurrenceKey.make(for: expired)])
        XCTAssertNotNil(storedEndDates[MeetingReminderOccurrenceKey.make(for: fresh)])
    }

    func testDashboardIgnoreHidesOneOccurrenceAndKeepsNextOccurrence() async {
        let seriesID = "calendar-series-\(UUID().uuidString)"
        let now = Date()
        let current = makeOccurrence(seriesID: seriesID, start: now)
        let next = makeOccurrence(seriesID: seriesID, start: now.addingTimeInterval(7200))

        let calendarService = MockCalendarEventService()
        calendarService.eventsToReturn = [current, next]
        let viewModel = MetricsDashboardViewModel(
            storage: MockStorageService(),
            calendarEventService: calendarService,
            recordingManager: .shared,
            settingsStore: settings
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.upcomingEvents, [current, next])

        viewModel.ignoreUpcomingEvent(current)

        XCTAssertEqual(viewModel.upcomingEvents, [next])
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
        restoreDefault(originalIgnoredIdentifiersData, forKey: AppSettingsStore.Keys.ignoredCalendarEventIdentifiers)
        restoreDefault(originalIgnoredOccurrencesData, forKey: AppSettingsStore.Keys.ignoredCalendarEventOccurrenceEndDates)
    }

    private func restoreDefault(_ data: Data?, forKey key: String) {
        if let data {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func makeOccurrence(seriesID: String, start: Date) -> MeetingCalendarEventSnapshot {
        MeetingCalendarEventSnapshot(
            eventIdentifier: seriesID,
            title: "Weekly sync",
            startDate: start,
            endDate: start.addingTimeInterval(3600)
        )
    }

    private func storedIgnoredOccurrenceEndDates() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: AppSettingsStore.Keys.ignoredCalendarEventOccurrenceEndDates) else {
            return [:]
        }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
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
        return eventsToReturn.filter { !$0.isIgnored(by: ignoredEventIdentifiers) }
    }

    func bestMatchingEvent(
        at _: Date,
        in events: [MeetingCalendarEventSnapshot],
    ) -> MeetingCalendarEventSnapshot? {
        events.first
    }
}
