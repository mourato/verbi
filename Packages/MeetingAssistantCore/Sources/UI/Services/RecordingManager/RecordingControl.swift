import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

// MARK: - Recording Control State

extension RecordingManager {
    func clearActiveTranscriptionSnapshot() {
        activeTranscriptionConfiguration = nil
        activeVocabularySnapshot = nil
        activeUseCaseConfig = nil
        activeAutoExportSummaries = nil
        activeDeliverySettings = nil
    }

    func makeTranscriptionSessionSnapshot(_ meeting: Meeting) -> TranscriptionSessionSnapshot {
        let settings = activeUseCaseConfig == nil ? AppSettingsStore.shared : nil
        let kernelMode = postProcessingKernelMode(
            for: meeting,
            capturePurposeOverride: meeting.capturePurpose
        )
        var resolvedContextItems = postProcessingContextItems
        if let meetingNotesItem = meetingNotesContextItem(
            from: MeetingNotesContent(
                plainText: currentMeetingNotesText,
                richTextRTFData: currentMeetingNotesRichTextData
            ),
            capturePurpose: meeting.capturePurpose
        ) {
            if let existingIndex = resolvedContextItems.firstIndex(where: { $0.source == .meetingNotes }) {
                resolvedContextItems[existingIndex] = meetingNotesItem
            } else {
                resolvedContextItems.append(meetingNotesItem)
            }
        }
        var snapshot = TranscriptionSessionSnapshot(
            id: meeting.id,
            meeting: meeting,
            recordingSource: recordingSource,
            kernelMode: kernelMode,
            postProcessingContext: postProcessingContext,
            postProcessingContextItems: resolvedContextItems,
            meetingNotesContent: MeetingNotesContent(
                plainText: currentMeetingNotesText,
                richTextRTFData: currentMeetingNotesRichTextData
            ),
            dictationSessionOutputLanguageOverride: dictationSessionOutputLanguageOverride,
            dictationStartBundleIdentifier: dictationStartBundleIdentifier,
            dictationStartURL: dictationStartURL,
            dictationStyleID: activeDictationStyleSnapshot?.id,
            dictationTextHandlingPolicy: activeDictationStyleSnapshot?.textHandlingPolicy,
            dictationTranscriptionConfiguration: activeDictationStyleSnapshot?.transcriptionConfiguration,
            transcriptionConfiguration: activeTranscriptionConfiguration,
            dictationEnhancementsSelection: activeDictationStyleSnapshot?.enhancementsSelection,
            postProcessingEnhancementsSelection: activeUseCaseConfig?.postProcessingSelection
                ?? settings?.enhancementsSelection(for: kernelMode),
            dictationPostProcessingEnabled: activeDictationStyleSnapshot?.postProcessingEnabled,
            dictationStyle: activeDictationStyleSnapshot,
            vocabularySnapshot: activeVocabularySnapshot
                ?? settings.map { VocabularySnapshot.current(from: $0) }
                ?? .empty,
            useCaseConfig: activeUseCaseConfig,
            autoExportSummaries: activeAutoExportSummaries ?? settings?.autoExportSummaries ?? false,
            deliverySettings: activeDeliverySettings
                ?? settings.map { DeliverySettingsSnapshot(settings: $0) }
        )
        if snapshot.useCaseConfig == nil, let settings {
            snapshot.useCaseConfig = makeUseCaseConfig(session: snapshot, settings: settings)
        }
        if let config = snapshot.useCaseConfig {
            snapshot.useCaseConfig = useCaseConfig(config, for: meeting)
        }
        return snapshot
    }

    private func useCaseConfig(_ config: UseCaseConfig, for meeting: Meeting) -> UseCaseConfig {
        guard config.applyPostProcessing, meeting.capturePurpose == .meeting else { return config }

        var resolved = config
        switch meeting.type {
        case .autodetect:
            resolved.postProcessingPrompt = nil
            resolved.defaultPostProcessingPrompt = config.defaultPostProcessingPrompt ?? config.postProcessingPrompt
            resolved.autoDetectMeetingType = true
        case .general:
            resolved.postProcessingPrompt = config.autoDetectMeetingType
                ? config.defaultPostProcessingPrompt
                : config.postProcessingPrompt
            resolved.defaultPostProcessingPrompt = nil
            resolved.autoDetectMeetingType = false
        case .standup:
            resolved.postProcessingPrompt = domainPrompt(
                from: postProcessingConfigurationProvider.promptWithMeetingSummaryOverrides(prompt: .standup)
            )
            resolved.defaultPostProcessingPrompt = nil
            resolved.autoDetectMeetingType = false
        case .presentation:
            resolved.postProcessingPrompt = domainPrompt(
                from: postProcessingConfigurationProvider.promptWithMeetingSummaryOverrides(prompt: .presentation)
            )
            resolved.defaultPostProcessingPrompt = nil
            resolved.autoDetectMeetingType = false
        case .designReview:
            resolved.postProcessingPrompt = domainPrompt(
                from: postProcessingConfigurationProvider.promptWithMeetingSummaryOverrides(prompt: .designReview)
            )
            resolved.defaultPostProcessingPrompt = nil
            resolved.autoDetectMeetingType = false
        case .oneOnOne:
            resolved.postProcessingPrompt = domainPrompt(
                from: postProcessingConfigurationProvider.promptWithMeetingSummaryOverrides(prompt: .oneOnOne)
            )
            resolved.defaultPostProcessingPrompt = nil
            resolved.autoDetectMeetingType = false
        case .planning:
            resolved.postProcessingPrompt = domainPrompt(
                from: postProcessingConfigurationProvider.promptWithMeetingSummaryOverrides(prompt: .planning)
            )
            resolved.defaultPostProcessingPrompt = nil
            resolved.autoDetectMeetingType = false
        }
        return resolved
    }
}

// MARK: - Dictation Language

public extension RecordingManager {
    var effectiveDictationOutputLanguageForCurrentRecording: DictationOutputLanguage {
        if let override = dictationSessionOutputLanguageOverride {
            return override
        }

        let settings = AppSettingsStore.shared
        return matchingDictationAppRule(settings: settings)?.outputLanguage ?? .original
    }

    func setDictationSessionOutputLanguageOverride(_ language: DictationOutputLanguage?) {
        dictationSessionOutputLanguageOverride = language
    }
}

// MARK: - VocabularySnapshot Factory

@MainActor
extension VocabularySnapshot {
    /// Creates a snapshot from the current `AppSettingsStore` values.
    static func current(from settings: AppSettingsStore) -> VocabularySnapshot {
        VocabularySnapshot(
            terms: settings.vocabularyTerms,
            replacementRules: settings.vocabularyReplacementRules
        )
    }
}
