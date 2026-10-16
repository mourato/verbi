import Combine
import Foundation
@testable import MeetingAssistantCore
@testable import MeetingAssistantCoreCommon
@testable import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreInfrastructure
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
extension RecordingManagerTests {
    func testLinkedCalendarEventChangeRefreshesSnapshotAndAutomaticTitle() async throws {
        let manager = try XCTUnwrap(manager)
        let calendarEventService = try XCTUnwrap(mockCalendarEventService)
        let meetingStart = Date()
        let oldEvent = makeLinkedEvent(title: "Planning", startDate: meetingStart.addingTimeInterval(-300))
        let nearbyEvent = makeLinkedEvent(
            title: "Moved occurrence",
            startDate: meetingStart.addingTimeInterval(-7_200),
            notes: "Not the active occurrence"
        )
        let refreshedEvent = makeLinkedEvent(
            title: "Updated planning",
            startDate: meetingStart.addingTimeInterval(-600),
            endDate: meetingStart.addingTimeInterval(5_400),
            notes: "Updated event notes"
        )
        manager.currentMeeting = Meeting(
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
        let meetingStart = Date()
        let oldEvent = makeLinkedEvent(title: "Planning", startDate: meetingStart.addingTimeInterval(-300))
        let refreshedEvent = makeLinkedEvent(
            title: "Updated planning",
            startDate: meetingStart.addingTimeInterval(-300),
            notes: "Updated event notes"
        )
        manager.currentMeeting = Meeting(
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
        let meetingStart = Date()
        let oldEvent = makeLinkedEvent(title: "Planning", startDate: meetingStart.addingTimeInterval(-300))
        manager.currentMeeting = Meeting(
            app: .zoom,
            capturePurpose: .meeting,
            title: oldEvent.trimmedTitle,
            linkedCalendarEvent: oldEvent,
            startTime: meetingStart
        )
        calendarEventService.eventsToReturn = []

        let refreshCompleted = expectation(description: "linked calendar event lookup completed")
        calendarEventService.onFetch = { refreshCompleted.fulfill() }
        calendarEventService.eventStoreChangesSubject.send()
        await fulfillment(of: [refreshCompleted], timeout: 2)

        XCTAssertEqual(manager.currentMeeting?.linkedCalendarEvent, oldEvent)
        XCTAssertEqual(manager.currentMeeting?.title, "Planning")
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
            endDate: endDate ?? startDate.addingTimeInterval(3_600),
            notes: notes
        )
    }
}
