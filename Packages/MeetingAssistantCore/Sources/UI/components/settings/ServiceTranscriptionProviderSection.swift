import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct ServiceTranscriptionProviderSection: View {
    @ObservedObject private var viewModel: ServiceSettingsViewModel

    public init(viewModel: ServiceSettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Section {
            Text("settings.models.routing.description".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("settings.models.routing.model".localized) {
                ModelPickerField(options: viewModel.dictationModelPickerOptions) { option in
                    viewModel.selectDictationModel(option.value)
                }
            }

            Picker(
                selection: Binding(
                    get: { viewModel.selectedInputLanguageHintRawValue },
                    set: { viewModel.updateTranscriptionInputLanguageHint(rawValue: $0) }
                )
            ) {
                ForEach(viewModel.availableInputLanguageHints, id: \.rawValue) { hint in
                    Text(hint.displayName).tag(hint.rawValue)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("settings.service.transcription_provider.input_language".localized)
                    DSInfoPopoverButton(
                        title: "settings.service.transcription_provider.input_language".localized,
                        message: "settings.service.transcription_provider.input_language.help".localized
                    )
                }
            }
            .pickerStyle(.menu)
        } header: {
            SettingsFormSectionHeader(title: "settings.models.routing.title".localized, icon: "arrow.triangle.branch")
        }
    }
}
