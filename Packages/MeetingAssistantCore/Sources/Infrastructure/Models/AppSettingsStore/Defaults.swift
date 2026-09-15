import Foundation
import MeetingAssistantCoreDomain

// MARK: - Default Values

public extension AppSettingsStore {
    /// Default list of apps that should force Markdown formatting for dictation.
    static let defaultMarkdownTargetBundleIdentifiers: [String] = [
        "abnerworks.Typora",
        "com.microsoft.VSCode",
        "com.uranusjr.macdown",
        "md.obsidian",
        "net.shinyfrog.bear"
    ]

    /// Default per-app dictation rules.
    static let defaultDictationAppRules: [DictationAppRule] = defaultMarkdownTargetBundleIdentifiers.map {
        DictationAppRule(bundleIdentifier: $0, forceMarkdownOutput: true, outputLanguage: .original)
    }

    /// Default list of dictation styles.
    static let defaultDictationModeID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!

    static var defaultDictationStyles: [DictationStyle] {
        [
            defaultDictationStyle(
                contextAwarenessEnabled: false,
                includeClipboard: false,
                includeWindowOCR: false,
                includeAccessibilityText: true,
                redactSensitiveData: true,
                dictationSelection: .default
            )
        ]
    }

    /// Default list of websites that should force Markdown formatting for dictation.
    static let defaultMarkdownWebTargets: [WebContextTarget] = []

    /// Default list of browsers used for web target matching.
    static let defaultWebTargetBrowserBundleIdentifiers: [String] = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac"
    ]

    /// Default list of apps monitored to start/stop meeting recordings.
    static let defaultMonitoredMeetingBundleIdentifiers: [String] = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.microsoft.edgemac",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "com.hnc.Discord",
        "com.tinyspeck.slackmacgap",
        "net.whatsapp.WhatsApp",
        "us.zoom.xos"
    ]

    /// Default list of web meeting targets detected via browser URL matching.
    static let defaultWebMeetingTargets: [WebMeetingTarget] = [
        WebMeetingTarget(
            app: .googleMeet,
            displayName: "Google Meet",
            urlPatterns: ["meet.google.com"],
            browserBundleIdentifiers: ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac"]
        ),
        WebMeetingTarget(
            app: .microsoftTeams,
            displayName: "Microsoft Teams",
            urlPatterns: ["teams.microsoft.com"],
            browserBundleIdentifiers: ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac"]
        ),
        WebMeetingTarget(
            app: .zoom,
            displayName: "Zoom",
            urlPatterns: ["zoom.us/j", "zoom.us/wc"],
            browserBundleIdentifiers: ["com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac"]
        )
    ]

    static let defaultShortcutDoubleTapIntervalMilliseconds: Double = 350
    static let shortcutDoubleTapIntervalRangeMilliseconds: ClosedRange<Double> = 150 ... 1000
    static let defaultAudioDuckingLevelPercent: Int = 30
    static let defaultMeetingNotesTextSize = 15
    static let meetingNotesTextSizeRange = 12 ... 24

    static func normalizedMeetingNotesTextSize(_ value: Int) -> Int {
        min(max(value, meetingNotesTextSizeRange.lowerBound), meetingNotesTextSizeRange.upperBound)
    }
}
