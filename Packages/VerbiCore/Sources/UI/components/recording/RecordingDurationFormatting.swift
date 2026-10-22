import Foundation

@MainActor
enum RecordingDurationFormatting {
    private static let minutesFormatter = makeFormatter(units: [.minute, .second])
    private static let hoursFormatter = makeFormatter(units: [.hour, .minute, .second])

    static func formatRecordingDuration(startTime: Date?, at date: Date) -> String {
        guard let startTime else { return "00:00" }
        let duration = max(0, date.timeIntervalSince(startTime))
        let formatter = duration >= 3600 ? hoursFormatter : minutesFormatter
        return formatter.string(from: duration) ?? "00:00"
    }

    private static func makeFormatter(units: NSCalendar.Unit) -> DateComponentsFormatter {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = units
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }
}
