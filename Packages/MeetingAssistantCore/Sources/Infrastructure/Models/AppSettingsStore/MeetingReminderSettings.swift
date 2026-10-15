import Foundation
import MeetingAssistantCoreDomain
import SwiftUI

public extension AppSettingsStore {
    enum MeetingReminderLeadMinutes: Int, CaseIterable, Sendable {
        case off = 0
        case five = 5
        case ten = 10
        case fifteen = 15
        case thirty = 30

        public var localizedTitle: String {
            switch self {
            case .off:
                "settings.meetings.reminders.lead_minutes.off".localized
            case .five:
                "settings.meetings.reminders.lead_minutes.5".localized
            case .ten:
                "settings.meetings.reminders.lead_minutes.10".localized
            case .fifteen:
                "settings.meetings.reminders.lead_minutes.15".localized
            case .thirty:
                "settings.meetings.reminders.lead_minutes.30".localized
            }
        }
    }

    static func meetingReminderOccurrenceKey(for event: MeetingCalendarEventSnapshot) -> String {
        MeetingReminderOccurrenceKey.make(for: event)
    }

    func meetingReminderDismissedOccurrenceKeys() -> Set<String> {
        Self.loadDecoded(Set<String>.self, forKey: Keys.meetingReminderDismissedEventKeys) ?? []
    }

    func dismissMeetingReminderOccurrence(for event: MeetingCalendarEventSnapshot) {
        var keys = meetingReminderDismissedOccurrenceKeys()
        keys.insert(Self.meetingReminderOccurrenceKey(for: event))
        save(keys, forKey: Keys.meetingReminderDismissedEventKeys)
    }

    func clearMeetingReminderDismissedOccurrenceKeys() {
        UserDefaults.standard.removeObject(forKey: Keys.meetingReminderDismissedEventKeys)
    }

    func resetMeetingReminderDefaults() {
        meetingDetectionMode = .notify
        UserDefaults.standard.removeObject(forKey: Keys.meetingDetectionMode)
        UserDefaults.standard.removeObject(forKey: Keys.meetingDetectionModeMigrated)
        meetingRemindersEnabled = true
        meetingReminderLeadMinutes = 15
        meetingReminderOverlayLeadSeconds = 0
        meetingReminderOverlayEnabled = true
        meetingReminderAlertSoundEnabled = false
        meetingReminderMirrorAllScreens = false
        clearMeetingReminderDismissedOccurrenceKeys()
    }
}
