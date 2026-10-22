@testable import MeetingAssistantCore
import XCTest

final class MetricsAggregatorTests: XCTestCase {
    func testComputeSummary_TimeSavedUsesRecordedDuration() {
        // Given
        let calendar = Self.gregorianCalendarMondayFirst()

        let monday = Self.date(year: 2_026, month: 2, day: 2, time: (hour: 10, minute: 0), calendar: calendar)
        let tuesday = Self.date(year: 2_026, month: 2, day: 3, time: (hour: 10, minute: 0), calendar: calendar)

        let metadata: [TranscriptionMetadata] = [
            TranscriptionMetadata(
                id: UUID(),
                meetingId: UUID(),
                appName: "Teams",
                appRawValue: "microsoft-teams",
                appBundleIdentifier: nil,
                startTime: monday,
                createdAt: monday,
                previewText: "",
                wordCount: 100,
                language: "pt",
                isPostProcessed: false,
                duration: 60,
                audioFilePath: nil,
                inputSource: "Microphone",
            ),
            TranscriptionMetadata(
                id: UUID(),
                meetingId: UUID(),
                appName: "Teams",
                appRawValue: "microsoft-teams",
                appBundleIdentifier: nil,
                startTime: tuesday,
                createdAt: tuesday,
                previewText: "",
                wordCount: 50,
                language: "pt",
                isPostProcessed: false,
                duration: 30,
                audioFilePath: nil,
                inputSource: "Microphone",
            ),
        ]

        // When
        let summary = MetricsAggregator.computeSummary(metadata: metadata, baselineTypingWordsPerMinute: 35)

        // Then
        XCTAssertEqual(summary.sessionsRecorded, 2)
        XCTAssertEqual(summary.wordsDictated, 150)
        XCTAssertEqual(summary.totalRecordedDuration, 90, accuracy: 0.001)
        XCTAssertEqual(summary.estimatedTypingDuration, (150.0 / 35.0) * 60.0, accuracy: 0.001)
        XCTAssertEqual(summary.timeSaved, summary.estimatedTypingDuration - summary.totalRecordedDuration, accuracy: 0.001)
    }

    func testComputeWeekdayBuckets_OrdersByCalendarFirstWeekday() {
        // Given
        var calendar = Self.gregorianCalendarMondayFirst()
        calendar.firstWeekday = 2 // Monday

        let monday = Self.date(year: 2_026, month: 2, day: 2, time: (hour: 10, minute: 0), calendar: calendar) // Monday
        let wednesday = Self.date(year: 2_026, month: 2, day: 2, time: (hour: 10, minute: 0), calendar: calendar)
            .addingTimeInterval(2 * 24 * 60 * 60) // Wednesday

        let metadata: [TranscriptionMetadata] = [
            TranscriptionMetadata(
                id: UUID(),
                meetingId: UUID(),
                appName: "Teams",
                appRawValue: "microsoft-teams",
                appBundleIdentifier: nil,
                startTime: monday,
                createdAt: monday,
                previewText: "",
                wordCount: 10,
                language: "pt",
                isPostProcessed: false,
                duration: 10,
                audioFilePath: nil,
                inputSource: "Microphone",
            ),
            TranscriptionMetadata(
                id: UUID(),
                meetingId: UUID(),
                appName: "Teams",
                appRawValue: "microsoft-teams",
                appBundleIdentifier: nil,
                startTime: wednesday,
                createdAt: wednesday,
                previewText: "",
                wordCount: 5,
                language: "pt",
                isPostProcessed: false,
                duration: 10,
                audioFilePath: nil,
                inputSource: "Microphone",
            ),
        ]

        // When
        let buckets = MetricsAggregator.computeWeekdayBuckets(metadata: metadata, calendar: calendar)

        // Then
        XCTAssertEqual(buckets.count, 7)
        XCTAssertEqual(buckets.first?.weekday, 2)

        let mondayBucket = buckets.first { $0.weekday == 2 }
        XCTAssertEqual(mondayBucket?.words, 10)

        let wednesdayBucket = buckets.first { $0.weekday == 4 }
        XCTAssertEqual(wednesdayBucket?.words, 5)
    }

