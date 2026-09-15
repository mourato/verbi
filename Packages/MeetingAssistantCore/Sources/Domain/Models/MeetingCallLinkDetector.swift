import Foundation

public enum MeetingReminderOccurrenceKey {
    public static func make(for event: MeetingCalendarEventSnapshot) -> String {
        "\(event.eventIdentifier)-\(event.startDate.timeIntervalSince1970)"
    }
}

public enum MeetingCallLinkDetector {
    private static let knownCallDomains = [
        "meet.google.com",
        "zoom.us",
        "teams.microsoft.com",
        "webex.com",
        "whereby.com",
        "jitsi",
        "bluejeans.com",
        "gotomeeting.com",
        "join.me",
        "discord.com",
        "discord.gg"
    ]

    public static func containsKnownMeetingLink(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return knownCallDomains.contains(where: normalized.contains)
    }

    public static func resolveJoinURL(from searchableValues: [String]) -> URL? {
        for value in searchableValues {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let directURL = URL(string: trimmed),
               directURL.scheme?.hasPrefix("http") == true,
               containsKnownMeetingLink(trimmed)
            {
                return directURL
            }

            guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
                continue
            }
            let range = NSRange(trimmed.startIndex ..< trimmed.endIndex, in: trimmed)
            for match in detector.matches(in: trimmed, range: range) {
                guard let url = match.url, containsKnownMeetingLink(url.absoluteString) else { continue }
                return url
            }
        }
        return nil
    }
}

public extension MeetingCalendarEventSnapshot {
    var joinURL: URL? {
        MeetingCallLinkDetector.resolveJoinURL(from: [location, notes].compactMap(\.self))
    }
}
