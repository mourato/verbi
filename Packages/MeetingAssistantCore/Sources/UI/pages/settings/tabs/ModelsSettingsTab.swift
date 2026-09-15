import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Models Settings Tab

/// Tab for configuring transcription provider and local model settings.
public struct ModelsSettingsTab: View {
    @StateObject private var viewModel: ServiceSettingsViewModel
    @StateObject private var aiSettingsViewModel: AISettingsViewModel
    @StateObject private var postProcessingViewModel: PostProcessingSettingsViewModel
    private let showsHeader: Bool
    private let onBack: (() -> Void)?

    @MainActor
    public init(
        settings: AppSettingsStore = .shared,
        showsHeader: Bool = true,
        onBack: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: ServiceSettingsViewModel(settings: settings))
        _aiSettingsViewModel = StateObject(wrappedValue: AISettingsViewModel(settings: settings))
        _postProcessingViewModel = StateObject(wrappedValue: PostProcessingSettingsViewModel(settings: settings))
        self.showsHeader = showsHeader
        self.onBack = onBack
    }

    public var body: some View {
        SettingsFormPage {
            VStack(alignment: .leading, spacing: 8) {
                if let onBack {
                    SettingsChildPageBackButton(action: onBack)
                }
                SettingsFormSectionHeader(title: "settings.section.models".localized, icon: "cpu")
                if showsHeader {
                    Text("settings.models.description".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } content: {
            EnhancementsProviderModelsPage(
                viewModel: aiSettingsViewModel,
                postProcessingViewModel: postProcessingViewModel
            )

            ServiceSettingsContent(
                viewModel: viewModel,
                includeTranscriptionProviderSection: false,
                includeMeetingTranscriptionSection: false
            )
        }
    }
}

#Preview {
    ModelsSettingsTab()
}
