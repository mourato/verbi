import Foundation

/// Shared utilities for time formatting across the application.
public enum TimeFormatter {
    /// Format seconds into a human-readable time string.
    /// - Parameter seconds: Time interval in seconds
    /// - Returns: Formatted string (e.g., "5s", "2m 30s", "1h 15m")
    public static func format(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }

    /// Format seconds into a compact time string (MM:SS or HH:MM:SS).
    /// - Parameter seconds: Time interval in seconds
    /// - Returns: Formatted string (e.g., "05:30", "01:15:00")
    public static func formatCompact(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds / 3600)
        let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        let secs = Int(seconds.truncatingRemainder(dividingBy: 60))

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}
