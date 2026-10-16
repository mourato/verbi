import Foundation
import MeetingAssistantCoreDomain
@testable import MeetingAssistantCoreUI
import XCTest

@MainActor
final class NotesScopeResolverTests: XCTestCase {
    func testResolvePrefersActiveMeetingSession() {
        let meetingID = UUID()
        let scope = NotesScopeResolver.resolve(
            context: NotesScopeResolver.Context(
                isRecordingMeeting: true,
                currentMeetingID: meetingID,
                lastEditedCalendarEventIdentifier: "event-a",
                ignoredCalendarEventIdentifiers: [],
                fetchUpcomingEvents: { [] },
            ),
        )

        XCTAssertEqual(scope, .meetingSession(meetingID: meetingID))
    }

    func testResolveUsesImminentCalendarEventWhenIdle() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let event = MeetingCalendarEventSnapshot(
            eventIdentifier: "event-a",
            title: "Standup",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(3_600),
        )

        let scope = NotesScopeResolver.resolve(
            context: NotesScopeResolver.Context(
                isRecordingMeeting: false,
                currentMeetingID: nil,
                lastEditedCalendarEventIdentifier: "event-b",
                ignoredCalendarEventIdentifiers: [],
                fetchUpcomingEvents: { [event] },
            ),
            now: now,
        )

        XCTAssertEqual(scope, .calendarEvent(eventIdentifier: "event-a"))
    }

    func testResolveSkipsIgnoredOccurrenceOfCalendarEvent() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let event = MeetingCalendarEventSnapshot(
            eventIdentifier: "event-a",
            title: "Standup",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(3600)
        )

        let scope = NotesScopeResolver.resolve(
            context: NotesScopeResolver.Context(
                isRecordingMeeting: false,
                currentMeetingID: nil,
                lastEditedCalendarEventIdentifier: nil,
                ignoredCalendarEventIdentifiers: [MeetingReminderOccurrenceKey.make(for: event)],
                fetchUpcomingEvents: { [event] }
            ),
            now: now
        )

        XCTAssertNil(scope)
    }

    func testResolveSkipsSeriesIgnoredByLegacyIdentifier() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let event = MeetingCalendarEventSnapshot(
            eventIdentifier: "event-a",
            title: "Standup",
            startDate: now.addingTimeInterval(600),
            endDate: now.addingTimeInterval(3600)
        )

        let scope = NotesScopeResolver.resolve(
            context: NotesScopeResolver.Context(
                isRecordingMeeting: false,
                currentMeetingID: nil,
                lastEditedCalendarEventIdentifier: nil,
                ignoredCalendarEventIdentifiers: ["event-a"],
                fetchUpcomingEvents: { [event] }
            ),
            now: now
        )

        XCTAssertNil(scope)
    }

    func testResolveFallsBackToLastEditedCalendarEvent() {
        let scope = NotesScopeResolver.resolve(
            context: NotesScopeResolver.Context(
                isRecordingMeeting: false,
                currentMeetingID: nil,
                lastEditedCalendarEventIdentifier: "event-b",
                ignoredCalendarEventIdentifiers: [],
                fetchUpcomingEvents: { [] },
            ),
        )

        XCTAssertEqual(scope, .calendarEvent(eventIdentifier: "event-b"))
    }
}
