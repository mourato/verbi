import Combine
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

@MainActor
public final class ServiceSettingsViewModel: ObservableObject {
    public struct LocalModelDescriptor: Identifiable, Hashable {
        public let model: LocalTranscriptionModel
        public let displayName: String
        public let supportsIncrementalTranscription: Bool
        public let supportsDiarization: Bool

        public var id: String {
            model.rawValue
        }
    }

    public struct CloudProviderDescriptor: Identifiable, Hashable {
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

    @Published public var transcriptionStatus: ConnectionStatus = .unknown
    @Published public var modelState: FluidAIModelManager.ModelState = .unloaded
    @Published public var isASRInstalled: Bool = false
    @Published public var isDiarizationLoaded: Bool = false
    @Published public var asrLastErrorMessage: String?
    @Published public var loadedASRLocalModelID: String?
    @Published public var lastRequestedASRLocalModelID: String?
    @Published public var transcriptionAPIKeyInput: String = ""
    @Published public var transcriptionAPIKeyInputsByProvider: [String: String] = [:]
    @Published public var transcriptionAPIKeyErrorMessage: String?

    private let transcriptionClient: TranscriptionClient
    private let settings: AppSettingsStore
    private let keychain: KeychainProvider
    private var cancellables = Set<AnyCancellable>()

    public init(
        transcriptionClient: TranscriptionClient = .shared,
        settings: AppSettingsStore = .shared,
        keychain: KeychainProvider = DefaultKeychainProvider()
    ) {
        self.transcriptionClient = transcriptionClient
        self.settings = settings
        self.keychain = keychain

        let modelManager = FluidAIModelManager.shared
        modelState = modelManager.modelState
        isASRInstalled = modelManager.isASRInstalled
        isDiarizationLoaded = modelManager.isDiarizationLoaded
        asrLastErrorMessage = modelManager.lastError
        loadedASRLocalModelID = modelManager.loadedASRLocalModelID
        lastRequestedASRLocalModelID = modelManager.lastRequestedASRLocalModelID

        modelManager.$modelState
            .receive(on: DispatchQueue.main)
            .assign(to: \.modelState, on: self)
            .store(in: &cancellables)

        modelManager.$isASRInstalled
            .receive(on: DispatchQueue.main)
            .assign(to: \.isASRInstalled, on: self)
            .store(in: &cancellables)

        modelManager.$isDiarizationLoaded
            .receive(on: DispatchQueue.main)
            .assign(to: \.isDiarizationLoaded, on: self)
            .store(in: &cancellables)

        modelManager.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: \.asrLastErrorMessage, on: self)
            .store(in: &cancellables)

        modelManager.$loadedASRLocalModelID
            .receive(on: DispatchQueue.main)
            .assign(to: \.loadedASRLocalModelID, on: self)
            .store(in: &cancellables)

        modelManager.$lastRequestedASRLocalModelID
            .receive(on: DispatchQueue.main)
            .assign(to: \.lastRequestedASRLocalModelID, on: self)
            .store(in: &cancellables)

        settings.$modelResidencyTimeout
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.$transcriptionInputLanguageHint
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.$transcriptionDictationSelection
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.$transcriptionProviderSelectedModels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.$meetingTranscriptionLocalModel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.$isMeetingTranscriptionEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        settings.$isDiarizationEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        refreshInstalledModelStates()
    }

    public var localModels: [LocalModelDescriptor] {
        LocalTranscriptionModel.allCases.map { model in
            LocalModelDescriptor(
                model: model,
                displayName: displayName(forModelID: model.rawValue),
                supportsIncrementalTranscription: model.supportsIncrementalTranscription,
                supportsDiarization: model.supportsDiarization
            )
        }
    }

