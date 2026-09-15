import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

struct MeetingSettingsRemindersSection: View {
    @ObservedObject var settings: AppSettingsStore

    var body: some View {
        Section {
            Toggle("settings.meetings.reminders.enabled".localized, isOn: $settings.meetingRemindersEnabled)
                .toggleStyle(.switch)
            Picker("settings.meetings.reminders.lead_minutes".localized, selection: $settings.meetingReminderLeadMinutes) {
                ForEach(AppSettingsStore.MeetingReminderLeadMinutes.allCases, id: \.rawValue) { option in
                    Text(option.localizedTitle).tag(option.rawValue)
                }
            }
            .pickerStyle(.menu)
            .disabled(!settings.meetingRemindersEnabled)
            Toggle("settings.meetings.reminders.overlay_enabled".localized, isOn: $settings.meetingReminderOverlayEnabled)
                .toggleStyle(.switch)
                .disabled(!settings.meetingRemindersEnabled)
            Stepper(
                value: $settings.meetingReminderOverlayLeadSeconds,
                in: 0 ... 300,
                step: 15
            ) {
                Text(
                    "settings.meetings.reminders.overlay_lead_seconds".localized(
                        with: settings.meetingReminderOverlayLeadSeconds
                    )
                )
            }
            .disabled(!settings.meetingRemindersEnabled || !settings.meetingReminderOverlayEnabled)
            Toggle("settings.meetings.reminders.alert_sound".localized, isOn: $settings.meetingReminderAlertSoundEnabled)
                .toggleStyle(.switch)
                .disabled(!settings.meetingRemindersEnabled)
            Toggle("settings.meetings.reminders.mirror_all_screens".localized, isOn: $settings.meetingReminderMirrorAllScreens)
                .toggleStyle(.switch)
                .disabled(!settings.meetingRemindersEnabled || !settings.meetingReminderOverlayEnabled)
        } header: {
            SettingsFormSectionHeader(title: "settings.meetings.reminders.title".localized, icon: "bell.badge.fill")
        } footer: {
            Text("settings.meetings.reminders.description".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
