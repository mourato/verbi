import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import SwiftUI

enum DashboardMetadataCache {
    private nonisolated(unsafe) static var storage: [TranscriptionMetadata]?

    static func get() -> [TranscriptionMetadata]? {
        storage
    }

    static func set(_ metadata: [TranscriptionMetadata]) {
        storage = metadata
    }

    static func clear() {
        storage = nil
    }
}

struct ActivityHeatmapWeekColumn: Identifiable {
    let id: Int
    let monthLabel: String?
    let days: [MetricsDailyBucket?]
}

struct ActivityHeatmapMonthMarker: Identifiable, Equatable {
    let id: Int
    let label: String
    let xOffset: CGFloat
}

/// Presentation mode for Activity's first-fold summary — never treat unknown
/// loading zeros as a populated story.
enum MetricsDashboardFirstFoldContent: Equatable {
    case loading
    case empty
    case summary
}

enum MetricsDashboardFirstFold {
    static func content(isLoading: Bool, sessionsRecorded: Int) -> MetricsDashboardFirstFoldContent {
        if isLoading, sessionsRecorded == 0 {
            return .loading
        }
        if sessionsRecorded == 0 {
            return .empty
        }
        return .summary
    }

    static func showsHeroMetricsSubtitle(isLoading: Bool, sessionsRecorded: Int) -> Bool {
        !isLoading && sessionsRecorded > 0
    }

    /// Hide the trend section only while the first fold is still resolving so
    /// we do not stack two ProgressViews; keep it when empty so filters stay reachable.
    static func showsTrendSection(isLoading: Bool, sessionsRecorded: Int) -> Bool {
        !(isLoading && sessionsRecorded == 0)
    }
}

