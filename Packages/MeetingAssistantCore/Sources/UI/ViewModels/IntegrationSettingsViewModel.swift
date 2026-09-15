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
public final class IntegrationSettingsViewModel: ObservableObject {
    private let settings = AppSettingsStore.shared
    private var cancellables = Set<AnyCancellable>()
    private let raycastIntegrationService: any AssistantDeepLinkDispatching

    @Published public var assistantIntegrations: [AssistantIntegrationConfig]
    @Published public var selectedIntegrationId: UUID?

    @Published public private(set) var raycastTestStatusMessage: String?
    @Published public private(set) var raycastTestStatusIsError: Bool = false
    @Published public private(set) var raycastDeepLinkIsValid: Bool = true
    @Published public private(set) var raycastDeepLinkValidationMessage: String?
    @Published public private(set) var scriptTestOutput: String?
    @Published public private(set) var scriptTestErrorMessage: String?

    public init(
        raycastIntegrationService: any AssistantDeepLinkDispatching = AssistantRaycastIntegrationService()
    ) {
        let persistedIntegrations = settings.assistantIntegrations
        let resolvedSelectedIntegration = settings.assistantSelectedIntegration ?? persistedIntegrations.first

        self.raycastIntegrationService = raycastIntegrationService
        assistantIntegrations = persistedIntegrations
        selectedIntegrationId = resolvedSelectedIntegration?.id
        raycastTestStatusMessage = nil
        raycastDeepLinkValidationMessage = nil
        scriptTestOutput = nil
        scriptTestErrorMessage = nil

        setupBindings()
        updateRaycastDeepLinkValidation()
    }

    public var builtInIntegrations: [AssistantIntegrationConfig] {
        assistantIntegrations.filter { $0.id == AssistantIntegrationConfig.raycastDefaultID }
    }

    public var customIntegrations: [AssistantIntegrationConfig] {
        assistantIntegrations.filter { $0.id != AssistantIntegrationConfig.raycastDefaultID }
    }

    public var canAddIntegration: Bool {
        true
    }

    public func integration(for id: UUID) -> AssistantIntegrationConfig? {
        assistantIntegrations.first(where: { $0.id == id })
    }

    public func setIntegrationEnabled(_ isEnabled: Bool, for id: UUID) {
        if isEnabled, let integration = integration(for: id) {
            var candidate = integration
            candidate.isEnabled = true
            if let conflictMessage = modifierConflictMessage(for: normalizedIntegration(candidate)) {
                raycastTestStatusIsError = true
                raycastTestStatusMessage = conflictMessage
                return
            }
        }

        updateIntegration(id: id) { integration in
            integration.isEnabled = isEnabled
        }

        if isEnabled {
            selectedIntegrationId = id
        }

        if selectedIntegrationId == id {
            updateRaycastDeepLinkValidation()
        }
    }

    public func addIntegration() {
        let nextIndex = customIntegrations.count + 1
        let newIntegration = AssistantIntegrationConfig(
            name: "settings.assistant.integrations.default_name".localized(with: nextIndex),
            kind: .deeplink,
            isEnabled: false,
            deepLink: AssistantIntegrationConfig.defaultRaycastDeepLink
        )

        assistantIntegrations += [newIntegration]
        selectedIntegrationId = newIntegration.id
        raycastTestStatusMessage = nil
    }

    public func removeIntegration(id: UUID) {
        guard id != AssistantIntegrationConfig.raycastDefaultID else {
            return
        }

        assistantIntegrations = assistantIntegrations.filter { $0.id != id }

        if selectedIntegrationId == id {
            selectedIntegrationId = assistantIntegrations.first?.id
        }

        raycastTestStatusMessage = nil
    }

    public func saveIntegration(_ integration: AssistantIntegrationConfig) {
        updateIntegration(id: integration.id) { existing in
            existing = integration
        }

        selectedIntegrationId = integration.id
        updateRaycastDeepLinkValidation()
    }

