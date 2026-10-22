import Combine
@testable import VerbiCore
@testable import VerbiCoreCommon
@testable import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
final class MetricsDashboardViewModelTests: XCTestCase {
    func testEventStoreChangesRefetchUpcomingEvents() async {
        let calendarEventService = MockCalendarEventService()
        let initialEvent = makeCalendarEvent(title: "Planning")
        let updatedEvent = makeCalendarEvent(title: "Updated planning")
        calendarEventService.eventsToReturn = [initialEvent]

        let viewModel = makeViewModel(
            storage: MockStorageService(),
            calendarEventService: calendarEventService
        )
        await viewModel.load()
        XCTAssertEqual(viewModel.upcomingEvents, [initialEvent])

        let fetchCountBeforeChange = calendarEventService.fetchCount
        let refreshCompleted = expectation(description: "calendar change refetches dashboard events")
        var didFulfill = false
        calendarEventService.onFetch = {
            if calendarEventService.fetchCount > fetchCountBeforeChange, !didFulfill {
                didFulfill = true
                refreshCompleted.fulfill()
            }
        }
        calendarEventService.eventsToReturn = [updatedEvent]

        calendarEventService.eventStoreChangesSubject.send()
        await fulfillment(of: [refreshCompleted], timeout: 2)

        XCTAssertEqual(viewModel.upcomingEvents, [updatedEvent])
        XCTAssertFalse(viewModel.isLoadingCalendar)
    }

    func testLoadIfNeeded_DoesNotReloadWhenAlreadyLoaded() async {
        let storage = MockStorageService()
        storage.mockTranscriptions = [
            makeTranscription(wordCount: 3),
        ]
        let viewModel = makeViewModel(storage: storage)

        await viewModel.loadIfNeeded()
        XCTAssertEqual(viewModel.summary.sessionsRecorded, 1)

        storage.mockTranscriptions.append(makeTranscription(wordCount: 4))

        await viewModel.loadIfNeeded()
        XCTAssertEqual(viewModel.summary.sessionsRecorded, 1)

        await viewModel.load()
        XCTAssertEqual(viewModel.summary.sessionsRecorded, 2)
    }

    func testLoad_RefreshesAfterFirstLoadEvenWhenAlreadyLoaded() async {
        let storage = MockStorageService()
        storage.mockTranscriptions = [
            makeTranscription(wordCount: 3),
        ]
        let viewModel = makeViewModel(storage: storage)

        await viewModel.load()
        XCTAssertEqual(viewModel.summary.sessionsRecorded, 1)
        XCTAssertEqual(viewModel.summary.wordsDictated, 3)

        storage.mockTranscriptions.append(makeTranscription(wordCount: 4))

        await viewModel.load()

        XCTAssertEqual(viewModel.summary.sessionsRecorded, 2)
        XCTAssertEqual(viewModel.summary.wordsDictated, 7)
    }

    func testHandleTranscriptionSaved_AddsSavedTranscriptionData() async {
        let storage = MockStorageService()
        let first = makeTranscription(wordCount: 2)
        let second = makeTranscription(wordCount: 5)
        storage.mockTranscriptions = [first]

        let viewModel = makeViewModel(storage: storage)
        await viewModel.load()
        XCTAssertEqual(viewModel.summary.sessionsRecorded, 1)

        storage.mockTranscriptions.append(second)
        let notification = Notification(
            name: .meetingAssistantTranscriptionSaved,
            object: nil,
            userInfo: [AppNotifications.UserInfoKey.transcriptionId: second.id.uuidString],
        )
        await viewModel.handleTranscriptionSaved(notification)

        XCTAssertEqual(viewModel.summary.sessionsRecorded, 2)
        XCTAssertEqual(viewModel.summary.wordsDictated, 7)
        XCTAssertTrue(viewModel.dailyBuckets.contains { $0.words >= 7 })
    }

    func testHandleTranscriptionSaved_UpdatesExistingMetadataWithoutDuplicating() async {
        let storage = MockStorageService()
        let original = makeTranscription(wordCount: 2)
        storage.mockTranscriptions = [original]

        let viewModel = makeViewModel(storage: storage)
        await viewModel.load()

        let updated = makeTranscription(id: original.id, wordCount: 5)
        storage.mockTranscriptions = [updated]
        let notification = Notification(
            name: .meetingAssistantTranscriptionSaved,
            object: nil,
            userInfo: [AppNotifications.UserInfoKey.transcriptionId: original.id.uuidString],
        )

        await viewModel.handleTranscriptionSaved(notification)

        XCTAssertEqual(viewModel.summary.sessionsRecorded, 1)
        XCTAssertEqual(viewModel.summary.wordsDictated, 5)
    }

