import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

public extension ServiceSettingsViewModel {
    struct LocalModelDescriptor: Identifiable, Hashable {
        public let model: LocalTranscriptionModel
        public let displayName: String
        public let supportsIncrementalTranscription: Bool
        public let supportsDiarization: Bool

        public var id: String {
            model.rawValue
        }
    }

    struct CloudProviderDescriptor: Identifiable, Hashable {
        public let provider: MeetingAssistantCoreInfrastructure.TranscriptionProvider
        public let displayName: String
        public let selectedModelID: String
        public let availableModelIDs: [String]
        public let isReady: Bool
        public let apiKeyURL: URL?

        public var id: String {
            provider.rawValue
        }
    }

    var localModels: [LocalModelDescriptor] {
        LocalTranscriptionModel.allCases.map { model in
            LocalModelDescriptor(
                model: model,
                displayName: displayName(forModelID: model.rawValue),
                supportsIncrementalTranscription: model.supportsIncrementalTranscription,
                supportsDiarization: model.supportsDiarization
            )
        }
    }

    var cloudProviders: [CloudProviderDescriptor] {
        let providers: [MeetingAssistantCoreInfrastructure.TranscriptionProvider] = [
            .groq,
            .elevenLabs,
            .openai
        ]
        return providers.map { provider in
            CloudProviderDescriptor(
                provider: provider,
                displayName: displayName(for: provider),
                selectedModelID: settings.transcriptionSelectedModel(for: provider),
                availableModelIDs: availableModelIDs(for: provider),
                isReady: isProviderReady(provider),
                apiKeyURL: apiKeyURL(for: provider)
            )
        }
    }

    struct CatalogModelDescriptor: Identifiable, Hashable {
        public let provider: MeetingAssistantCoreInfrastructure.TranscriptionProvider
        public let modelID: String
        public let localModel: LocalTranscriptionModel?
        public let displayName: String
        public let providerDisplayName: String
        public let iconSystemName: String
        public let isLocal: Bool
        public let requiresAPIKey: Bool
        public let isProviderReady: Bool
        public let isInstalled: Bool
        public let isLoaded: Bool
        public let isBusy: Bool
        public let isUsedForDictation: Bool
        public let isUsedForMeetings: Bool
        public let supportsIncrementalTranscription: Bool
        public let supportsDiarization: Bool
        public let apiKeyURL: URL?

        public var id: String {
            "\(provider.rawValue):\(modelID)"
        }

        public var isInUse: Bool {
            isUsedForDictation || isUsedForMeetings
        }

        public var showsRequiresKeyBadge: Bool {
            requiresAPIKey && !isProviderReady
        }
    }

    var catalogModels: [CatalogModelDescriptor] {
        let localCatalog = LocalTranscriptionModel.allCases.map { model in
            CatalogModelDescriptor(
                provider: .local,
                modelID: model.rawValue,
                localModel: model,
                displayName: displayName(forModelID: model.rawValue),
                providerDisplayName: displayName(for: .local),
                iconSystemName: TranscriptionProvider.local.iconSystemName,
                isLocal: true,
                requiresAPIKey: false,
                isProviderReady: true,
                isInstalled: isLocalModelInstalled(model),
                isLoaded: isLocalModelLoaded(model),
                isBusy: isLocalModelBusy(model),
                isUsedForDictation: isModelUsedForDictation(provider: .local, modelID: model.rawValue),
                isUsedForMeetings: settings.isMeetingTranscriptionEnabled && selectedMeetingLocalModel == model,
                supportsIncrementalTranscription: model.supportsIncrementalTranscription,
                supportsDiarization: model.supportsDiarization,
                apiKeyURL: nil
            )
        }

        let cloudProviders: [MeetingAssistantCoreInfrastructure.TranscriptionProvider] = [
            .groq,
            .elevenLabs,
            .openai
        ]

        let cloudCatalog = cloudProviders.flatMap { provider in
            let ready = isProviderReady(provider)
            let providerName = displayName(for: provider)
            let icon = provider.iconSystemName
            let keyURL = apiKeyURL(for: provider)

            return availableModelIDs(for: provider).map { modelID in
                CatalogModelDescriptor(
                    provider: provider,
                    modelID: modelID,
                    localModel: nil,
                    displayName: displayName(forModelID: modelID),
                    providerDisplayName: providerName,
                    iconSystemName: icon,
                    isLocal: false,
                    requiresAPIKey: true,
                    isProviderReady: ready,
                    isInstalled: false,
                    isLoaded: false,
                    isBusy: false,
                    isUsedForDictation: isModelUsedForDictation(provider: provider, modelID: modelID),
                    isUsedForMeetings: false,
                    supportsIncrementalTranscription: false,
                    supportsDiarization: false,
                    apiKeyURL: keyURL
                )
            }
        }

        return localCatalog + cloudCatalog
    }

    var selectedCatalogModel: CatalogModelDescriptor? {
        guard let selectedCatalogModelID else { return nil }
        return catalogModels.first { $0.id == selectedCatalogModelID }
    }

    func selectCatalogModel(_ descriptor: CatalogModelDescriptor) {
        transcriptionAPIKeyErrorMessage = nil
        selectedCatalogModelID = descriptor.id
    }

    func dismissSelectedCatalogModel() {
        transcriptionAPIKeyErrorMessage = nil
        selectedCatalogModelID = nil
    }

    func catalogModelStatusText(_ descriptor: CatalogModelDescriptor) -> String {
        if let localModel = descriptor.localModel {
            return localModelStatusText(localModel)
        }
        return descriptor.isProviderReady
            ? "settings.models.cloud_models.provider_ready".localized
            : "settings.models.catalog.badge.requires_key".localized
    }

    func catalogModelStatusColor(_ descriptor: CatalogModelDescriptor) -> Color {
        if let localModel = descriptor.localModel {
            return localModelStatusColor(localModel)
        }
        return descriptor.isProviderReady
            ? AppDesignSystem.Colors.success
            : AppDesignSystem.Colors.warning
    }

    internal func isModelUsedForDictation(
        provider: MeetingAssistantCoreInfrastructure.TranscriptionProvider,
        modelID: String
    ) -> Bool {
        if selectedDictationProvider == provider,
           settings.transcriptionSelectedModel(for: provider) == modelID
        {
            return true
        }

        guard settings.hasConfiguredDictationStyles else {
            return false
        }

        return settings.dictationStyles.contains { style in
            let selection = style.transcriptionConfiguration.selection
            return selection.provider == provider
                && provider.normalizedModelID(selection.selectedModel) == modelID
        }
    }
}

extension TranscriptionProvider {
    var iconSystemName: String {
        switch self {
        case .local:
            "internaldrive"
        case .groq:
            AIProvider.groq.icon
        case .elevenLabs:
            "waveform"
        case .openai:
            AIProvider.openai.icon
        }
    }
}
