@testable import VerbiCore
@testable import VerbiCoreUI
import XCTest

final class MetricsDashboardNavigationTests: XCTestCase {
    func testOpenEventDetailRoute() {
        var navigationState = SettingsSubpageNavigationState<MetricsDashboardRoute>()
        let event = MeetingCalendarEventSnapshot(
            eventIdentifier: "event-1",
            title: "Design Review",
            startDate: Date(timeIntervalSince1970: 1_700_000_000),
            endDate: Date(timeIntervalSince1970: 1_700_003_600),
        )

        navigationState.open(.eventDetail(event))

        XCTAssertEqual(navigationState.currentRoute, .eventDetail(event))
        XCTAssertTrue(navigationState.canGoBack)
        XCTAssertFalse(navigationState.canGoForward)
    }

    func testBackAndForwardRestoresEventDetailRoute() {
        var navigationState = SettingsSubpageNavigationState<MetricsDashboardRoute>()
        let event = MeetingCalendarEventSnapshot(
            eventIdentifier: "event-2",
            title: "Planning",
            startDate: Date(timeIntervalSince1970: 1_700_010_000),
            endDate: Date(timeIntervalSince1970: 1_700_013_600),
        )

        navigationState.open(.eventDetail(event))
        _ = navigationState.goBack()

        XCTAssertNil(navigationState.currentRoute)
        XCTAssertTrue(navigationState.canGoForward)

        _ = navigationState.goForward()

        XCTAssertEqual(navigationState.currentRoute, .eventDetail(event))
    }

    func testOpenPerformanceRecordingRoute() throws {
        var navigationState = SettingsSubpageNavigationState<MetricsDashboardRoute>()
        let recordingID = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))

        navigationState.open(.performanceRecording(recordingID))

        XCTAssertEqual(navigationState.currentRoute, .performanceRecording(recordingID))
        XCTAssertTrue(navigationState.canGoBack)
    }

    func testActivityFirstFoldKeepsExploreAndCalendarSecondaryToSummary() {
        // Composition invariant: summary is the populated first-fold story;
        // trend stays available once loading zeros resolve so filters remain reachable.
        XCTAssertEqual(
            MetricsDashboardFirstFold.content(isLoading: false, sessionsRecorded: 3),
            .summary,
        )
        XCTAssertTrue(MetricsDashboardFirstFold.showsTrendSection(isLoading: false, sessionsRecorded: 3))
        XCTAssertTrue(MetricsDashboardFirstFold.showsTrendSection(isLoading: false, sessionsRecorded: 0))
    }
}
