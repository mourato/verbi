import MeetingAssistantCoreCommon
import SwiftUI

public struct SettingsDestination: Equatable, Sendable {
    public let section: SettingsSection
    public let activityPendingSheet: ActivityPendingSheet?
    public let systemRoute: SystemSettingsRoute?
    public let modesSubroute: DictationStyleRoute?
    public let expandProtectedApps: Bool

    public init(
        section: SettingsSection,
        activityPendingSheet: ActivityPendingSheet? = nil,
        systemRoute: SystemSettingsRoute? = nil,
        modesSubroute: DictationStyleRoute? = nil,
        expandProtectedApps: Bool = false
    ) {
        self.section = section
        self.activityPendingSheet = activityPendingSheet
        self.systemRoute = systemRoute
        self.modesSubroute = modesSubroute
        self.expandProtectedApps = expandProtectedApps
    }
}

// MARK: - Settings Section Enum

public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case metrics
    case dictation
    case modes
    case assistant
    case integrations
    case meetings
    case history
    case transcriptions
    case general
    case models
    case vocabulary
    case dictionary
    case enhancements
    case audio
    case permissions
    case activity
    case intelligence
    case system
    case updates

    public var id: String {
        rawValue
    }

    public static let primarySections: [SettingsSection] = [
        .activity,
        .modes,
        .meetings,
        .history,
        .dictionary
    ]

    public static let settingsSections: [SettingsSection] = [
        .system
    ]

    public static var visibleSections: [SettingsSection] {
        [
            .activity,
            .modes,
            .meetings,
            .history,
            .dictionary,
            .system
        ]
    }

    public var isLegacyRedirect: Bool {
        switch self {
        case .metrics, .transcriptions, .models, .enhancements, .vocabulary, .permissions, .general, .intelligence, .audio, .dictation, .assistant, .integrations, .updates:
            true
        case .activity, .modes, .meetings, .history, .dictionary, .system:
            false
        }
    }

    public var visibleSection: SettingsSection {
        destination.section
    }

    public var destination: SettingsDestination {
        switch self {
        case .metrics:
            SettingsDestination(
                section: .activity,
                activityPendingSheet: .performance
            )
        case .transcriptions:
            SettingsDestination(section: .history)
        case .models:
            SettingsDestination(section: .system, systemRoute: .models)
        case .vocabulary, .dictionary:
            SettingsDestination(section: .dictionary)
        case .enhancements:
            SettingsDestination(section: .modes)
        case .permissions:
            SettingsDestination(section: .system)
        case .general:
            SettingsDestination(section: .system)
        case .audio:
            SettingsDestination(section: .system, systemRoute: .sound)
        case .intelligence:
            SettingsDestination(section: .system, systemRoute: .models)
        case .dictation:
            SettingsDestination(section: .modes)
        case .assistant:
            SettingsDestination(section: .modes, modesSubroute: .assistant)
        case .integrations:
            SettingsDestination(section: .modes, modesSubroute: .integrations)
        case .updates:
            SettingsDestination(section: .system, systemRoute: .updates)
        case .activity, .modes, .meetings, .history, .system:
            SettingsDestination(section: self)
        }
    }

    public static func resolvedVisibleSection(for rawValue: String) -> SettingsSection? {
        resolvedDestination(for: rawValue)?.section
    }

    public static func resolvedDestination(for rawValue: String) -> SettingsDestination? {
        SettingsSection(rawValue: rawValue)?.destination
    }

    public var title: String {
        switch self {
        case .metrics: "settings.section.metrics".localized
        case .general: "settings.section.general".localized
        case .dictation: "settings.section.dictation".localized
        case .modes: "settings.section.modes".localized
        case .meetings: "settings.section.meetings".localized
        case .audio: "settings.section.audio".localized
        case .assistant: "settings.section.assistant".localized
        case .integrations: "settings.section.integrations".localized
        case .history, .transcriptions: "settings.section.history".localized
        case .models: "settings.section.models".localized
        case .vocabulary: "settings.section.vocabulary".localized
        case .dictionary: "settings.section.dictionary".localized
        case .enhancements: "settings.section.ai".localized
        case .permissions: "settings.section.permissions".localized
        case .activity: "settings.section.activity".localized
        case .intelligence: "settings.section.intelligence".localized
        case .system: "settings.section.settings".localized
        case .updates: "settings.section.updates".localized
        }
    }

    public var icon: String {
        switch self {
        case .metrics: "chart.pie.fill"
        case .general: "gearshape.2"
        case .dictation: "microphone"
        case .modes: "mic"
        case .meetings: "bubble.left.and.bubble.right"
        case .audio: "speaker.wave.2"
        case .assistant: "sparkle"
        case .integrations: "puzzlepiece.extension"
        case .history, .transcriptions: "clock"
        case .models: "cpu"
        case .vocabulary: "character.book.closed"
        case .dictionary: "character.book.closed"
        case .enhancements: "sparkles"
        case .permissions: "checkmark.shield"
        case .activity: "chart.pie"
        case .intelligence: "sparkles"
        case .system: "gearshape.2"
        case .updates: "arrow.down.circle"
        }
    }

    /// The filled variant used to communicate selection in the settings sidebar.
    public var selectedSidebarIcon: String {
        switch self {
        case .activity: "chart.pie.fill"
        case .modes: "mic.fill"
        case .meetings: "bubble.left.and.bubble.right.fill"
        case .history: "clock.fill"
        case .dictionary: "character.book.closed.fill"
        case .system: "gearshape.2.fill"
        case .updates: "arrow.down.circle.fill"
        default: icon
        }
    }

    /// Compatibility color retained for existing callers; sidebar rows no longer render badge plates.
    public var badgeColor: Color {
        switch self {
        case .activity, .metrics:
            .blue
        case .modes, .dictation, .assistant, .integrations:
            .purple
        case .meetings:
            .green
        case .history, .transcriptions:
            .orange
        case .dictionary, .vocabulary:
            .indigo
        case .system, .general, .permissions, .audio, .intelligence, .models, .enhancements:
            Color(nsColor: .systemGray)
        case .updates:
            .blue
        }
    }

    /// Compatibility gradient retained for existing callers; sidebar rows no longer render badge plates.
    public var badgeGradient: LinearGradient {
        LinearGradient(
            colors: [badgeColor, badgeColor.opacity(0.88)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
