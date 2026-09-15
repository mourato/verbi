import Combine
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import os.log
import SwiftUI

public struct EnhancementsProviderModelOption: Identifiable, Hashable, Sendable {
    public let provider: AIProvider
    public let registrationID: UUID?
    public let registrationName: String?
    public let modelID: String

    public init(
        provider: AIProvider,
        registrationID: UUID? = nil,
        registrationName: String? = nil,
        modelID: String
    ) {
        self.provider = provider
        self.registrationID = registrationID
        self.registrationName = registrationName
        self.modelID = modelID
    }

    public var id: String {
        let registrationPart = registrationID?.uuidString ?? provider.rawValue
        return "\(registrationPart)::\(modelID)"
    }
}

public enum CredentialBootstrapPolicy: Sendable {
    case eager
    case deferredUserAction
}

public enum AIModelCatalogStatus: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case unavailable
    case failed
}

@MainActor
public class AISettingsViewModel: ObservableObject {
    @Published var settings: AppSettingsStore
    @Published public var showAPIKey = false
    @Published public var apiKeyText = ""
    @Published public var isKeySaved = false
    @Published public var connectionStatus: ConnectionStatus = .unknown
    @Published public var showVerifyButton = true
    @Published public var showGetApiKeyButton = true
    @Published public private(set) var modelCatalogStatus: AIModelCatalogStatus = .idle
    @Published public var availableModels: [LLMModel] = []
    @Published public var isLoadingModels = false
    @Published public var modelsFetchError: String?
    @Published public private(set) var lastModelsRefreshAt: Date?
    @Published public private(set) var lastModelsRefreshSucceeded = false
    @Published public private(set) var lastModelsRefreshResultText: String?
    @Published public var enhancementsAvailableModels: [LLMModel] = []
    @Published public var isLoadingEnhancementsModels = false
    @Published public var enhancementsModelsFetchError: String?
    @Published public var enhancementsProviderModels: [EnhancementsProviderModelOption] = []
    @Published public var isLoadingEnhancementsProviderModels = false
    @Published public var enhancementsProviderModelsFetchError: String?
    @Published public var enhancementsLastModelsRefreshAt: Date?
    @Published public var enhancementsLastModelsRefreshSucceeded = false
    @Published public var enhancementsLastModelsRefreshResultText: String?
    @Published public var activeEnhancementsProvider: AIProvider = .openai
    @Published public var isEnhancementsProviderKeySaved = false
    @Published public var enhancementsConnectionStatus: ConnectionStatus = .unknown
    @Published public var enhancementsAPIKeyText = ""
    @Published public var enhancementsActionError: String?
    @Published public internal(set) var enhancementsModelCatalogStatus: AIModelCatalogStatus = .idle
    @Published public var actionError: String?

