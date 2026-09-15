import Foundation

// MARK: - Onboarding Step

public enum OnboardingStep: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case welcome
    case permissions
    case shortcuts
    case downloadModels
    case meetingRecording
    case completion

    public var id: Int {
        rawValue
    }

    /// 1-based index for display purposes.
    public var index: Int {
        rawValue + 1
    }

    /// Whether this step can be skipped.
    public var isSkippable: Bool {
        switch self {
        case .permissions, .shortcuts, .downloadModels, .meetingRecording: true
        case .welcome, .completion: false
        }
    }
}

// MARK: - Onboarding Meeting Recording Readiness

public struct OnboardingMeetingRecordingReadiness: Equatable, Sendable {
    public let microphoneGranted: Bool
    public let screenRecordingGranted: Bool
    public let transcriptionModelReady: Bool
    public let isMeetingRecordingEnabled: Bool
    public let wasSkipped: Bool

    public init(
        microphoneGranted: Bool,
        screenRecordingGranted: Bool,
        transcriptionModelReady: Bool,
        isMeetingRecordingEnabled: Bool,
        wasSkipped: Bool
    ) {
        self.microphoneGranted = microphoneGranted
        self.screenRecordingGranted = screenRecordingGranted
        self.transcriptionModelReady = transcriptionModelReady
        self.isMeetingRecordingEnabled = isMeetingRecordingEnabled
        self.wasSkipped = wasSkipped
    }

    public var prerequisitesSatisfied: Bool {
        microphoneGranted && screenRecordingGranted && transcriptionModelReady
    }

    public var isReadyForMeetings: Bool {
        prerequisitesSatisfied && isMeetingRecordingEnabled && !wasSkipped
    }

    public var completionSubtitleKey: String {
        isReadyForMeetings
            ? "onboarding.completion.subtitle.meetings_ready"
            : "onboarding.completion.subtitle.dictation_ready"
    }
}

// MARK: - Onboarding Permission Type

public enum OnboardingPermissionType: CaseIterable, Hashable, Sendable {
    case microphone
    case screenRecording
    case accessibility
}

// MARK: - Onboarding Permission Item

public struct OnboardingPermissionItem: Hashable, Sendable {
    public let type: OnboardingPermissionType
    public let titleKey: String
    public let descriptionKey: String
    public let iconName: String

    public init(
        type: OnboardingPermissionType,
        titleKey: String,
        descriptionKey: String,
        iconName: String
    ) {
        self.type = type
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.iconName = iconName
    }

    /// All permissions required for onboarding.
    public static var allPermissions: [OnboardingPermissionItem] {
        [
            OnboardingPermissionItem(
                type: .microphone,
                titleKey: "onboarding.permissions.microphone.title",
                descriptionKey: "onboarding.permissions.microphone.desc",
                iconName: "mic.fill"
            ),
            OnboardingPermissionItem(
                type: .screenRecording,
                titleKey: "onboarding.permissions.screen_recording.title",
                descriptionKey: "onboarding.permissions.screen_recording.desc",
                iconName: "rectangle.on.rectangle"
            ),
            OnboardingPermissionItem(
                type: .accessibility,
                titleKey: "onboarding.permissions.accessibility.title",
                descriptionKey: "onboarding.permissions.accessibility.desc",
                iconName: "figure.wave"
            )
        ]
    }
}

// MARK: - Onboarding Shortcut Type

public enum OnboardingShortcutType: CaseIterable, Hashable, Sendable {
    case dictation
    case meeting
    case assistant

    public var titleKey: String {
        switch self {
        case .dictation: "onboarding.shortcuts.dictation"
        case .meeting: "onboarding.shortcuts.meeting"
        case .assistant: "onboarding.shortcuts.assistant"
        }
    }
}

// MARK: - Onboarding Shortcut Item

public struct OnboardingShortcutItem: Hashable, Sendable {
    public let type: OnboardingShortcutType
    public let titleKey: String
    public let descriptionKey: String

    public init(type: OnboardingShortcutType) {
        self.type = type
        titleKey = type.titleKey
        descriptionKey = "onboarding.shortcuts.use_default"
    }

    /// All shortcuts configurable during onboarding.
    public static var allShortcuts: [OnboardingShortcutItem] {
        OnboardingShortcutType.allCases.map { OnboardingShortcutItem(type: $0) }
    }
}
