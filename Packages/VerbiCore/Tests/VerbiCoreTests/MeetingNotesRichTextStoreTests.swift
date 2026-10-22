import Foundation
@testable import VerbiCoreUI
import XCTest

@MainActor
final class MeetingNotesRichTextStoreTests: XCTestCase {
    private var userDefaults: UserDefaults!
    private var store: MeetingNotesRichTextStore!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "MeetingNotesRichTextStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create test UserDefaults suite")
            return
        }
        userDefaults = defaults
        store = MeetingNotesRichTextStore(userDefaults: userDefaults)
    }

    override func tearDown() async throws {
        if let suiteName {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        suiteName = nil
        userDefaults = nil
        store = nil
        try await super.tearDown()
    }

    func testMeetingNotesRTFData_SaveLoadAndRemove() {
        let meetingID = UUID()
        let data = Data([0x7b, 0x5c, 0x72, 0x74, 0x66]) // "{\\rtf"

        store.saveMeetingNotesRTFData(data, for: meetingID)
        XCTAssertEqual(store.meetingNotesRTFData(for: meetingID), data)

        store.saveMeetingNotesRTFData(nil, for: meetingID)
        XCTAssertNil(store.meetingNotesRTFData(for: meetingID))
    }

    func testCalendarEventNotesRTFData_SaveLoadAndRemove() {
        let eventIdentifier = "event-\(UUID().uuidString)"
        let data = Data([0x7b, 0x5c, 0x72, 0x74, 0x66])

        store.saveCalendarEventNotesRTFData(data, for: eventIdentifier)
        XCTAssertEqual(store.calendarEventNotesRTFData(for: eventIdentifier), data)

        store.saveCalendarEventNotesRTFData(nil, for: eventIdentifier)
        XCTAssertNil(store.calendarEventNotesRTFData(for: eventIdentifier))
    }

    func testTranscriptionNotesRTFData_SaveLoadAndRemove() {
        let transcriptionID = UUID()
        let data = Data([0x7b, 0x5c, 0x72, 0x74, 0x66])

        store.saveTranscriptionNotesRTFData(data, for: transcriptionID)
        XCTAssertEqual(store.transcriptionNotesRTFData(for: transcriptionID), data)

        store.saveTranscriptionNotesRTFData(nil, for: transcriptionID)
        XCTAssertNil(store.transcriptionNotesRTFData(for: transcriptionID))
    }

    func testMissingAndEmptyDataFallbacks() {
        let meetingID = UUID()
        XCTAssertNil(store.meetingNotesRTFData(for: meetingID))

        store.saveMeetingNotesRTFData(Data(), for: meetingID)
        XCTAssertNil(store.meetingNotesRTFData(for: meetingID))
    }
}
