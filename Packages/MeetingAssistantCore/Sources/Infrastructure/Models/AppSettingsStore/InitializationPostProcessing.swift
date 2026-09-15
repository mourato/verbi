import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

extension AppSettingsStore {
    /// Struct for post-processing settings to avoid large tuple.
    struct PostProcessingSettingsValues {
        let systemPrompt: String
        let userPrompts: [PostProcessingPrompt]
        let dictationPrompts: [PostProcessingPrompt]
        let deletedPromptIds: Set<UUID>
        let postProcessingEnabled: Bool
        let dictationStructuredPostProcessingEnabled: Bool
        let isDiarizationEnabled: Bool
        let modelResidencyTimeout: ModelResidencyTimeoutOption
        let transcriptionInputLanguageHint: TranscriptionInputLanguageHint
        let minSpeakers: Int?
        let maxSpeakers: Int?
        let numSpeakers: Int?
        let audioFormat: AudioFormat
        let selectedPromptId: UUID?
        let dictationSelectedPromptId: UUID?
        let shouldMergeAudioFiles: Bool
    }

    /// Loads post-processing related properties.
    static func loadPostProcessingSettings() -> PostProcessingSettingsValues {
        PostProcessingSettingsValues(
            systemPrompt: UserDefaults.standard.string(forKey: Keys.systemPrompt) ?? AIPromptTemplates.defaultSystemPrompt,
            userPrompts: loadDecoded([PostProcessingPrompt].self, forKey: Keys.userPrompts) ?? [],
            dictationPrompts: loadDecoded([PostProcessingPrompt].self, forKey: Keys.dictationPrompts) ?? [],
            deletedPromptIds: loadDecoded(Set<UUID>.self, forKey: Keys.deletedPromptIds) ?? [],
            postProcessingEnabled: UserDefaults.standard.bool(forKey: Keys.postProcessingEnabled),
            dictationStructuredPostProcessingEnabled: loadBoolDefaultIfUnset(forKey: Keys.dictationStructuredPostProcessingEnabled, defaultValue: false),
            isDiarizationEnabled: UserDefaults.standard.bool(forKey: Keys.isDiarizationEnabled),
            modelResidencyTimeout: loadEnum(forKey: Keys.modelResidencyTimeout, defaultValue: .minutes30),
            transcriptionInputLanguageHint: loadEnum(
                forKey: Keys.transcriptionInputLanguageHint,
                defaultValue: .automatic
            ),
            minSpeakers: loadOptionalInt(forKey: Keys.minSpeakers),
            maxSpeakers: loadOptionalInt(forKey: Keys.maxSpeakers),
            numSpeakers: loadOptionalInt(forKey: Keys.numSpeakers),
            audioFormat: loadEnum(forKey: PostProcessingKeys.audioFormat, defaultValue: .m4a),
            selectedPromptId: loadUUID(forKey: Keys.selectedPromptId),
            dictationSelectedPromptId: loadUUID(forKey: Keys.dictationSelectedPromptId),
            shouldMergeAudioFiles: loadBoolDefaultIfUnset(forKey: PostProcessingKeys.shouldMergeAudioFiles, defaultValue: true)
        )
    }
}