enum MetricsDashboardFormatters {
    static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    static let calendarIntervalFormatter: DateIntervalFormatter = {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func formattedNumber(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func calendarEventIntervalLabel(startDate: Date, endDate: Date) -> String {
        calendarIntervalFormatter.string(from: startDate, to: endDate)
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "metrics.performance.summary.none".localized }
        if seconds < 60 {
            return String(format: "%.1fs", seconds)
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .pad
        return formatter.string(from: seconds) ?? String(format: "%.0fs", seconds)
    }

    static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

enum ActivityHeatmap {
    static let squareSize: CGFloat = 10
    static let spacing: CGFloat = 2
    static let verticalPadding: CGFloat = 8
    static let baseColor = AppDesignSystem.Colors.subtleFill
    static let monthHeaderHeight: CGFloat = 14
    static let monthToGridSpacing: CGFloat = 6
    static let estimatedMonthLabelWidth: CGFloat = 24
    static let monthLabelMinimumSpacing: CGFloat = 6
    static let weekdayLabelWidth: CGFloat = 24
    static let weekdayToGridSpacing: CGFloat = 8
    static let weekColumnPrefix = "heatmap-week"
    static let latestAnchorID = "heatmap-latest-anchor"

    static var gridHeight: CGFloat {
        squareSize * 7 + spacing * 6
    }

    static var scrollHeight: CGFloat {
        monthHeaderHeight + monthToGridSpacing + gridHeight + verticalPadding * 2
    }

    static func resolveVisibleMonthMarkers(
        _ markers: [ActivityHeatmapMonthMarker],
        estimatedLabelWidth: CGFloat = estimatedMonthLabelWidth,
        minimumSpacing: CGFloat = monthLabelMinimumSpacing
    ) -> [ActivityHeatmapMonthMarker] {
        var visibleMarkers: [ActivityHeatmapMonthMarker] = []

        for marker in markers {
            guard let lastMarker = visibleMarkers.last else {
                visibleMarkers.append(marker)
                continue
            }

            let lastMarkerEnd = lastMarker.xOffset + estimatedLabelWidth
            if marker.xOffset - lastMarkerEnd >= minimumSpacing {
                visibleMarkers.append(marker)
            }
        }

        return visibleMarkers
    }

    static func shouldShowRangeStartMonthLabel(
        for weekStart: Date,
        rangeStart: Date,
        calendar: Calendar
    ) -> Bool {
        guard calendar.component(.day, from: rangeStart) != 1 else {
            return false
        }

        let rangeStartWeek = calendar.dateInterval(of: .weekOfYear, for: rangeStart)?.start
        return rangeStartWeek == weekStart
    }

    static func makeWeekColumns(
        from dailyBuckets: [MetricsDailyBucket],
        calendar: Calendar = .current
    ) -> [ActivityHeatmapWeekColumn] {
        let buckets = dailyBuckets.sorted { $0.date < $1.date }
        guard let firstDate = buckets.first?.date, let lastDate = buckets.last?.date else {
            return []
        }

        let rangeStart = calendar.startOfDay(for: firstDate)
        let rangeEnd = calendar.startOfDay(for: lastDate)
        let firstWeekStart = calendar.dateInterval(of: .weekOfYear, for: rangeStart)?.start ?? rangeStart
        let lastWeekStart = calendar.dateInterval(of: .weekOfYear, for: rangeEnd)?.start ?? rangeEnd

        let bucketsByDate = Dictionary(uniqueKeysWithValues: buckets.map {
            (calendar.startOfDay(for: $0.date), $0)
        })

        var columns: [ActivityHeatmapWeekColumn] = []
        var weekStart = firstWeekStart
        var index = 0

        while weekStart <= lastWeekStart {
            let days: [MetricsDailyBucket?] = (0 ..< 7).map { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                    return nil
                }
                guard day >= rangeStart, day <= rangeEnd else {
                    return nil
                }
                return bucketsByDate[day] ?? MetricsDailyBucket(date: day, words: 0)
            }

            columns.append(
                ActivityHeatmapWeekColumn(
                    id: index,
                    monthLabel: monthLabelForWeek(startingAt: weekStart, rangeStart: rangeStart, rangeEnd: rangeEnd, calendar: calendar),
                    days: days
                )
            )

            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else {
                break
            }
            weekStart = nextWeek
            index += 1
        }

        return columns
    }

    static func makeMonthMarkers(
        from columns: [ActivityHeatmapWeekColumn]
    ) -> [ActivityHeatmapMonthMarker] {
        let rawMarkers: [ActivityHeatmapMonthMarker] = columns.compactMap { column in
            guard let monthLabel = column.monthLabel else { return nil }
            let xOffset = CGFloat(column.id) * (squareSize + spacing)
            return ActivityHeatmapMonthMarker(id: column.id, label: monthLabel, xOffset: xOffset)
        }
        return resolveVisibleMonthMarkers(rawMarkers)
    }

    static func gridWidth(columnCount: Int) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        let columns = CGFloat(columnCount)
        return columns * squareSize + (columns - 1) * spacing
    }

    private static func monthLabelForWeek(startingAt weekStart: Date, rangeStart: Date, rangeEnd: Date, calendar: Calendar) -> String? {
        for offset in 0 ..< 7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else {
                continue
            }
            guard date >= rangeStart, date <= rangeEnd else {
                continue
            }
            if calendar.component(.day, from: date) == 1 {
                return localizedMonthLabel(for: date)
            }
        }

        if shouldShowRangeStartMonthLabel(for: weekStart, rangeStart: rangeStart, calendar: calendar) {
            return localizedMonthLabel(for: rangeStart)
        }

        return nil
    }

    private static func localizedMonthLabel(for date: Date) -> String {
        let monthName = monthNameFormatter.string(from: date)
        return String(monthName.prefix(3))
    }

    private static let monthNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter
    }()

    static let legendSpacing: CGFloat = 12
    static let legendSwatchSize: CGFloat = 10
    static let legendSwatchCornerRadius: CGFloat = 2
}
