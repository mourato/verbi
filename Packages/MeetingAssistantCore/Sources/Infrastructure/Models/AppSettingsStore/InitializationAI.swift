import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

extension AppSettingsStore {
    /// Struct for AI configuration values to avoid large tuple.
    struct AIConfigurationValues {
        let aiConfiguration: AIConfiguration
        let enhancementsAISelection: EnhancementsAISelection
        let enhancementsDictationAISelection: EnhancementsAISelection
        let enhancementsProviderSelectedModels: [String: String]
        let enhancementsProviderRegistrations: [EnhancementsProviderRegistration]
        let enhancementsProviderSelectedModelsByRegistration: [String: String]
        let transcriptionDictationSelection: TranscriptionProviderSelection
        let transcriptionProviderSelectedModels: [String: String]
        let meetingTranscriptionLocalModel: LocalTranscriptionModel
    }

    /// Loads AI configuration properties from the context.
    static func loadAIConfigurationValues(from context: InitializationContext) -> AIConfigurationValues {
        let legacyEnhancementsProviderSelectedModels = loadEnhancementsProviderSelectedModels(
            defaultMeetingSelection: context.loadedEnhancementsSelection,
            defaultDictationSelection: context.loadedDictationSelection
        )

        let enhancementsProviderRegistrations = loadEnhancementsProviderRegistrations(
            aiConfiguration: context.loadedAIConfiguration,
            meetingSelection: context.loadedEnhancementsSelection,
            dictationSelection: context.loadedDictationSelection,
            legacyProviderSelectedModels: legacyEnhancementsProviderSelectedModels
        )

        let normalizedMeetingSelection = normalizedEnhancementsSelection(
            context.loadedEnhancementsSelection,
            registrations: enhancementsProviderRegistrations
        )
        let normalizedDictationSelection = normalizedEnhancementsSelection(
            context.loadedDictationSelection,
            registrations: enhancementsProviderRegistrations
        )

        let enhancementsProviderSelectedModelsByRegistration = loadEnhancementsProviderSelectedModelsByRegistration(
            registrations: enhancementsProviderRegistrations,
            legacyProviderSelectedModels: legacyEnhancementsProviderSelectedModels,
            meetingSelection: normalizedMeetingSelection,
            dictationSelection: normalizedDictationSelection
        )

        let transcriptionDictationSelection = loadTranscriptionDictationSelection()
        let transcriptionProviderSelectedModels = loadTranscriptionProviderSelectedModels(
            defaultDictationSelection: transcriptionDictationSelection
        )
        let meetingTranscriptionLocalModel = loadMeetingTranscriptionLocalModel(
            transcriptionProviderSelectedModels: transcriptionProviderSelectedModels
        )

        return AIConfigurationValues(
            aiConfiguration: context.loadedAIConfiguration,
            enhancementsAISelection: normalizedMeetingSelection,
            enhancementsDictationAISelection: normalizedDictationSelection,
            enhancementsProviderSelectedModels: legacyEnhancementsProviderSelectedModels,
            enhancementsProviderRegistrations: enhancementsProviderRegistrations,
            enhancementsProviderSelectedModelsByRegistration: enhancementsProviderSelectedModelsByRegistration,
            transcriptionDictationSelection: transcriptionDictationSelection,
            transcriptionProviderSelectedModels: transcriptionProviderSelectedModels,
            meetingTranscriptionLocalModel: meetingTranscriptionLocalModel
        )
    }
}
