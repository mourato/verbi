import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

struct MeetingNotesPanelSettingsSection: View {
    @ObservedObject var settings: AppSettingsStore
    @StateObject private var shortcutViewModel = MeetingNotesShortcutSettingsViewModel()
    @State private var availableThemes: [String] = []

    var body: some View {
        Section {
            Toggle("settings.meetings.notes_panel.hotkey_enabled".localized, isOn: $settings.meetingNotesHotkeyEnabled)
                .toggleStyle(.switch)

            if settings.meetingNotesHotkeyEnabled {
                HStack(alignment: .top, spacing: 12) {
                    Text("settings.meetings.notes_panel.shortcut".localized)
                        .font(.body)

                    Spacer()

                    DSModifierShortcutEditor(
                        shortcut: $shortcutViewModel.meetingNotesShortcutDefinition,
                        conflictMessage: shortcutViewModel.meetingNotesShortcutConflictMessage,
                        showsTitle: false,
                        maxInputWidth: AppDesignSystem.Layout.maxCompactTextFieldWidth,
                    )
                }
            }

            Toggle("settings.meetings.notes_panel.translucent".localized, isOn: $settings.meetingNotesTranslucentPanel)
                .toggleStyle(.switch)
            Toggle("settings.meetings.notes_panel.all_spaces".localized, isOn: $settings.meetingNotesShowOnAllSpaces)
                .toggleStyle(.switch)
            Toggle("settings.meetings.notes_panel.hide_from_capture".localized, isOn: $settings.meetingNotesHideFromScreenCapture)
                .toggleStyle(.switch)
            Toggle("settings.meetings.notes_panel.auto_height".localized, isOn: $settings.meetingNotesAutoSizeHeight)
                .toggleStyle(.switch)

            Picker("settings.meetings.notes_panel.text_size".localized, selection: $settings.meetingNotesTextSize) {
                ForEach(Array(AppSettingsStore.meetingNotesTextSizeRange), id: \.self) { size in
                    Text("\(size)").tag(size)
                }
            }
            .pickerStyle(.menu)

            Picker("settings.meetings.notes_panel.theme".localized, selection: $settings.meetingNotesEditorTheme) {
                Text("settings.meetings.notes_panel.theme_default".localized).tag("")
                ForEach(availableThemes, id: \.self) { theme in
                    Text(theme).tag(theme)
                }
            }
            .pickerStyle(.menu)
        } header: {
            SettingsFormSectionHeader(title: "settings.meetings.notes_panel.title".localized, icon: "note.text")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.meetings.notes_panel.desc".localized)
                Text("settings.meetings.notes_panel.theme_footer".localized)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .onAppear {
            MeetingNotesEditorThemeResolver.ensureThemesDirectoryExists()
            availableThemes = MeetingNotesEditorThemeResolver.availableThemeNames()
        }
    }
}

#if DEBUG
#Preview {
    Form {
        MeetingNotesPanelSettingsSection(settings: .shared)
    }
    .frame(width: 620)
}
#endif
