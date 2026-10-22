import Foundation
import MeetingAssistantCoreCommon

/// Represents a meeting app that can be detected.
public enum CaptureOrigin: String, CaseIterable, Codable, Sendable {
    case googleMeet = "google-meet"
    case microsoftTeams = "microsoft-teams"
    case discord
    case slack
    case whatsApp = "whatsapp"
    case zoom
    case manualMeeting = "manual-meeting"
    case importedFile = "imported-file"
    case unknown

    /// Bundle identifiers to detect this app.
    public var bundleIdentifiers: [String] {
        switch self {
        case .googleMeet:
            ["com.google.Chrome", "com.apple.Safari", "com.microsoft.edgemac"]
        case .microsoftTeams:
            ["com.microsoft.teams", "com.microsoft.teams2"]
        case .discord:
            ["com.hnc.Discord"]
        case .slack:
            ["com.tinyspeck.slackmacgap"]
        case .whatsApp:
            ["net.whatsapp.WhatsApp"]
        case .zoom:
            ["us.zoom.xos"]
        case .manualMeeting, .importedFile, .unknown:
            []
        }
    }

    /// Window title patterns to detect meeting in progress.
    public var windowTitlePatterns: [String] {
        switch self {
        case .googleMeet:
            ["meet.google.com", "Google Meet"]
        case .microsoftTeams:
            ["Microsoft Teams", "| Teams"]
        case .discord:
            []
        case .slack:
            ["Huddle", "Call"]
        case .whatsApp:
            []
        case .zoom:
            ["Zoom Meeting", "Zoom Webinar"]
        case .manualMeeting, .importedFile, .unknown:
            []
        }
    }

    public var displayName: String {
        switch self {
        case .googleMeet: "Google Meet"
        case .microsoftTeams: "Microsoft Teams"
        case .discord: "Discord"
        case .slack: "Slack"
        case .whatsApp: "WhatsApp"
        case .zoom: "Zoom"
        case .manualMeeting: "meeting.app.manual".localized
        case .importedFile: "meeting.app.imported".localized
        case .unknown: "meeting.app.unknown".localized
        }
    }

    public var icon: String {
        switch self {
        case .googleMeet: "video.fill"
        case .microsoftTeams: "person.3.fill"
        case .discord: "bubble.left.and.bubble.right.fill"
        case .slack: "number.square.fill"
        case .whatsApp: "phone.fill"
        case .zoom: "video.circle.fill"
        case .manualMeeting: "person.2.wave.2"
        case .importedFile: "doc.badge.arrow.up"
        case .unknown: "questionmark.circle"
        }
    }

    /// Compatibility accessor used by the former domain entity projection.
    public var iconName: String {
        icon
    }

}

/// Represents an active or completed meeting.
public struct CaptureSession: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let app: CaptureOrigin
    public let capturePurpose: CapturePurpose
    public let appBundleIdentifier: String?
    public let appDisplayName: String?
    public var title: String?
    public var linkedCalendarEvent: MeetingCalendarEventSnapshot?
    public var type: SummaryStrategy = .general
    public var state: CaptureState = .idle
    public let startTime: Date
    public var endTime: Date?
    public var audioFilePath: String?

    public init(
        id: UUID = UUID(),
        app: CaptureOrigin,
        capturePurpose: CapturePurpose? = nil,
        appBundleIdentifier: String? = nil,
        appDisplayName: String? = nil,
        title: String? = nil,
        linkedCalendarEvent: MeetingCalendarEventSnapshot? = nil,
        type: SummaryStrategy = .general,
        state: CaptureState = .idle,
        startTime: Date = Date(),
        endTime: Date? = nil,
        audioFilePath: String? = nil
    ) {
        self.id = id
        self.app = app
        self.capturePurpose = capturePurpose ?? CapturePurpose.defaultValue(for: app)
        self.appBundleIdentifier = appBundleIdentifier
        self.appDisplayName = appDisplayName
        self.title = title
        self.linkedCalendarEvent = linkedCalendarEvent
        self.type = type
        self.state = state
        self.startTime = startTime
        self.endTime = endTime
        self.audioFilePath = audioFilePath
    }

    /// Duration of the meeting in seconds.
    public var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    /// Formatted duration string (e.g., "1h 23m").
    public var formattedDuration: String {
        let seconds = Int(duration)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    public var appName: String {
        let trimmed = appDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : app.displayName
    }

    public var appIcon: String {
        app.icon
    }

    public var preferredTitle: String? {
        guard capturePurpose.supportsMeetingConversation else { return nil }

        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }

        if let calendarTitle = linkedCalendarEvent?.trimmedTitle, !calendarTitle.isEmpty {
            return calendarTitle
        }

        return nil
    }

    public func sanitizedForPersistence() -> CaptureSession {
        guard !capturePurpose.supportsMeetingConversation else { return self }

        var sanitized = self
        sanitized.title = nil
        sanitized.linkedCalendarEvent = nil
        return sanitized
    }

    public var resolvedTitle: String {
        if let preferredTitle {
            return preferredTitle
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return "export.header.meeting_title".localized(
            with: app.displayName,
            formatter.string(from: startTime)
        )
    }

    /// Indicates if the meeting represents a dictation (unknown app source).
    public var isDictation: Bool {
        capturePurpose == .dictation
    }
}

/// Compatibility name for the pre-phase-3 capture origin type.
@available(*, deprecated, renamed: "CaptureOrigin")
public typealias MeetingApp = CaptureOrigin

/// Compatibility name for the pre-phase-3 capture session type.
@available(*, deprecated, renamed: "CaptureSession")
public typealias Meeting = CaptureSession