    public var cloudProviders: [CloudProviderDescriptor] {
        [
            MeetingAssistantCoreInfrastructure.TranscriptionProvider.groq,
            .elevenLabs
        ].map { provider in
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

    public var selectedDictationProvider: MeetingAssistantCoreInfrastructure.TranscriptionProvider {
        settings.transcriptionDictationSelection.provider
    }

    public var selectedDictationProviderRawValue: String {
        selectedDictationProvider.rawValue
    }

    public var selectedDictationModel: String {
        settings.transcriptionDictationSelection.selectedModel
    }

    public var availableDictationProviders: [MeetingAssistantCoreInfrastructure.TranscriptionProvider] {
        MeetingAssistantCoreInfrastructure.TranscriptionProvider.allCases
    }

    public var availableDictationModels: [String] {
        availableModelIDs(for: selectedDictationProvider)
    }

    public var availableInputLanguageHints: [TranscriptionInputLanguageHint] {
        TranscriptionInputLanguageHint.allCases
    }

    public var selectedInputLanguageHintRawValue: String {
        settings.transcriptionInputLanguageHint.rawValue
    }

    public var activeDictationTargetSummary: String {
        let providerName = displayName(for: selectedDictationProvider)
        if selectedDictationProvider == .local {
            return "\(providerName) - \(activeDictationLocalModelDisplayName)"
        }
        return "\(providerName) - \(displayName(forModelID: selectedDictationModel))"
    }

    public var activeDictationLocalModelDisplayName: String {
        displayName(forModelID: settings.transcriptionSelectedModel(for: .local))
    }

    public var selectedMeetingLocalModel: LocalTranscriptionModel {
        settings.meetingTranscriptionLocalModel
    }

    public var meetingLocalModelDisplayName: String {
        displayName(forModelID: selectedMeetingLocalModel.rawValue)
    }

    public var isMeetingTranscriptionEnabled: Bool {
        settings.isMeetingTranscriptionEnabled
    }

    public var shouldShowMeetingSection: Bool {
        settings.isMeetingTranscriptionEnabled
    }

    public var shouldShowMeetingDiarizationAutoDisableWarning: Bool {
        settings.isDiarizationEnabled && !selectedMeetingLocalModel.supportsDiarization
    }

    public var shouldShowRemoteTranscriptionAPIKeyActions: Bool {
        selectedDictationProvider.usesRemoteInference
    }

    public var shouldShowInlineTranscriptionAPIKeyInput: Bool {
        selectedDictationProvider == .elevenLabs && !isDictationProviderReady
    }

    public var selectedRemoteProviderGetAPIKeyURL: URL? {
        apiKeyURL(for: selectedDictationProvider)
    }

    public var selectedRemoteProviderDisplayName: String {
        displayName(for: selectedDictationProvider)
    }

    public var isDictationProviderReady: Bool {
        isProviderReady(selectedDictationProvider)
    }

    public var isASRDownloadInProgress: Bool {
        modelState == .downloading || modelState == .loading
    }

    public var activeASRModelID: String? {
        loadedASRLocalModelID ?? lastRequestedASRLocalModelID
    }

    public var modelResidencyTimeoutOptions: [AppSettingsStore.ModelResidencyTimeoutOption] {
        AppSettingsStore.ModelResidencyTimeoutOption.allCases
    }

    public var modelResidencyTimeout: AppSettingsStore.ModelResidencyTimeoutOption {
        get { settings.modelResidencyTimeout }
        set { settings.modelResidencyTimeout = newValue }
    }

    public var hasPendingTranscriptionAPIKeyInput: Bool {
        !transcriptionAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func isLocalModelInstalled(_ model: LocalTranscriptionModel) -> Bool {
        FluidAIModelManager.shared.isASRModelInstalled(localModelID: model.rawValue)
    }

    public func isLocalModelLoaded(_ model: LocalTranscriptionModel) -> Bool {
        loadedASRLocalModelID == model.rawValue && modelState == .loaded
    }

    public func isLocalModelBusy(_ model: LocalTranscriptionModel) -> Bool {
        activeASRModelID == model.rawValue && isASRDownloadInProgress
    }

    public func localModelStatusText(_ model: LocalTranscriptionModel) -> String {
        if isLocalModelLoaded(model) {
            return "settings.service.installed".localized
        }

        if isLocalModelBusy(model) {
            switch modelState {
            case .downloading:
                return "transcription.model_state.downloading".localized
            case .loading:
                return "transcription.model_state.loading".localized
            case .error:
                return "transcription.model_state.error".localized
            case .loaded, .unloaded:
                break
            }
        }

        return isLocalModelInstalled(model)
            ? "settings.service.installed".localized
            : "settings.service.not_installed".localized
    }

    public func localModelStatusColor(_ model: LocalTranscriptionModel) -> Color {
        if isLocalModelLoaded(model) {
            return AppDesignSystem.Colors.success
        }

        if isLocalModelBusy(model) {
            switch modelState {
            case .downloading, .loading:
                return AppDesignSystem.Colors.warning
            case .error:
                return AppDesignSystem.Colors.error
            case .loaded, .unloaded:
                break
            }
        }

        return isLocalModelInstalled(model) ? AppDesignSystem.Colors.success : .secondary
    }

    public var localModelActionErrorMessage: String? {
        guard modelState == .error else { return nil }
        let message = asrLastErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (message?.isEmpty == false) ? message : nil
    }

    public func testConnection() {
        transcriptionStatus = .testing

        Task {
            do {
                var isHealthy = try await self.transcriptionClient.healthCheck()

                if !isHealthy {
                    try await self.transcriptionClient.warmupModel()
                    isHealthy = try await self.transcriptionClient.healthCheck()
                }

                if isHealthy {
                    self.transcriptionStatus = .success
                } else {
                    let message = FluidAIModelManager.shared.lastError?.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.transcriptionStatus = .failure((message?.isEmpty == false) ? message : nil)
                }
            } catch {
                let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                self.transcriptionStatus = .failure(message.isEmpty ? nil : message)
            }
        }
    }

    public func downloadASRModels() {
        downloadLocalModel(selectedMeetingLocalModel)
    }

    public func downloadLocalModel(_ model: LocalTranscriptionModel) {
        Task {
            await FluidAIModelManager.shared.loadModels(for: model.rawValue)
            await MainActor.run { self.objectWillChange.send() }
        }
    }

    public func deleteASRModels() {
        deleteLocalModel(selectedMeetingLocalModel)
    }

    public func deleteLocalModel(_ model: LocalTranscriptionModel) {
        Task {
            FluidAIModelManager.shared.deleteASRModels(for: model.rawValue)
            await MainActor.run { self.objectWillChange.send() }
        }
    }

    public func downloadDiarizationModels() {
        Task {
            await FluidAIModelManager.shared.loadDiarizationModels()
        }
    }

    public func deleteDiarizationModels() {
        Task {
            FluidAIModelManager.shared.deleteDiarizationModels()
        }
    }

    public func refreshInstalledModelStates() {
        FluidAIModelManager.shared.refreshInstalledModelStates()
    }

    public func updateDictationProvider(rawValue: String) {
        guard let provider = MeetingAssistantCoreInfrastructure.TranscriptionProvider(rawValue: rawValue) else {
            return
        }
        settings.updateTranscriptionDictationProvider(provider)
        transcriptionAPIKeyErrorMessage = nil
        loadTranscriptionAPIKeyInputForCurrentProvider()
        objectWillChange.send()
    }

    public func updateDictationModel(_ model: String) {
        settings.updateTranscriptionDictationModel(model)
        objectWillChange.send()
    }

    public func updateCloudProviderModel(_ model: String, for provider: MeetingAssistantCoreInfrastructure.TranscriptionProvider) {
        settings.updateTranscriptionModel(model, for: provider)
        objectWillChange.send()
    }

    public func updateMeetingLocalModel(_ model: LocalTranscriptionModel) {
        settings.updateMeetingTranscriptionLocalModel(model)
        objectWillChange.send()
    }

    public func updateTranscriptionInputLanguageHint(rawValue: String) {
        guard let hint = TranscriptionInputLanguageHint(rawValue: rawValue) else { return }
        settings.transcriptionInputLanguageHint = hint
        objectWillChange.send()
    }

    public func saveTranscriptionAPIKey() {
        let trimmed = transcriptionAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            transcriptionAPIKeyErrorMessage = "settings.service.transcription_provider.api_key.error.empty".localized
            return
        }

        do {
            try keychain.storeTranscriptionAPIKey(trimmed, for: selectedDictationProvider)
            transcriptionAPIKeyInput = ""
            transcriptionAPIKeyErrorMessage = nil
            objectWillChange.send()
        } catch {
            transcriptionAPIKeyErrorMessage = error.localizedDescription
        }
    }

    public func saveTranscriptionAPIKey(_ value: String, for provider: MeetingAssistantCoreInfrastructure.TranscriptionProvider) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            transcriptionAPIKeyErrorMessage = "settings.service.transcription_provider.api_key.error.empty".localized
            return
        }

        do {
            try keychain.storeTranscriptionAPIKey(trimmed, for: provider)
            transcriptionAPIKeyInputsByProvider[provider.rawValue] = ""
            transcriptionAPIKeyErrorMessage = nil
            objectWillChange.send()
        } catch {
            transcriptionAPIKeyErrorMessage = error.localizedDescription
        }
    }

