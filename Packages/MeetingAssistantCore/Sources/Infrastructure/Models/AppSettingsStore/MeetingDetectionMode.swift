import Foundation
import MeetingAssistantCoreCommon

public enum MeetingDetectionMode: String, CaseIterable, Codable, Sendable {
    case off
    case notify
    case auto

    public var localizedTitle: String {
        switch self {
        case .off:
            "settings.meetings.detection_mode.off".localized
        case .notify:
            "settings.meetings.detection_mode.notify".localized
        case .auto:
            "settings.meetings.detection_mode.auto".localized
        }
    }
}

// MARK: - Migration Helper

public extension AppSettingsStore {
    /// Migrates legacy meeting reminder and auto-record settings into meetingDetectionMode.
    @discardableResult
    static func migrateMeetingDetectionModeIfNeeded(defaults: UserDefaults = .standard) -> MeetingDetectionMode {
        if defaults.bool(forKey: Keys.meetingDetectionModeMigrated) {
            if let raw = defaults.string(forKey: Keys.meetingDetectionMode),
               let mode = MeetingDetectionMode(rawValue: raw)
            {
                return mode
            }
            return .notify
        }

        if let raw = defaults.string(forKey: Keys.meetingDetectionMode),
           let mode = MeetingDetectionMode(rawValue: raw)
        {
            defaults.set(true, forKey: Keys.meetingDetectionModeMigrated)
            return mode
        }

        let hasAutoStart = defaults.object(forKey: Keys.autoStartRecording) != nil
        let hasTranscription = defaults.object(forKey: Keys.isMeetingTranscriptionEnabled) != nil
        let hasReminders = defaults.object(forKey: Keys.meetingRemindersEnabled) != nil

        let mode: MeetingDetectionMode
        if !hasAutoStart, !hasTranscription, !hasReminders {
            mode = .notify
        } else {
            let autoStart = defaults.bool(forKey: Keys.autoStartRecording)
            let transcriptionEnabled = defaults.bool(forKey: Keys.isMeetingTranscriptionEnabled)
            let remindersEnabled = defaults.bool(forKey: Keys.meetingRemindersEnabled)

            if autoStart, transcriptionEnabled {
                mode = .auto
            } else if remindersEnabled {
                mode = .notify
            } else {
                mode = .off
            }
        }

        defaults.set(mode.rawValue, forKey: Keys.meetingDetectionMode)
        defaults.set(true, forKey: Keys.meetingDetectionModeMigrated)
        return mode
    }
}
