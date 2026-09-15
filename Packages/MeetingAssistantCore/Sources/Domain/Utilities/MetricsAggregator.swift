import Foundation

public struct MetricsDashboardSummary: Equatable, Sendable {
    public let sessionsRecorded: Int
    public let wordsDictated: Int
    public let totalRecordedDuration: TimeInterval
    public let estimatedTypingDuration: TimeInterval
    public let timeSaved: TimeInterval
    public let baselineTypingWordsPerMinute: Double
    public let keystrokesSaved: Int
    public let wordsPerMinute: Double

    public init(
        sessionsRecorded: Int,
        wordsDictated: Int,
        totalRecordedDuration: TimeInterval,
        estimatedTypingDuration: TimeInterval,
        timeSaved: TimeInterval,
        baselineTypingWordsPerMinute: Double,
        keystrokesSaved: Int,
        wordsPerMinute: Double
    ) {
        self.sessionsRecorded = sessionsRecorded
        self.wordsDictated = wordsDictated
        self.totalRecordedDuration = totalRecordedDuration
        self.estimatedTypingDuration = estimatedTypingDuration
        self.timeSaved = timeSaved
        self.baselineTypingWordsPerMinute = baselineTypingWordsPerMinute
        self.keystrokesSaved = keystrokesSaved
        self.wordsPerMinute = wordsPerMinute
    }
}

public struct MetricsWeekdayBucket: Equatable, Identifiable, Sendable {
    public let weekday: Int
    public let words: Int

    public var id: Int {
        weekday
    }

    public init(weekday: Int, words: Int) {
        self.weekday = weekday
        self.words = words
    }
}

public struct MetricsHourlyBucket: Equatable, Identifiable, Sendable {
    public let hour: Int
    public let count: Int

    public var id: Int {
        hour
    }

    public init(hour: Int, count: Int) {
        self.hour = hour
        self.count = count
    }
}

public struct MetricsDailyBucket: Equatable, Identifiable, Sendable {
    public let date: Date
    public let words: Int

    public var id: Date {
        date
    }

    public init(date: Date, words: Int) {
        self.date = date
        self.words = words
    }
}

public struct MetricsAppUsageBucket: Equatable, Identifiable, Sendable {
    public let appRawValue: String
    public let appName: String
    public let sessions: Int
    public let isOther: Bool

    public var id: String {
        appRawValue
    }

    public init(
        appRawValue: String,
        appName: String,
        sessions: Int,
        isOther: Bool
    ) {
        self.appRawValue = appRawValue
        self.appName = appName
        self.sessions = sessions
        self.isOther = isOther
    }
}

public enum MetricsAggregator {
    private static let KEYSTROKES_PER_WORD = 5

    public static func computeSummary(
        metadata: [TranscriptionMetadata],
        baselineTypingWordsPerMinute: Double
    ) -> MetricsDashboardSummary {
        let sessionsRecorded = metadata.count
        let wordsDictated = metadata.reduce(0) { $0 + $1.wordCount }
        let totalRecordedDuration = metadata.reduce(0.0) { $0 + $1.duration }

        let estimatedTypingDuration: TimeInterval = if baselineTypingWordsPerMinute > 0 {
            (Double(wordsDictated) / baselineTypingWordsPerMinute) * 60.0
        } else {
            0
        }

        let timeSaved = max(estimatedTypingDuration - totalRecordedDuration, 0)
        let keystrokesSaved = wordsDictated * KEYSTROKES_PER_WORD
        let wordsPerMinute = totalRecordedDuration > 0 ? (Double(wordsDictated) / (totalRecordedDuration / 60.0)) : 0.0

        return MetricsDashboardSummary(
            sessionsRecorded: sessionsRecorded,
            wordsDictated: wordsDictated,
            totalRecordedDuration: totalRecordedDuration,
            estimatedTypingDuration: estimatedTypingDuration,
            timeSaved: timeSaved,
            baselineTypingWordsPerMinute: baselineTypingWordsPerMinute,
            keystrokesSaved: keystrokesSaved,
            wordsPerMinute: wordsPerMinute
        )
    }