    public func removeTranscriptionAPIKey() {
        do {
            try keychain.deleteTranscriptionAPIKey(for: selectedDictationProvider)
            transcriptionAPIKeyInput = ""
            transcriptionAPIKeyErrorMessage = nil
            objectWillChange.send()
        } catch {
            transcriptionAPIKeyErrorMessage = error.localizedDescription
        }
    }

    public func removeTranscriptionAPIKey(for provider: MeetingAssistantCoreInfrastructure.TranscriptionProvider) {
        do {
            try keychain.deleteTranscriptionAPIKey(for: provider)
            transcriptionAPIKeyInputsByProvider[provider.rawValue] = ""
            transcriptionAPIKeyErrorMessage = nil
            objectWillChange.send()
        } catch {
            transcriptionAPIKeyErrorMessage = error.localizedDescription
        }
    }

    public func displayName(forModelID modelID: String) -> String {
        if let localModel = MeetingAssistantCoreInfrastructure.LocalTranscriptionModel(rawValue: modelID) {
            localModel.displayName
        } else if modelID == "scribe_v1" {
            "settings.service.transcription_provider.model_option.elevenlabs.scribe_v1".localized
        } else if modelID == "scribe_v2" {
            "settings.service.transcription_provider.model_option.elevenlabs.scribe_v2".localized
        } else {
            modelID
        }
    }

