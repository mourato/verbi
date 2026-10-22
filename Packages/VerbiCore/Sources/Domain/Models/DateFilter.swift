import Foundation
import VerbiCoreCommon

/// Filter for transcription date ranges.
public enum DateFilter: String, CaseIterable, Sendable {
    case today
    case yesterday
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case allEntries

    /// Display name for the filter option.
    public var displayName: String {
        switch self {
        case .today:
            "filter.date.today".localized
        case .yesterday:
            "filter.date.yesterday".localized
        case .thisWeek:
            "filter.date.this_week".localized
        case .lastWeek:
            "filter.date.last_week".localized
        case .thisMonth:
            "filter.date.this_month".localized
        case .lastMonth:
            "filter.date.last_month".localized
        case .allEntries:
            "filter.date.all".localized
        }
    }

    /// Date range for filtering.
    /// Returns a tuple of (start, end) dates for the filter period.
    public var dateRange: (start: Date, end: Date) {
        let calculator = DateRangeCalculator()

        switch self {
        case .today:
            return calculator.todayRange()
        case .yesterday:
            return calculator.yesterdayRange()
        case .thisWeek:
            return calculator.thisWeekRange()
        case .lastWeek:
            return calculator.lastWeekRange()
        case .thisMonth:
            return calculator.thisMonthRange()
        case .lastMonth:
            return calculator.lastMonthRange()
        case .allEntries:
            return (.distantPast, .distantFuture)
        }
    }

    /// Checks if a date falls within the filter's range.
    public func contains(_ date: Date) -> Bool {
        let range = dateRange
        return date >= range.start && date < range.end
    }
}

// MARK: - Date Range Calculator

/// Helper struct for calculating date ranges.
/// Extracted to keep individual functions under 20 lines.
private struct DateRangeCalculator {
    private let calendar = Calendar.current
    private let now = Date()

    func todayRange() -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        return (start, end)
    }

    func yesterdayRange() -> (start: Date, end: Date) {
        let todayStart = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? now
        return (start, todayStart)
    }

    func thisWeekRange() -> (start: Date, end: Date) {
        let start = startOfCurrentWeek()
        let end = endOfToday()
        return (start, end)
    }

    func lastWeekRange() -> (start: Date, end: Date) {
        let thisWeekStart = startOfCurrentWeek()
        let start = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? now
        return (start, thisWeekStart)
    }

    func thisMonthRange() -> (start: Date, end: Date) {
        let start = startOfCurrentMonth()
        let end = endOfToday()
        return (start, end)
    }

    func lastMonthRange() -> (start: Date, end: Date) {
        let thisMonthStart = startOfCurrentMonth()
        let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? now
        return (start, thisMonthStart)
    }

    // MARK: - Private Helpers

    private func startOfCurrentWeek() -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return calendar.date(from: components) ?? now
    }

    private func startOfCurrentMonth() -> Date {
        let components = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: components) ?? now
    }

    private func endOfToday() -> Date {
        let todayStart = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
    }
}
