import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Meeting prompts editor hosted in a footerless `ModeEditorDrawer` side panel.
public struct MeetingPromptsSettingsContent: View {
    @ObservedObject private var meetingViewModel: MeetingSettingsViewModel
    private let onClose: () -> Void

    public init(meetingViewModel: MeetingSettingsViewModel, onClose: @escaping () -> Void) {
        self.meetingViewModel = meetingViewModel
        self.onClose = onClose
    }

    public var body: some View {
        ModeEditorDrawer(
            headerStyle: .close,
            title: "settings.meetings.prompts".localized,
            iconSymbol: "text.bubble",
            onClose: onClose,
        ) {
            Form {
                Section {
                    promptsContent
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var promptsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker(
                "settings.meetings.summary_output_language".localized,
                selection: $meetingViewModel.settings.meetingSummaryOutputLanguage,
            ) {
                ForEach(DictationOutputLanguage.allCases, id: \.self) { language in
                    Text(meetingSummaryOutputLanguageLabel(language)).tag(language)
                }
            }
            .pickerStyle(.menu)

            Divider()
                .padding(.vertical, 8)

            Toggle(isOn: $meetingViewModel.settings.meetingTypeAutoDetectEnabled) {
                VStack(alignment: .leading) {
                    Text("settings.meetings.autodetect_type".localized)
                    Text("settings.meetings.autodetect_type_desc".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()
                .padding(.vertical, 8)

            HStack {
                Text("settings.post_processing.choose_active".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    meetingViewModel.editingPrompt = nil
                    meetingViewModel.showPromptEditor = true
                } label: {
                    Label(
                        "settings.post_processing.new_prompt".localized,
                        systemImage: "plus",
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
            .padding(.vertical, 4)

            VStack(spacing: 8) {
                ForEach(meetingViewModel.availablePrompts) { prompt in
                    promptRow(prompt: prompt)
                }
            }
            .padding(.top, 4)
        }
    }

    private func meetingSummaryOutputLanguageLabel(_ language: DictationOutputLanguage) -> String {
        if language == .original {
            return "\(language.flagEmoji) \("settings.meetings.summary_output_language.option.meeting_spoken".localized)"
        }
        return language.displayName
    }

    private func promptRow(prompt: PostProcessingPrompt) -> some View {
        let isAutoDetectEnabled = meetingViewModel.settings.meetingTypeAutoDetectEnabled
        let isSelected = !isAutoDetectEnabled && meetingViewModel.selectedPromptId == prompt.id

        return PromptSelectionRow(
            iconSystemName: prompt.icon,
            title: prompt.title,
            description: prompt.description,
            isSelected: isSelected,
            onSelect: isAutoDetectEnabled ? nil : {
                meetingViewModel.selectPrompt(prompt.id)
            },
            onDoubleClick: {
                openPromptEditor(for: prompt)
            },
            unselectedStrokeColor: AppDesignSystem.Colors.separator.opacity(0.4),
            menuAccessibilityLabel: "transcription.ai_actions".localized,
            menuContent: {
                promptMenuContent(prompt: prompt, isSelected: isSelected, isAutoDetectEnabled: isAutoDetectEnabled)
            },
        )
    }

    @ViewBuilder
    private func promptMenuContent(prompt: PostProcessingPrompt, isSelected: Bool, isAutoDetectEnabled: Bool) -> some View {
        if !isAutoDetectEnabled {
            Button {
                meetingViewModel.selectPrompt(prompt.id, forceSelect: true)
            } label: {
                Label("settings.post_processing.select".localized, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
            }

            Divider()
        }

        Button {
            openPromptEditor(for: prompt)
        } label: {
            Label("settings.post_processing.edit".localized, systemImage: "pencil")
        }

        Button {
            meetingViewModel.prepareCopy(of: prompt, asDuplicate: true)
        } label: {
            Label("settings.post_processing.duplicate".localized, systemImage: "plus.square.on.square")
        }

        Divider()

        Button(role: .destructive) {
            meetingViewModel.confirmDeletePrompt(prompt)
        } label: {
            Label("settings.post_processing.delete".localized, systemImage: "trash")
        }
    }

    private func openPromptEditor(for prompt: PostProcessingPrompt) {
        meetingViewModel.editingPrompt = prompt
        meetingViewModel.showPromptEditor = true
    }
}

#Preview("Meeting Prompts Drawer") {
    MeetingPromptsSettingsContent(
        meetingViewModel: MeetingSettingsViewModel(),
        onClose: {},
    )
    .frame(width: 400, height: 640)
}
