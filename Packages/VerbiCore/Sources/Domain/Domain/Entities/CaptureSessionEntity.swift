// CaptureSessionEntity - Domain Entity pura sem dependências de UI/frameworks

import Foundation
import VerbiCoreCommon

/// Representa uma reunião ativa ou completada.
public struct CaptureSessionEntity: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let app: CaptureOrigin
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
        app: CaptureOrigin,
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
        guard let trimmed, !trimmed.isEmpty else {
            return app.displayName
        }
        return trimmed
    }

    public var appIconName: String {
        app.iconName
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

    public func sanitizedForPersistence() -> CaptureSessionEntity {
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
}

/// Compatibility name for the duplicate pre-phase-3 domain origin type.
@available(*, deprecated, renamed: "CaptureOrigin")
public typealias DomainMeetingApp = CaptureOrigin

/// Compatibility name for the pre-phase-3 domain capture session entity.
@available(*, deprecated, renamed: "CaptureSessionEntity")
public typealias MeetingEntity = CaptureSessionEntity
