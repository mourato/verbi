import MeetingAssistantCoreInfrastructure

@MainActor
public struct RecordingIndicatorOverlayLayout: Equatable {
    public let showsPromptSelector: Bool
    public let showsLanguageSelector: Bool
    public let showsMeetingTimer: Bool

    public var auxiliaryControlCount: Int {
        [showsPromptSelector, showsLanguageSelector].count(where: { $0 })
    }

    public static func resolve(
        renderState: RecordingIndicatorRenderState,
        settingsStore: AppSettingsStore
    ) -> RecordingIndicatorOverlayLayout {
        guard case .recording = renderState.mode else {
            return RecordingIndicatorOverlayLayout(
                showsPromptSelector: false,
                showsLanguageSelector: false,
                showsMeetingTimer: false
            )
        }

        switch renderState.kind {
        case .dictation:
            return RecordingIndicatorOverlayLayout(
                showsPromptSelector: true,
                showsLanguageSelector: true,
                showsMeetingTimer: false
            )
        case .assistant:
            return RecordingIndicatorOverlayLayout(
                showsPromptSelector: false,
                showsLanguageSelector: false,
                showsMeetingTimer: false
            )
        case .assistantIntegration:
            guard let integrationID = renderState.assistantIntegrationID,
                  let integration = settingsStore.assistantIntegrations.first(where: { $0.id == integrationID }),
                  integration.isEnabled
            else {
                return RecordingIndicatorOverlayLayout(
                    showsPromptSelector: false,
                    showsLanguageSelector: false,
                    showsMeetingTimer: false
                )
            }

            return RecordingIndicatorOverlayLayout(
                showsPromptSelector: integration.showsPromptSelectorInOverlay,
                showsLanguageSelector: integration.showsLanguageSelectorInOverlay,
                showsMeetingTimer: false
            )
        case .meeting:
            return RecordingIndicatorOverlayLayout(
                showsPromptSelector: true,
                showsLanguageSelector: false,
                showsMeetingTimer: true
            )
        }
    }
}
