import Combine
import Foundation
@testable import VerbiCore
@testable import VerbiCoreCommon
@testable import VerbiCoreDomain
@testable import VerbiCoreInfrastructure
@testable import VerbiCoreUI
import XCTest

@MainActor
extension RecordingManagerTests {
    func testLinkedCalendarEventChangeRefreshesSnapshotAndAutomaticTitle() async throws {
        let manager = try XCTUnwrap(manager)
        let calendarEventService = try XCTUnwrap(mockCalendarEventService)
        await waitForInitialMeetingState(manager)
        let meetingStart = Date()
        let oldEvent = makeLinkedEvent(title: "Planning", startDate: meetingStart.addingTimeInterval(-300))
        let nearbyEvent = makeLinkedEvent(
            title: "Moved occurrence",
            startDate: meetingStart.addingTimeInterval(-7200),
            notes: "Not the active occurrence"
        )
        let refreshedEvent = makeLinkedEvent(
            title: "Updated planning",
            startDate: meetingStart.addingTimeInterval(-600),
            endDate: meetingStart.addingTimeInterval(5400),
            notes: "Updated event notes"
        )
        manager.currentMeeting = CaptureSession(
            app: .zoom,
            capturePurpose: .meeting,
            title: oldEvent.trimmedTitle,
            linkedCalendarEvent: oldEvent,
            startTime: meetingStart
        )
        calendarEventService.eventsToReturn = [nearbyEvent, refreshedEvent]

        let refreshCompleted = expectation(description: "linked calendar event refetched")
        calendarEventService.onFetch = { refreshCompleted.fulfill() }
        calendarEventService.eventStoreChangesSubject.send()
        await fulfillment(of: [refreshCompleted], timeout: 2)

        XCTAssertEqual(manager.currentMeeting?.linkedCalendarEvent, refreshedEvent)
        XCTAssertEqual(manager.currentMeeting?.title, "Updated planning")
        XCTAssertEqual(manager.currentMeeting?.linkedCalendarEvent?.notes, "Updated event notes")
    }

    func testLinkedCalendarEventChangePreservesManuallyEditedTitle() async throws {
        let manager = try XCTUnwrap(manager)
        let calendarEventService = try XCTUnwrap(mockCalendarEventService)
        await waitForInitialMeetingState(manager)
        let meetingStart = Date()
        let oldEvent = makeLinkedEvent(title: "Planning", startDate: meetingStart.addingTimeInterval(-300))
        let refreshedEvent = makeLinkedEvent(
            title: "Updated planning",
            startDate: meetingStart.addingTimeInterval(-300),
            notes: "Updated event notes"
        )
        manager.currentMeeting = CaptureSession(
            app: .zoom,
            capturePurpose: .meeting,
            title: "My meeting title",
            linkedCalendarEvent: oldEvent,
            startTime: meetingStart
        )
        calendarEventService.eventsToReturn = [refreshedEvent]

        let refreshCompleted = expectation(description: "linked calendar event refetched")
        calendarEventService.onFetch = { refreshCompleted.fulfill() }
        calendarEventService.eventStoreChangesSubject.send()
        await fulfillment(of: [refreshCompleted], timeout: 2)

        XCTAssertEqual(manager.currentMeeting?.linkedCalendarEvent, refreshedEvent)
        XCTAssertEqual(manager.currentMeeting?.title, "My meeting title")
    }

    func testLinkedCalendarEventChangeKeepsSnapshotWhenEventDisappears() async throws {
        let manager = try XCTUnwrap(manager)
        let calendarEventService = try XCTUnwrap(mockCalendarEventService)
        await waitForInitialMeetingState(manager)
        let meetingStart = Date()
        let oldEvent = makeLinkedEvent(title: "Planning", startDate: meetingStart.addingTimeInterval(-300))
        manager.currentMeeting = CaptureSession(
            app: .zoom,
            capturePurpose: .meeting,
            title: oldEvent.trimmedTitle,
            linkedCalendarEvent: oldEvent,
            startTime: meetingStart
        )
        calendarEventService.eventsToReturn = [makeLinkedEvent(
            title: "Another occurrence",
            startDate: meetingStart.addingTimeInterval(7200)
        )]

        let refreshCompleted = expectation(description: "linked calendar event lookup completed")
        calendarEventService.onFetch = { refreshCompleted.fulfill() }
        calendarEventService.eventStoreChangesSubject.send()
        await fulfillment(of: [refreshCompleted], timeout: 2)

        XCTAssertEqual(manager.currentMeeting?.linkedCalendarEvent, oldEvent)
        XCTAssertEqual(manager.currentMeeting?.title, "Planning")
    }

    private func waitForInitialMeetingState(_ manager: RecordingManager) async {
        let initialized = expectation(description: "initial actor meeting state published")
        let subscription = manager.currentMeetingPublisher
            .dropFirst()
            .first()
            .sink { _ in initialized.fulfill() }
        await fulfillment(of: [initialized], timeout: 2)
        subscription.cancel()
    }

    private func makeLinkedEvent(
        title: String,
        startDate: Date,
        endDate: Date? = nil,
        notes: String? = nil
    ) -> MeetingCalendarEventSnapshot {
        MeetingCalendarEventSnapshot(
            eventIdentifier: "linked-event",
            title: title,
            startDate: startDate,
            endDate: endDate ?? startDate.addingTimeInterval(3600),
            notes: notes
        )
    }
}