    public func displayName(for provider: MeetingAssistantCoreInfrastructure.TranscriptionProvider) -> String {
        provider.displayName
    }

    private func availableModelIDs(for provider: MeetingAssistantCoreInfrastructure.TranscriptionProvider) -> [String] {
        switch provider {
        case .local:
            []
        case .groq:
            MeetingAssistantCoreInfrastructure.TranscriptionProvider.groqPresetModelIDs
        case .elevenLabs:
            MeetingAssistantCoreInfrastructure.TranscriptionProvider.elevenLabsPresetModelIDs
        }
    }

    private func apiKeyURL(for provider: MeetingAssistantCoreInfrastructure.TranscriptionProvider) -> URL? {
        switch provider {
        case .local:
            nil
        case .groq:
            AIProvider.groq.apiKeyURL
        case .elevenLabs:
            URL(string: "https://elevenlabs.io/app/settings/api-keys")
        }
    }

    private func isProviderReady(_ provider: MeetingAssistantCoreInfrastructure.TranscriptionProvider) -> Bool {
        switch provider {
        case .local:
            true
        case .groq:
            keychain.existsAPIKey(for: .groq)
        case .elevenLabs:
            keychain.existsTranscriptionAPIKey(for: .elevenLabs)
        }
    }

    private func loadTranscriptionAPIKeyInputForCurrentProvider() {
        transcriptionAPIKeyInput = ""
        transcriptionAPIKeyErrorMessage = nil
    }
}