    func testComputeTopAppUsageBuckets_ReturnsTopSixAndAggregatesRemainingIntoOther() {
        let metadata = makeMetadata(appName: "Zoom", appRawValue: CaptureOrigin.zoom.rawValue, sessions: 6)
            + makeMetadata(appName: "Microsoft Teams", appRawValue: CaptureOrigin.microsoftTeams.rawValue, sessions: 5)
            + makeMetadata(appName: "Slack", appRawValue: CaptureOrigin.slack.rawValue, sessions: 4)
            + makeMetadata(appName: "Discord", appRawValue: CaptureOrigin.discord.rawValue, sessions: 3)
            + makeMetadata(appName: "Google Meet", appRawValue: CaptureOrigin.googleMeet.rawValue, sessions: 2)
            + makeMetadata(appName: "Manual", appRawValue: CaptureOrigin.manualMeeting.rawValue, sessions: 1)
            + makeMetadata(appName: "Unknown", appRawValue: CaptureOrigin.unknown.rawValue, sessions: 1)

        let buckets = MetricsAggregator.computeTopAppUsageBuckets(
            metadata: metadata,
            topLimit: 6,
            otherLabel: "Other Apps",
        )

        XCTAssertEqual(buckets.count, 7)
        XCTAssertEqual(buckets[0].appRawValue, CaptureOrigin.zoom.rawValue)
        XCTAssertEqual(buckets[0].sessions, 6)
        XCTAssertEqual(buckets[5].appRawValue, CaptureOrigin.manualMeeting.rawValue)
        XCTAssertEqual(buckets[5].sessions, 1)

        guard let otherBucket = buckets.last else {
            XCTFail("Expected an aggregated 'Other' bucket")
            return
        }

        XCTAssertTrue(otherBucket.isOther)
        XCTAssertEqual(otherBucket.appName, "Other Apps")
        XCTAssertEqual(otherBucket.sessions, 1)
    }

    func testComputeTopAppUsageBuckets_DoesNotCreateOtherBucketWhenTopLimitNotExceeded() {
        let metadata = makeMetadata(appName: "Zoom", appRawValue: CaptureOrigin.zoom.rawValue, sessions: 3)
            + makeMetadata(appName: "Slack", appRawValue: CaptureOrigin.slack.rawValue, sessions: 2)

        let buckets = MetricsAggregator.computeTopAppUsageBuckets(
            metadata: metadata,
            topLimit: 6,
            otherLabel: "Other Apps",
        )

        XCTAssertEqual(buckets.count, 2)
        XCTAssertFalse(buckets.contains(where: \.isOther))
    }

    private static func gregorianCalendarMondayFirst() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.locale = Locale(identifier: "pt_BR")
        calendar.firstWeekday = 2
        return calendar
    }

    private func makeMetadata(appName: String, appRawValue: String, sessions: Int) -> [TranscriptionMetadata] {
        (0..<sessions).map { index in
            let timestamp = Date(timeIntervalSince1970: TimeInterval(index))
            return TranscriptionMetadata(
                id: UUID(),
                meetingId: UUID(),
                appName: appName,
                appRawValue: appRawValue,
                appBundleIdentifier: nil,
                startTime: timestamp,
                createdAt: timestamp,
                previewText: "",
                wordCount: 10,
                language: "en",
                isPostProcessed: false,
                duration: 60,
                audioFilePath: nil,
                inputSource: "Microphone",
            )
        }
    }

    private static func date(year: Int, month: Int, day: Int, time: (hour: Int, minute: Int), calendar: Calendar) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = time.hour
        components.minute = time.minute
        return components.date ?? Date(timeIntervalSince1970: 0)
    }
}
