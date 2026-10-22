@testable import VerbiCoreUI
import XCTest

final class ActivityHeatmapMonthMarkerTests: XCTestCase {
    func testResolveVisibleMonthMarkers_SkipsCollidingLabels() {
        let markers = [
            ActivityHeatmapMonthMarker(id: 0, label: "Mar", xOffset: 0),
            ActivityHeatmapMonthMarker(id: 1, label: "Apr", xOffset: 24),
            ActivityHeatmapMonthMarker(id: 2, label: "May", xOffset: 48),
            ActivityHeatmapMonthMarker(id: 3, label: "Jun", xOffset: 84),
        ]

        let visibleMarkers = ActivityHeatmap.resolveVisibleMonthMarkers(
            markers,
            estimatedLabelWidth: 24,
            minimumSpacing: 6,
        )

        XCTAssertEqual(visibleMarkers.map(\.label), ["Mar", "May", "Jun"])
    }

    func testResolveVisibleMonthMarkers_KeepsFirstMarkerWhenRangeStartsMidMonth() {
        let markers = [
            ActivityHeatmapMonthMarker(id: 0, label: "Mar", xOffset: 0),
            ActivityHeatmapMonthMarker(id: 4, label: "Apr", xOffset: 60),
        ]

        let visibleMarkers = ActivityHeatmap.resolveVisibleMonthMarkers(markers)

        XCTAssertEqual(visibleMarkers.map(\.label), ["Mar", "Apr"])
    }

    func testShouldShowRangeStartMonthLabel_OnlyForFirstWeekInRangeMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        calendar.locale = Locale(identifier: "en_US")
        calendar.firstWeekday = 2

        let rangeStart = date(year: 2_025, month: 3, day: 8, calendar: calendar)
        let firstWeekStart = date(year: 2_025, month: 3, day: 3, calendar: calendar)
        let secondWeekStart = date(year: 2_025, month: 3, day: 10, calendar: calendar)

        XCTAssertTrue(
            ActivityHeatmap.shouldShowRangeStartMonthLabel(
                for: firstWeekStart,
                rangeStart: rangeStart,
                calendar: calendar,
            ),
        )
        XCTAssertFalse(
            ActivityHeatmap.shouldShowRangeStartMonthLabel(
                for: secondWeekStart,
                rangeStart: rangeStart,
                calendar: calendar,
            ),
        )
    }

    private func date(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        return components.date ?? Date(timeIntervalSince1970: 0)
    }
}