    @discardableResult
    public func saveIntegrationWithModifierValidation(_ integration: AssistantIntegrationConfig) -> String? {
        if let shortcut = integration.shortcutDefinition,
           ShortcutDefinitionNormalizer.normalized(shortcut, allowReturnOrEnter: false) == nil
        {
            return "settings.shortcuts.modifier.primary_key_required".localized
        }

        let normalized = normalizedIntegration(integration)
        if let conflictMessage = modifierConflictMessage(for: normalized) {
            return conflictMessage
        }

        saveIntegration(normalized)
        return nil
    }

    @discardableResult
    public func setIntegrationShortcutDefinition(_ shortcut: ShortcutDefinition?, for id: UUID) -> String? {
        guard var integration = integration(for: id) else {
            return nil
        }

        integration.shortcutDefinition = shortcut
        integration.modifierShortcutGesture = shortcut?.asModifierShortcutGesture
        integration.shortcutPresetKey = shortcut == nil ? .notSpecified : .custom

        return saveIntegrationWithModifierValidation(integration)
    }

    public func applyPreset(_ preset: AssistantIntegrationPreset, to id: UUID) {
        updateIntegration(id: id) { integration in
            integration.selectedPreset = preset
            integration.deepLink = defaultDeepLink(for: preset)
        }

        updateRaycastDeepLinkValidation()
    }

    public func defaultDeepLink(for preset: AssistantIntegrationPreset) -> String {
        switch preset {
        case .googleSearch:
            "raycast://extensions/raycast/google-search/search"
        case .launchApps:
            "raycast://extensions/raycast/system/open"
        case .closeApps:
            "raycast://extensions/raycast/system/quit"
        case .askChatGPT:
            AssistantIntegrationConfig.defaultRaycastDeepLink
        case .askClaude:
            AssistantIntegrationConfig.defaultRaycastDeepLink
        case .youtubeSearch:
            "raycast://extensions/raycast/youtube/search-videos"
        case .openWebsite:
            "raycast://extensions/raycast/browser/open-url"
        case .appleShortcuts:
            "raycast://extensions/raycast/shortcuts/run-shortcut"
        case .shellCommand:
            "raycast://extensions/raycast/script-commands"
        case .pressKeys:
            "raycast://extensions/raycast/system/keyboard-shortcuts"
        }
    }

    public func validateDeepLink(_ deepLink: String, integrationEnabled: Bool) {
        guard integrationEnabled else {
            raycastDeepLinkIsValid = true
            raycastDeepLinkValidationMessage = nil
            return
        }

        let validation = raycastIntegrationService.validateDeepLink(deepLink)
        switch validation {
        case .valid:
            raycastDeepLinkIsValid = true
            raycastDeepLinkValidationMessage = "settings.assistant.integrations.valid_deeplink".localized
        case .invalid:
            raycastDeepLinkIsValid = false
            raycastDeepLinkValidationMessage = "settings.assistant.integrations.invalid_deeplink".localized
        }
    }

    public func testIntegration(_ integration: AssistantIntegrationConfig) {
        AppLogger.info(
            "Running integration test",
            category: .assistant,
            extra: ["deepLinkLength": integration.deepLink.count, "name": integration.name]
        )

        do {
            let result = try raycastIntegrationService.dispatch(
                command: "settings.assistant.integrations.test_message".localized,
                baseDeepLink: integration.deepLink
            )

            raycastTestStatusIsError = false
            raycastTestStatusMessage = result == .openedWithClipboardFallback
                ? "settings.assistant.integrations.test_success_clipboard_fallback".localized
                : "settings.assistant.integrations.test_success".localized
        } catch AssistantIntegrationDispatchError.invalidDeepLink {
            raycastTestStatusIsError = true
            raycastTestStatusMessage = "settings.assistant.integrations.test_invalid_deeplink".localized
        } catch {
            raycastTestStatusIsError = true
            raycastTestStatusMessage = "settings.assistant.integrations.test_failed".localized
        }
    }

    public func clearScriptTestResult() {
        scriptTestOutput = nil
        scriptTestErrorMessage = nil
    }