    public static func computeWeekdayBuckets(
        metadata: [TranscriptionMetadata],
        calendar: Calendar = .current
    ) -> [MetricsWeekdayBucket] {
        var wordCounts: [Int: Int] = [:]
        wordCounts.reserveCapacity(7)

        for item in metadata {
            let weekday = calendar.component(.weekday, from: item.startTime)
            wordCounts[weekday, default: 0] += item.wordCount
        }

        let orderedWeekdays = orderedWeekdays(calendar: calendar)
        return orderedWeekdays.map { weekday in
            MetricsWeekdayBucket(weekday: weekday, words: wordCounts[weekday, default: 0])
        }
    }

    private static func orderedWeekdays(calendar: Calendar) -> [Int] {
        guard (1 ... 7).contains(calendar.firstWeekday) else {
            return Array(1 ... 7)
        }

        return (0 ..< 7).map { offset in
            ((calendar.firstWeekday - 1 + offset) % 7) + 1
        }
    }

    public static func computeHourlyBuckets(
        metadata: [TranscriptionMetadata],
        calendar: Calendar = .current
    ) -> [MetricsHourlyBucket] {
        var hourCounts: [Int: Int] = [:]
        hourCounts.reserveCapacity(24)

        for item in metadata {
            let hour = calendar.component(.hour, from: item.startTime)
            hourCounts[hour, default: 0] += 1
        }

        return (0 ..< 24).map { hour in
            MetricsHourlyBucket(hour: hour, count: hourCounts[hour, default: 0])
        }
    }

    public static func computeDailyBuckets(
        metadata: [TranscriptionMetadata],
        days: Int = 365,
        calendar: Calendar = .current
    ) -> [MetricsDailyBucket] {
        guard days > 0 else { return [] }

        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return []
        }

        var dayCounts: [Date: Int] = [:]
        dayCounts.reserveCapacity(days)

        for item in metadata {
            let day = calendar.startOfDay(for: item.startTime)
            guard day >= start, day <= today else { continue }
            dayCounts[day, default: 0] += item.wordCount
        }

        return (0 ..< days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else {
                return nil
            }

            return MetricsDailyBucket(date: date, words: dayCounts[date, default: 0])
        }
    }

    public static func computeTopAppUsageBuckets(
        metadata: [TranscriptionMetadata],
        topLimit: Int = 6,
        otherLabel: String = "Other"
    ) -> [MetricsAppUsageBucket] {
        guard topLimit > 0 else { return [] }

        struct AppUsageAccumulator {
            var appName: String
            var sessions: Int
        }

        var appUsage: [String: AppUsageAccumulator] = [:]

        for item in metadata {
            let normalizedRawValue = normalizeAppRawValue(item.appRawValue)
            let normalizedName = normalizeAppName(item.appName, appRawValue: normalizedRawValue)

            if var existing = appUsage[normalizedRawValue] {
                existing.sessions += 1
                appUsage[normalizedRawValue] = existing
            } else {
                appUsage[normalizedRawValue] = AppUsageAccumulator(
                    appName: normalizedName,
                    sessions: 1
                )
            }
        }

        let sortedUsage = appUsage
            .map { (appRawValue: $0.key, appName: $0.value.appName, sessions: $0.value.sessions) }
            .sorted { lhs, rhs in
                if lhs.sessions == rhs.sessions {
                    return lhs.appName.localizedCaseInsensitiveCompare(rhs.appName) == .orderedAscending
                }
                return lhs.sessions > rhs.sessions
            }

        let topApps = sortedUsage.prefix(topLimit).map { app in
            MetricsAppUsageBucket(
                appRawValue: app.appRawValue,
                appName: app.appName,
                sessions: app.sessions,
                isOther: false
            )
        }

        let remainingSessions = sortedUsage.dropFirst(topLimit).reduce(0) { partialResult, usage in
            partialResult + usage.sessions
        }

        guard remainingSessions > 0 else {
            return topApps
        }

        return topApps + [
            MetricsAppUsageBucket(
                appRawValue: "other",
                appName: otherLabel,
                sessions: remainingSessions,
                isOther: true
            )
        ]
    }

    private static func normalizeAppRawValue(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return MeetingApp.unknown.rawValue
        }
        return trimmed
    }

    private static func normalizeAppName(_ appName: String, appRawValue: String) -> String {
        let trimmedName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        if let meetingApp = MeetingApp(rawValue: appRawValue) {
            return meetingApp.displayName
        }

        return appRawValue
    }
}
