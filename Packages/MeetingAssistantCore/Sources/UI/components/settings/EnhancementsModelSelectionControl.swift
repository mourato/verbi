import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// preview-check: ignore — picker controls are previewed through the owning model surface.

public enum EnhancementsModelSelectionTarget: String, Identifiable {
    case meeting
    case dictation

    public var id: String {
        rawValue
    }

    var mode: IntelligenceKernelMode {
        switch self {
        case .meeting: .meeting
        case .dictation: .dictation
        }
    }

    var titleKey: String {
        switch self {
        case .meeting: "settings.enhancements.selector.meeting.title"
        case .dictation: "settings.enhancements.selector.dictation.title"
        }
    }

    var subtitleKey: String {
        switch self {
        case .meeting: "settings.enhancements.selector.meeting.subtitle"
        case .dictation: "settings.enhancements.selector.dictation.subtitle"
        }
    }
}

public struct EnhancementsModelSelectionControl: View {
    private let target: EnhancementsModelSelectionTarget
    @ObservedObject private var viewModel: AISettingsViewModel
    private let settings: AppSettingsStore

    public init(
        target: EnhancementsModelSelectionTarget,
        viewModel: AISettingsViewModel,
        settings: AppSettingsStore,
    ) {
        self.target = target
        self.viewModel = viewModel
        self.settings = settings
    }

    public var body: some View {
        EnhancementsModelPicker(
            title: target.titleKey.localized,
            subtitle: target.subtitleKey.localized,
            selection: selection,
            options: viewModel.enhancementsProviderModels,
            isLoadingOptions: viewModel.isLoadingEnhancementsProviderModels,
            providerDisplayName: settings.enhancementsProviderDisplayName(for:),
            onRefresh: {
                _ = viewModel.refreshEnhancementsProviderModelsManually()
            },
            onSelect: selectOption,
        )
        .onAppear {
            _ = viewModel.refreshEnhancementsProviderModelsManually()
        }
    }

    private var selection: EnhancementsAISelection {
        switch target {
        case .meeting:
            settings.enhancementsAISelection
        case .dictation:
            settings.enhancementsDictationAISelection
        }
    }

    private func selectOption(_ option: EnhancementsProviderModelOption) {
        if let registrationID = option.registrationID {
            settings.updateEnhancementsSelection(
                registrationID: registrationID,
                model: option.modelID,
                for: target.mode,
            )
        } else {
            settings.updateEnhancementsSelection(
                provider: option.provider,
                model: option.modelID,
                for: target.mode,
            )
        }
    }
}

public struct EnhancementsModelPicker: View {
    private let title: String
    private let subtitle: String
    private let selection: EnhancementsAISelection
    private let options: [EnhancementsProviderModelOption]
    private let isLoadingOptions: Bool
    private let providerDisplayName: (EnhancementsAISelection) -> String
    private let onRefresh: () -> Void
    private let onSelect: (EnhancementsProviderModelOption) -> Void

    @State private var isShowingModelSelection = false

    public init(
        title: String,
        subtitle: String,
        selection: EnhancementsAISelection,
        options: [EnhancementsProviderModelOption],
        isLoadingOptions: Bool,
        providerDisplayName: @escaping (EnhancementsAISelection) -> String,
        onRefresh: @escaping () -> Void,
        onSelect: @escaping (EnhancementsProviderModelOption) -> Void,
    ) {
        self.title = title
        self.subtitle = subtitle
        self.selection = selection
        self.options = options
        self.isLoadingOptions = isLoadingOptions
        self.providerDisplayName = providerDisplayName
        self.onRefresh = onRefresh
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                HStack(spacing: 8) {
                    Button(selectionSummary) {
                        isShowingModelSelection = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingOptions || options.isEmpty)

                    Button {
                        onRefresh()
                    } label: {
                        if isLoadingOptions {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .fontWeight(.medium)
                        }
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("settings.ai.model_refresh".localized)
                    .disabled(isLoadingOptions)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if options.isEmpty, !isLoadingOptions {
                Text("settings.enhancements.model_selector.empty".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $isShowingModelSelection) {
            EnhancementsModelSelectionSheet(
                options: options,
                isSelected: isSelectedOption,
                onSelect: { option in
                    onSelect(option)
                    isShowingModelSelection = false
                },
                onCancel: {
                    isShowingModelSelection = false
                },
            )
        }
    }

    private var selectionSummary: String {
        let providerName = providerDisplayName(selection)
        let model = selection.selectedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            return "settings.enhancements.provider_models.summary.no_model".localized(with: providerName)
        }
        return "settings.enhancements.provider_models.summary".localized(with: providerName, model)
    }

    private func isSelectedOption(_ option: EnhancementsProviderModelOption) -> Bool {
        if let selectedRegistrationID = selection.registrationID,
           let optionRegistrationID = option.registrationID
        {
            return selectedRegistrationID == optionRegistrationID
                && selection.selectedModel == option.modelID
        }

        return selection.provider == option.provider && selection.selectedModel == option.modelID
    }
}
