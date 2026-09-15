// MeetingEntity - Domain Entity pura sem dependências de UI/frameworks

import Foundation
import MeetingAssistantCoreCommon

/// Representa um aplicativo de reunião que pode ser detectado.
public enum DomainMeetingApp: String, CaseIterable, Codable, Sendable {
    case googleMeet = "google-meet"
    case microsoftTeams = "microsoft-teams"
    case discord
    case slack
    case whatsApp = "whatsapp"
    case zoom
    case manualMeeting = "manual-meeting"
    case importedFile = "imported-file"
    case unknown

    /// Bundle identifiers para detectar este app.
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

    /// Padrões de título de janela para detectar reunião em andamento.
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

    public var iconName: String {
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

    public var supportsMeetingConversation: Bool {
        self != .unknown && self != .importedFile
    }
}

/// Representa uma reunião ativa ou completada.
public struct MeetingEntity: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let app: DomainMeetingApp
    public let capturePurpose: CapturePurpose
    public let appBundleIdentifier: String?
    public let appDisplayName: String?
    public var title: String?
    public var linkedCalendarEvent: MeetingCalendarEventSnapshot?
    public let startTime: Date
    public var endTime: Date?
    public var audioFilePath: String?

    public init(
        id: UUID = UUID(),
        app: DomainMeetingApp,
        capturePurpose: CapturePurpose? = nil,
        appBundleIdentifier: String? = nil,
        appDisplayName: String? = nil,
        title: String? = nil,
        linkedCalendarEvent: MeetingCalendarEventSnapshot? = nil,
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
        self.startTime = startTime
        self.endTime = endTime
        self.audioFilePath = audioFilePath
    }

    /// Duração da reunião em segundos.
    public var duration: TimeInterval {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    /// String de duração formatada (ex: "1h 23m").
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

    public var appIconName: String {
        app.iconName
    }

    public var supportsMeetingConversation: Bool {
        capturePurpose == .meeting
    }

    public var preferredTitle: String? {
        guard supportsMeetingConversation else { return nil }

        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }

        if let calendarTitle = linkedCalendarEvent?.trimmedTitle, !calendarTitle.isEmpty {
            return calendarTitle
        }

        return nil
    }

    public func sanitizedForPersistence() -> MeetingEntity {
        guard !supportsMeetingConversation else { return self }

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
}