    let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "AISettingsViewModel")
    let keychain: KeychainProvider
    let llmService: LLMService
    let credentialBootstrapPolicy: CredentialBootstrapPolicy
    var cancellables = Set<AnyCancellable>()
    var lastAutomaticModelsFetchAt: Date?
    var lastAutomaticEnhancementsModelsFetchAt: Date?
    var lastAutomaticEnhancementsProviderModelsFetchAt: Date?
    var enhancementsModelsByProvider: [AIProvider: [LLMModel]] = [:]
    let automaticModelsFetchThrottleInterval: TimeInterval = 15

    public var canRefreshModels: Bool {
        isKeySaved || !normalizedAPIKeyText.isEmpty
    }

    public var hasPendingAPIKeyInput: Bool {
        !normalizedAPIKeyText.isEmpty
    }

    public var canVerifyConnection: Bool {
        isKeySaved || hasPendingAPIKeyInput
    }

    public var modelsRefreshSummary: String? {
        guard let result = lastModelsRefreshResultText,
              let refreshedAt = lastModelsRefreshAt
        else { return nil }

        let refreshTime = DateFormatter.localizedString(from: refreshedAt, dateStyle: .none, timeStyle: .short)
        return "\(result) • \(refreshTime)"
    }

    public var enhancementsModelsRefreshSummary: String? {
        guard let result = enhancementsLastModelsRefreshResultText,
              let refreshedAt = enhancementsLastModelsRefreshAt
        else { return nil }

        let refreshTime = DateFormatter.localizedString(from: refreshedAt, dateStyle: .none, timeStyle: .short)
        return "\(result) • \(refreshTime)"
    }

    public var hasPendingEnhancementsAPIKeyInput: Bool {
        !enhancementsAPIKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public init(
        settings: AppSettingsStore,
        keychain: KeychainProvider = DefaultKeychainProvider(),
        llmService: LLMService = DefaultLLMService(),
        credentialBootstrapPolicy: CredentialBootstrapPolicy = .eager
    ) {
        self.settings = settings
        self.keychain = keychain
        self.llmService = llmService
        self.credentialBootstrapPolicy = credentialBootstrapPolicy
        activeEnhancementsProvider = settings.enhancementsAISelection.provider

        settings.$aiConfiguration
            .map(\.provider)
            .removeDuplicates()
            .dropFirst() // Skip initial value to avoid clearing selection on tab switch
            .sink { [weak self] _ in
                guard let self else { return }
                settings.updateSelectedModel("") // Clear previous selection (properly triggers didSet)
                clearTransientAPIKey()
                if credentialBootstrapPolicy == .eager {
                    refreshProviderCredentialState()
                } else {
                    resetPrimaryProviderStateForDeferredBootstrap()
                }
            }
            .store(in: &cancellables)

        settings.$enhancementsAISelection
            .map(\.provider)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] provider in
                guard let self else { return }
                if activeEnhancementsProvider == provider {
                    if credentialBootstrapPolicy == .eager {
                        refreshEnhancementsProviderCredentialState(provider: provider)
                    } else {
                        resetEnhancementsProviderStateForDeferredBootstrap(provider: provider)
                    }
                }
            }
            .store(in: &cancellables)

        // Initial load for current provider
        if credentialBootstrapPolicy == .eager {
            refreshProviderCredentialState()
            refreshEnhancementsProviderCredentialState()
        } else {
            resetPrimaryProviderStateForDeferredBootstrap()
            resetEnhancementsProviderStateForDeferredBootstrap(provider: activeEnhancementsProvider)
        }
    }

    private func updateUIStates() {
        showVerifyButton = connectionStatus != .success
        showGetApiKeyButton = !isKeySaved && settings.aiConfiguration.provider.apiKeyURL != nil
    }

    public func refreshProviderCredentialState() {
        isKeySaved = keychain.existsAPIKey(for: settings.aiConfiguration.provider)
        clearTransientAPIKey()
        lastModelsRefreshAt = nil
        lastModelsRefreshSucceeded = false
        lastModelsRefreshResultText = nil
        modelsFetchError = nil

        if isKeySaved {
            connectionStatus = .saved
            if settings.aiConfiguration.provider == .custom {
                modelCatalogStatus = .unavailable
                availableModels = []
            } else if credentialBootstrapPolicy == .eager {
                Task {
                    await fetchAvailableModels()
                }
            } else {
                availableModels = []
            }
        } else {
            connectionStatus = .unknown
            modelCatalogStatus = .idle
            availableModels = []
        }

        updateUIStates()
    }

    private func persistAPIKey(_ value: String) throws {
        let providerKey = KeychainManager.apiKeyKey(for: settings.aiConfiguration.provider)
        do {
            if !value.isEmpty {
                try keychain.store(value, for: providerKey)
                // swiftformat:disable:next redundantSelf
                logger.info("API Key successfully persisted to Keychain for \(self.settings.aiConfiguration.provider.displayName)")
            } else {
                try keychain.delete(for: providerKey)
                // swiftformat:disable:next redundantSelf
                logger.info("API Key removed from Keychain for \(self.settings.aiConfiguration.provider.displayName)")
            }
        } catch {
            logger.error("Failed to persist API key: \(error.localizedDescription)")
            // We'll handle visual feedback in the verify/remove methods
            throw error
        }
    }

    @discardableResult
    public func saveAPIKeyWithoutVerification() -> Bool {
        let value = normalizedAPIKeyText
        guard !value.isEmpty else { return false }

        do {
            try persistAPIKey(value)
            guard keychain.existsAPIKey(for: settings.aiConfiguration.provider) else {
                throw KeychainManager.KeychainError.itemNotFound
            }

            isKeySaved = true
            connectionStatus = .saved
            clearTransientAPIKey()
            actionError = nil
            if settings.aiConfiguration.provider == .custom {
                modelCatalogStatus = .unavailable
                availableModels = []
            }
            updateUIStates()
            refreshEnhancementsCredentialStateIfNeeded()
            return true
        } catch {
            actionError = "settings.ai.save_failed".localized
            connectionStatus = .failure(actionError)
            clearTransientAPIKey()
            updateUIStates()
            logger.error("Failed to save API key without verification: \(error.localizedDescription)")
            return false
        }
    }

    private func loadAPIKeyForCurrentProvider() -> String? {
        do {
            return try keychain.retrieveAPIKey(for: settings.aiConfiguration.provider)
        } catch {
            logger.error("Failed to load API key: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    public func testAPIConnection() -> Task<Void, Never> {
        connectionStatus = .testing
        availableModels = []
        modelsFetchError = nil

        let pendingAPIKey = normalizedAPIKeyText
        let apiKeySnapshot = pendingAPIKey.isEmpty
            ? (loadAPIKeyForCurrentProvider() ?? "")
            : pendingAPIKey
        guard let url = llmService.validateURL(settings.aiConfiguration.baseURL) else {
            connectionStatus = .failure("settings.ai.connection.invalid_url".localized)
            clearTransientAPIKey()
            updateUIStates()
            return Task {}
        }

        guard !apiKeySnapshot.isEmpty else {
            connectionStatus = .failure("settings.ai.connection.missing_key".localized)
            clearTransientAPIKey()
            updateUIStates()
            return Task {}
        }

        return Task {
            do {
                let success = try await llmService.testConnection(
                    baseURL: url,
                    apiKey: apiKeySnapshot,
                    provider: settings.aiConfiguration.provider
                )

                if success {
                    self.connectionStatus = .success
                    if !pendingAPIKey.isEmpty {
                        try self.persistAPIKey(pendingAPIKey)
                    }
                    self.isKeySaved = true
                    self.clearTransientAPIKey()
                    self.updateUIStates()
                    self.refreshEnhancementsCredentialStateIfNeeded()
                    if self.settings.aiConfiguration.provider == .custom {
                        self.modelCatalogStatus = .unavailable
                        self.availableModels = []
                    } else {
                        await self.fetchAvailableModels()
                    }
                } else {
                    self.connectionStatus = .failure("settings.ai.connection.invalid_response".localized)
                    self.clearTransientAPIKey()
                    self.updateUIStates()
                }
            } catch {
                self.connectionStatus = .failure(self.connectionErrorMessage(from: error))
                logger.error("Connection test failed: \(error.localizedDescription)")
                self.clearTransientAPIKey()
                self.updateUIStates()
            }
        }
    }

    @discardableResult
    public func refreshModelsManually() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            await fetchAvailableModels(trigger: .manual)
        }
    }

    @discardableResult
    public func refreshEnhancementsModelsManually() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            await fetchEnhancementsAvailableModels(trigger: .manual)
        }
    }

    @discardableResult
    public func refreshEnhancementsProviderModelsManually() -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            await fetchEnhancementsProviderModels(trigger: .manual)
        }
    }

    /// Fetches available models from the LLM service's /models endpoint.
    public func fetchAvailableModels(trigger: ModelFetchTrigger = .automatic) async {
        if trigger == .automatic,
           let lastFetch = lastAutomaticModelsFetchAt,
           Date().timeIntervalSince(lastFetch) < automaticModelsFetchThrottleInterval
        {
            return
        }

        guard let baseURL = llmService.validateURL(settings.aiConfiguration.baseURL) else {
            modelCatalogStatus = .failed
            modelsFetchError = "settings.ai.connection.invalid_url".localized
            registerModelsRefreshResult(success: false, message: "settings.ai.connection.invalid_url".localized)
            return
        }

        if settings.aiConfiguration.provider == .custom {
            modelCatalogStatus = .unavailable
            availableModels = []
            modelsFetchError = nil
            registerModelsRefreshResult(success: false, message: "settings.ai.models.catalog_unavailable".localized)
            return
        }

        if trigger == .automatic {
            lastAutomaticModelsFetchAt = Date()
        }

        isLoadingModels = true
        modelCatalogStatus = .loading
        modelsFetchError = nil

        defer { self.isLoadingModels = false }

        do {
            let credential = resolvedCredentialForModelsFetch()
            availableModels = try await llmService.fetchAvailableModels(
                baseURL: baseURL,
                apiKey: credential,
                provider: settings.aiConfiguration.provider
            )
            modelCatalogStatus = .loaded
            if isKeySaved {
                connectionStatus = .success
                updateUIStates()
            }
            registerModelsRefreshResult(
                success: true,
                message: String(format: "settings.ai.models_loaded".localized, availableModels.count)
            )
            // swiftformat:disable:next redundantSelf
            self.logger.info("Fetched \(self.availableModels.count) models from API")
        } catch {
            modelCatalogStatus = .failed
            logger.error("Failed to fetch models: \(error.localizedDescription)")
            modelsFetchError = error.localizedDescription
            registerModelsRefreshResult(success: false, message: "settings.ai.models.fetch_failed".localized)
        }
    }

    /// Removes the API key for the current provider from the Keychain.
    public func removeAPIKey() {
        actionError = nil
        let providerKey = KeychainManager.apiKeyKey(for: settings.aiConfiguration.provider)
        do {
            try keychain.delete(for: providerKey)
            clearTransientAPIKey()
            isKeySaved = false
            connectionStatus = .unknown
            updateUIStates()
            availableModels = []
            modelCatalogStatus = .idle
            refreshEnhancementsCredentialStateIfNeeded()
            // swiftformat:disable:next redundantSelf
            logger.info("API Key removed from Keychain for \(self.settings.aiConfiguration.provider.displayName)")
        } catch {
            actionError = "settings.ai.remove_failed".localized
            logger.error("Failed to remove API key: \(error.localizedDescription)")
        }
    }

    private func refreshEnhancementsCredentialStateIfNeeded() {
        guard activeEnhancementsProvider == settings.aiConfiguration.provider else { return }
        refreshEnhancementsProviderCredentialState()
    }

    private func resetPrimaryProviderStateForDeferredBootstrap() {
        isKeySaved = false
        connectionStatus = .unknown
        modelCatalogStatus = settings.aiConfiguration.provider == .custom ? .unavailable : .idle
        availableModels = []
        modelsFetchError = nil
        clearTransientAPIKey()
        updateUIStates()
    }

    private var normalizedAPIKeyText: String {
        apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func clearTransientAPIKey() {
        guard !apiKeyText.isEmpty else { return }
        apiKeyText = ""
    }

    private func resolvedCredentialForModelsFetch() -> String {
        if isKeySaved {
            return loadAPIKeyForCurrentProvider() ?? ""
        }
        return normalizedAPIKeyText
    }

    private func registerModelsRefreshResult(success: Bool, message: String) {
        lastModelsRefreshSucceeded = success
        lastModelsRefreshResultText = message
        lastModelsRefreshAt = Date()
    }

    func connectionErrorMessage(from error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "settings.ai.connection.not_connected".localized
            case .timedOut:
                return "settings.ai.connection.timed_out".localized
            case .cannotFindHost:
                return "settings.ai.connection.host_not_found".localized
            case .cannotConnectToHost:
                return "settings.ai.connection.cannot_connect".localized
            case .secureConnectionFailed:
                return "settings.ai.connection.secure_failed".localized
            case .networkConnectionLost:
                return "settings.ai.connection.network_lost".localized
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

public enum ModelFetchTrigger {
    case automatic
    case manual
}
