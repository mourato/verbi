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

            Picker(
                "settings.service.transcription_provider.provider".localized,
                selection: Binding(
                    get: { viewModel.selectedDictationProviderRawValue },
                    set: { viewModel.updateDictationProvider(rawValue: $0) }
                )
            ) {
                ForEach(viewModel.availableDictationProviders, id: \.rawValue) { provider in
                    Text(viewModel.displayName(for: provider)).tag(provider.rawValue)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("settings.models.routing.active_model".localized) {
                Text(viewModel.activeDictationTargetSummary)
                    .fontWeight(.medium)
            }

            Picker(
                "settings.service.transcription_provider.input_language".localized,
                selection: Binding(
                    get: { viewModel.selectedInputLanguageHintRawValue },
                    set: { viewModel.updateTranscriptionInputLanguageHint(rawValue: $0) }
                )
            ) {
                ForEach(viewModel.availableInputLanguageHints, id: \.rawValue) { hint in
                    Text(hint.displayName).tag(hint.rawValue)
                }
            }
            .pickerStyle(.menu)

            Text("settings.service.transcription_provider.input_language.help".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            SettingsFormSectionHeader(title: "settings.models.routing.title".localized, icon: "arrow.triangle.branch")
        }
    }
}

#Preview {
    ServiceTranscriptionProviderSection(viewModel: ServiceSettingsViewModel())
        .padding()
        .frame(width: 760)
}