    func testHandleTranscriptionSaved_MissingIDFallsBackToRefresh() async {
        let storage = MockStorageService()
        storage.mockTranscriptions = [
            makeTranscription(wordCount: 3),
        ]
        let viewModel = makeViewModel(storage: storage)

        await viewModel.load()
        XCTAssertEqual(viewModel.summary.sessionsRecorded, 1)

        storage.mockTranscriptions.append(makeTranscription(wordCount: 6))
        let notification = Notification(name: .meetingAssistantTranscriptionSaved)
        await viewModel.handleTranscriptionSaved(notification)

        XCTAssertEqual(viewModel.summary.sessionsRecorded, 2)
        XCTAssertEqual(viewModel.summary.wordsDictated, 9)
    }

    func testLoad_ComputesTopAppUsageBucketsWithOtherGroup() async {
        let storage = MockStorageService()
        storage.mockTranscriptions = [
            makeTranscription(wordCount: 10, app: .zoom),
            makeTranscription(wordCount: 10, app: .zoom),
            makeTranscription(wordCount: 10, app: .microsoftTeams),
            makeTranscription(wordCount: 10, app: .microsoftTeams),
            makeTranscription(wordCount: 10, app: .slack),
            makeTranscription(wordCount: 10, app: .discord),
            makeTranscription(wordCount: 10, app: .googleMeet),
            makeTranscription(wordCount: 10, app: .manualMeeting),
            makeTranscription(wordCount: 10, app: .unknown),
        ]

        let viewModel = makeViewModel(storage: storage)
        await viewModel.load()

        XCTAssertEqual(viewModel.appUsageBuckets.count, 7)
        XCTAssertEqual(viewModel.appUsageBuckets.first?.sessions, 2)
        XCTAssertTrue(
            viewModel.appUsageBuckets.contains {
                $0.appRawValue == CaptureOrigin.zoom.rawValue && $0.sessions == 2
            },
        )
        XCTAssertTrue(
            viewModel.appUsageBuckets.contains {
                $0.appRawValue == CaptureOrigin.microsoftTeams.rawValue && $0.sessions == 2
            },
        )
        XCTAssertTrue(viewModel.appUsageBuckets.last?.isOther ?? false)
        XCTAssertEqual(viewModel.appUsageBuckets.last?.sessions, 1)
    }

    func testFirstFoldContent_DoesNotTreatLoadingZerosAsSummary() {
        XCTAssertEqual(
            MetricsDashboardFirstFold.content(isLoading: true, sessionsRecorded: 0),
            .loading,
        )
        XCTAssertEqual(
            MetricsDashboardFirstFold.content(isLoading: false, sessionsRecorded: 0),
            .empty,
        )
        XCTAssertEqual(
            MetricsDashboardFirstFold.content(isLoading: false, sessionsRecorded: 2),
            .summary,
        )
        XCTAssertEqual(
            MetricsDashboardFirstFold.content(isLoading: true, sessionsRecorded: 2),
            .summary,
        )
        XCTAssertFalse(MetricsDashboardFirstFold.showsHeroMetricsSubtitle(isLoading: true, sessionsRecorded: 0))
        XCTAssertFalse(MetricsDashboardFirstFold.showsHeroMetricsSubtitle(isLoading: false, sessionsRecorded: 0))
        XCTAssertTrue(MetricsDashboardFirstFold.showsHeroMetricsSubtitle(isLoading: false, sessionsRecorded: 1))
        XCTAssertFalse(MetricsDashboardFirstFold.showsTrendSection(isLoading: true, sessionsRecorded: 0))
        XCTAssertTrue(MetricsDashboardFirstFold.showsTrendSection(isLoading: false, sessionsRecorded: 0))
        XCTAssertTrue(MetricsDashboardFirstFold.showsTrendSection(isLoading: false, sessionsRecorded: 1))
    }

    private func makeViewModel(
        storage: MockStorageService,
        calendarEventService: any CalendarEventServiceProtocol = CalendarEventService.shared // justified: Swift existential type, not a lint suppression
    ) -> MetricsDashboardViewModel {
        let viewModel = MetricsDashboardViewModel(storage: storage, calendarEventService: calendarEventService)
        viewModel.showMeetings = true
        return viewModel
    }

    private func makeCalendarEvent(title: String) -> MeetingCalendarEventSnapshot {
        let startDate = Date().addingTimeInterval(600)
        return MeetingCalendarEventSnapshot(
            eventIdentifier: "dashboard-event",
            title: title,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(1800)
        )
    }

    private func makeTranscription(
        id: UUID = UUID(),
        wordCount: Int,
        app: CaptureOrigin = .microsoftTeams,
    ) -> CaptureArtifact {
        let words = Array(repeating: "word", count: max(wordCount, 1)).joined(separator: " ")
        let start = Date()
        let end = start.addingTimeInterval(60)
        let meeting = CaptureSession(
            id: UUID(),
            app: app,
            capturePurpose: .meeting,
            startTime: start,
            endTime: end,
        )

        return CaptureArtifact(
            id: id,
            meeting: meeting,
            text: words,
            rawText: words,
            createdAt: start,
        )
    }
}
