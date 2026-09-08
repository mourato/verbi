import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct ServiceMeetingTranscriptionSection: View {
    @ObservedObject private var viewModel: ServiceSettingsViewModel

    public init(viewModel: ServiceSettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Section {
            Text("settings.models.meeting_transcription.description".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "settings.service.model".localized,
                selection: Binding(
                    get: { viewModel.selectedMeetingLocalModel },
                    set: { viewModel.updateMeetingLocalModel($0) },
                ),
            ) {
                ForEach(viewModel.localModels) { localModel in
                    Text(localModel.displayName).tag(localModel.model)
                }
            }
            .pickerStyle(.menu)

            if viewModel.shouldShowMeetingDiarizationAutoDisableWarning {
                DSCallout(
                    kind: .warning,
                    title: "settings.service.transcription_provider.meeting_diarization_warning.title".localized,
                    message: "settings.service.transcription_provider.meeting_diarization_warning.message".localized(
                        with: viewModel.meetingLocalModelDisplayName,
                    ),
                )
            }
        } header: {
            SettingsFormSectionHeader(title: "settings.models.meeting_transcription.title".localized, icon: "waveform.and.person.filled")
        }
    }
}

#Preview {
    ServiceMeetingTranscriptionSection(viewModel: ServiceSettingsViewModel())
        .padding()
        .frame(width: 760)
}
