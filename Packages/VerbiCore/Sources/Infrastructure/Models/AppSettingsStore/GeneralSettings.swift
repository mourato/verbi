import Foundation

public extension AppSettingsStore {
    private enum GeneralKeys {
        static let recordingsDirectory = "recordingsDirectory"
        static let autoStartRecording = "autoStartRecording"
        static let showSettingsOnLaunch = "showSettingsOnLaunch"
        static let isSettingsSidebarVisible = "isSettingsSidebarVisible"
        static let autoCopyTranscriptionToClipboard = "autoCopyTranscriptionToClipboard"
        static let autoPasteTranscriptionToActiveApp = "autoPasteTranscriptionToActiveApp"
        static let launchAtLogin = "launchAtLogin"
    }

    enum AutomaticMeetingRecordingConfirmationDelay: Int, CaseIterable, Codable, Sendable {
        case seconds3 = 3
        case seconds6 = 6
        case seconds9 = 9

        public var localizedTitle: String {
            switch self {
            case .seconds3:
                "settings.general.auto_start_confirmation_delay.3".localized
            case .seconds6:
                "settings.general.auto_start_confirmation_delay.6".localized
            case .seconds9:
                "settings.general.auto_start_confirmation_delay.9".localized
            }
        }

        public var timeInterval: TimeInterval {
            TimeInterval(rawValue)
        }
    }

    /// Configured path for saving recordings.
    /// If empty or invalid, services should fallback to the default Application Support directory.
    var recordingsDirectory: String {
        get { UserDefaults.standard.string(forKey: GeneralKeys.recordingsDirectory) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.recordingsDirectory) }
    }

    /// Whether to automatically start recording when a meeting is detected.
    var autoStartRecording: Bool {
        get { UserDefaults.standard.bool(forKey: GeneralKeys.autoStartRecording) }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.autoStartRecording) }
    }

    /// Whether to show the settings window on app launch.
    var showSettingsOnLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: GeneralKeys.showSettingsOnLaunch) }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.showSettingsOnLaunch) }
    }

    /// Whether the Settings sidebar is currently visible.
    var isSettingsSidebarVisible: Bool {
        get {
            if UserDefaults.standard.object(forKey: GeneralKeys.isSettingsSidebarVisible) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: GeneralKeys.isSettingsSidebarVisible)
        }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.isSettingsSidebarVisible) }
    }

    /// Whether to automatically copy the latest transcription to the clipboard.
    /// Default: true
    var autoCopyTranscriptionToClipboard: Bool {
        get {
            if UserDefaults.standard.object(forKey: GeneralKeys.autoCopyTranscriptionToClipboard) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: GeneralKeys.autoCopyTranscriptionToClipboard)
        }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.autoCopyTranscriptionToClipboard) }
    }

    /// Whether to automatically paste the latest transcription into the active app.
    /// Default: false
    var autoPasteTranscriptionToActiveApp: Bool {
        get { UserDefaults.standard.bool(forKey: GeneralKeys.autoPasteTranscriptionToActiveApp) }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.autoPasteTranscriptionToActiveApp) }
    }

    /// Whether the app should launch automatically at login.
    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: GeneralKeys.launchAtLogin) }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.launchAtLogin) }
    }

    // MARK: - Post-Processing Extension

    enum PostProcessingKeys {
        public static let audioFormat = "audioFormat"
        public static let shouldMergeAudioFiles = "shouldMergeAudioFiles"
    }

    /// Supported audio formats for recording.
    enum AudioFormat: String, CaseIterable, Codable, Sendable {
        case m4a
        case wav

        public var fileExtension: String {
            switch self {
            case .m4a: "m4a"
            case .wav: "wav"
            }
        }

        public var displayName: String {
            switch self {
            case .m4a: "AAC (.m4a)"
            case .wav: "WAV (Linear PCM)"
            }
        }
    }

    /// How Verbi should handle currently playing media for microphone-only recordings.
    enum RecordingMediaHandlingMode: String, CaseIterable, Codable, Sendable {
        case none
        case duckAudio
        case pauseMedia

        public var displayNameKey: String {
            switch self {
            case .none: "settings.general.recording_media_handling.none"
            case .duckAudio: "settings.general.recording_media_handling.duck_audio"
            case .pauseMedia: "settings.general.recording_media_handling.pause_media"
            }
        }

        public var usesDucking: Bool {
            switch self {
            case .none:
                false
            case .duckAudio, .pauseMedia:
                true
            }
        }

        public var prefersPauseBeforeFallback: Bool {
            switch self {
            case .pauseMedia:
                true
            case .none, .duckAudio:
                false
            }
        }
    }

    // Moved to main class body to support @Published storage
}