    public func testScript(script: String, input: String) async {
        do {
            scriptTestErrorMessage = nil
            let output = try await Self.executeScript(script: script, input: input)
            scriptTestOutput = output
        } catch {
            scriptTestOutput = nil
            scriptTestErrorMessage = error.localizedDescription
        }
    }

    private func setupBindings() {
        $assistantIntegrations
            .dropFirst()
            .sink { [weak self] newValue in
                self?.settings.assistantIntegrations = newValue
            }
            .store(in: &cancellables)

        $selectedIntegrationId
            .dropFirst()
            .sink { [weak self] newValue in
                self?.settings.assistantSelectedIntegrationId = newValue
                self?.updateRaycastDeepLinkValidation()
            }
            .store(in: &cancellables)
    }

    private func updateRaycastDeepLinkValidation() {
        guard let selectedIntegrationId,
              let selected = assistantIntegrations.first(where: { $0.id == selectedIntegrationId })
        else {
            raycastDeepLinkIsValid = true
            raycastDeepLinkValidationMessage = nil
            return
        }

        validateDeepLink(selected.deepLink, integrationEnabled: selected.isEnabled)
    }

    private func updateIntegration(id: UUID, mutate: (inout AssistantIntegrationConfig) -> Void) {
        guard let index = assistantIntegrations.firstIndex(where: { $0.id == id }) else {
            return
        }

        var updated = assistantIntegrations
        mutate(&updated[index])
        assistantIntegrations = updated
    }

    private func normalizedIntegration(_ integration: AssistantIntegrationConfig) -> AssistantIntegrationConfig {
        var normalized = integration
        let resolvedShortcut = ShortcutDefinitionNormalizer.normalized(
            integration.shortcutDefinition,
            allowReturnOrEnter: false
        ) ??
            ShortcutDefinitionNormalizer.normalized(
                integration.modifierShortcutGesture?.asShortcutDefinition,
                allowReturnOrEnter: false
            ) ??
            ShortcutDefinitionNormalizer.normalized(
                integration.shortcutPresetKey
                    .asLegacyModifierGesture(activationMode: integration.shortcutActivationMode)?
                    .asShortcutDefinition,
                allowReturnOrEnter: false
            )

        normalized.shortcutDefinition = resolvedShortcut
        normalized.modifierShortcutGesture = resolvedShortcut?.asModifierShortcutGesture
        return normalized
    }

    private func modifierConflictMessage(for integration: AssistantIntegrationConfig) -> String? {
        guard integration.isEnabled else {
            return nil
        }

        let resolvedShortcut = ShortcutDefinitionNormalizer.normalized(
            integration.shortcutDefinition,
            allowReturnOrEnter: false
        ) ??
            ShortcutDefinitionNormalizer.normalized(
                integration.modifierShortcutGesture?.asShortcutDefinition,
                allowReturnOrEnter: false
            ) ??
            ShortcutDefinitionNormalizer.normalized(
                integration.shortcutPresetKey
                    .asLegacyModifierGesture(activationMode: integration.shortcutActivationMode)?
                    .asShortcutDefinition,
                allowReturnOrEnter: false
            )
        guard let resolvedShortcut else {
            return nil
        }

        let candidate = ShortcutBinding(
            actionID: .assistantIntegration(integration.id),
            actionDisplayName: integration.name,
            shortcut: resolvedShortcut
        )

        guard let conflict = settings.shortcutConflict(for: candidate) else {
            return nil
        }

        switch conflict.reason {
        case .systemReserved:
            return "settings.shortcuts.modifier.system_reserved".localized
        case .layerLeaderKeyCollision,
             .identicalSignature,
             .effectiveModifierOverlap,
             .sideSpecificVsAgnosticOverlap,
             .assistantIntegrationConcurrentActivation:
            return "settings.shortcuts.modifier.conflict".localized(with: conflict.conflicting.actionDisplayName)
        }
    }

    private static func executeScript(script: String, input: String) async throws -> String? {
        try await AssistantBashScriptRunner().run(script: script, input: input, timeoutSeconds: 15)
    }
}
