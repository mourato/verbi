import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Shortcuts Settings Tab

/// Single home for the app's global keyboard shortcuts.
public struct ShortcutsSettingsTab: View {
    @ObservedObject private var settings: AppSettingsStore
    @StateObject private var shortcutSettingsViewModel = ShortcutSettingsViewModel()
    @StateObject private var recordingCancelShortcutViewModel = RecordingCancelShortcutSettingsViewModel()
    @StateObject private var meetingNotesShortcutViewModel = MeetingNotesShortcutSettingsViewModel()
    @State private var doubleTapIntervalInput = ""

    public init(settings: AppSettingsStore = .shared) {
        self.settings = settings
    }

    public var body: some View {
        SettingsFormPage {
            VStack(alignment: .leading, spacing: 4) {
                SettingsFormSectionHeader(title: "settings.section.shortcuts".localized, icon: "command")
                if let healthPresentation = shortcutSettingsViewModel.shortcutCaptureHealthPresentation {
                    ShortcutCaptureHealthStatusView(presentation: healthPresentation) {
                        shortcutSettingsViewModel.openShortcutCaptureHealthAction()
                    }
                }
            }
        } content: {
            ShortcutSettingsSection(
                groupTitle: "settings.shortcuts.dictation".localized,
                descriptionText: "settings.shortcuts.dictation_desc".localized
            ) {
                DSModifierShortcutEditor(
                    shortcut: $shortcutSettingsViewModel.dictationShortcutDefinition,
                    conflictMessage: shortcutSettingsViewModel.dictationModifierConflictMessage
                )
            }

            ShortcutSettingsSection(
                groupTitle: "settings.shortcuts.meeting".localized,
                descriptionText: "settings.shortcuts.meeting_desc".localized
            ) {
                DSModifierShortcutEditor(
                    shortcut: $shortcutSettingsViewModel.meetingShortcutDefinition,
                    conflictMessage: shortcutSettingsViewModel.meetingModifierConflictMessage
                )
            }

            Section {
                Toggle("settings.meetings.notes_panel.hotkey_enabled".localized, isOn: $settings.meetingNotesHotkeyEnabled)
                    .toggleStyle(.switch)

                if settings.meetingNotesHotkeyEnabled {
                    shortcutRow(title: "settings.meetings.notes_panel.shortcut".localized) {
                        DSModifierShortcutEditor(
                            shortcut: $meetingNotesShortcutViewModel.meetingNotesShortcutDefinition,
                            conflictMessage: meetingNotesShortcutViewModel.meetingNotesShortcutConflictMessage,
                            showsTitle: false,
                            maxInputWidth: AppDesignSystem.Layout.maxCompactTextFieldWidth
                        )
                    }
                }
            } header: {
                SettingsFormSectionHeader(title: "settings.meetings.notes_panel.title".localized, icon: "note.text")
            }

            Section {
                shortcutRow(
                    title: "settings.general.cancel_recording_shortcut".localized,
                    helperMessage: "settings.general.cancel_recording_shortcut_desc".localized
                ) {
                    DSModifierShortcutEditor(
                        shortcut: $recordingCancelShortcutViewModel.cancelRecordingShortcutDefinition,
                        conflictMessage: recordingCancelShortcutViewModel.cancelRecordingShortcutConflictMessage,
                        showsTitle: false,
                        maxInputWidth: AppDesignSystem.Layout.maxCompactTextFieldWidth
                    )
                }

                HStack(alignment: .center, spacing: 12) {
                    SettingsTitleWithPopover(
                        title: "settings.general.shortcut_double_tap_interval".localized,
                        helperMessage: "settings.general.shortcut_double_tap_interval_desc".localized
                    )

                    Spacer()

                    HStack(spacing: 8) {
                        TextField("", text: $doubleTapIntervalInput)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 84)
                            .onChange(of: doubleTapIntervalInput) { _, newValue in
                                applyDoubleTapIntervalInput(newValue)
                            }
                            .onSubmit(syncDoubleTapIntervalInput)

                        Text("ms")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                SettingsFormSectionHeader(title: "settings.shortcuts.recording".localized, icon: "record.circle")
            }
        }
        .onAppear(perform: syncDoubleTapIntervalInput)
    }

    private func shortcutRow(
        title: String,
        helperMessage: String? = nil,
        @ViewBuilder editor: () -> some View
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let helperMessage {
                SettingsTitleWithPopover(title: title, helperMessage: helperMessage)
            } else {
                Text(title)
                    .font(.body)
            }

            Spacer()

            editor()
        }
    }

    private func applyDoubleTapIntervalInput(_ rawValue: String) {
        let digitsOnly = rawValue.filter(\.isNumber)
        if digitsOnly != rawValue {
            doubleTapIntervalInput = digitsOnly
            return
        }

        guard !digitsOnly.isEmpty, let value = Double(digitsOnly) else { return }
        let validRange = AppSettingsStore.shortcutDoubleTapIntervalRangeMilliseconds
        let clampedValue = min(max(value, validRange.lowerBound), validRange.upperBound)

        settings.shortcutDoubleTapIntervalMilliseconds = clampedValue
        let normalizedValue = "\(Int(clampedValue))"
        if doubleTapIntervalInput != normalizedValue {
            doubleTapIntervalInput = normalizedValue
        }
    }

    private func syncDoubleTapIntervalInput() {
        doubleTapIntervalInput = "\(Int(settings.shortcutDoubleTapIntervalMilliseconds))"
    }
}

#Preview {
    ShortcutsSettingsTab()
        .frame(width: 680, height: 700)
}
