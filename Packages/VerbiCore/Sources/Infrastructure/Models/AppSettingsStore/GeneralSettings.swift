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

    var recordingsDirectory: String {
        get { UserDefaults.standard.string(forKey: GeneralKeys.recordingsDirectory) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.recordingsDirectory) }
    }

    var autoStartRecording: Bool {
        get { UserDefaults.standard.bool(forKey: GeneralKeys.autoStartRecording) }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.autoStartRecording) }
    }

    var showSettingsOnLaunch: Bool {
        get { UserDefaults.standard.bool(forKey: GeneralKeys.showSettingsOnLaunch) }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.showSettingsOnLaunch) }
    }

    var isSettingsSidebarVisible: Bool {
        get {
            if UserDefaults.standard.object(forKey: GeneralKeys.isSettingsSidebarVisible) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: GeneralKeys.isSettingsSidebarVisible)
        }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.isSettingsSidebarVisible) }
    }

    var autoCopyTranscriptionToClipboard: Bool {
        get {
            if UserDefaults.standard.object(forKey: GeneralKeys.autoCopyTranscriptionToClipboard) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: GeneralKeys.autoCopyTranscriptionToClipboard)
        }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.autoCopyTranscriptionToClipboard) }
    }

    var autoPasteTranscriptionToActiveApp: Bool {
        get { UserDefaults.standard.bool(forKey: GeneralKeys.autoPasteTranscriptionToActiveApp) }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.autoPasteTranscriptionToActiveApp) }
    }

    var launchAtLogin: Bool {
        get { UserDefaults.standard.bool(forKey: GeneralKeys.launchAtLogin) }
        set { UserDefaults.standard.set(newValue, forKey: GeneralKeys.launchAtLogin) }
    }

    enum PostProcessingKeys {
        public static let audioFormat = "audioFormat"
        public static let shouldMergeAudioFiles = "shouldMergeAudioFiles"
    }

    enum AudioFormat: String, CaseIterable, Codable, Sendable {
        case m4a
        case wav

        public var fileExtension: String {
            switch self {
            case .m4a: "m4a"
            case .wav: "wav"
            }
        }

        public func temporaryRecordingURL(prefix: String) -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("\(prefix)-\(UUID().uuidString)")
                .appendingPathExtension(fileExtension)
        }

        public var displayName: String {
            switch self {
            case .m4a: "AAC (.m4a)"
            case .wav: "WAV (Linear PCM)"
            }
        }
    }

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
}
