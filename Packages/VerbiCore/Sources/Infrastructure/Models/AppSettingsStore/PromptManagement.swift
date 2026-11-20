import Foundation
import VerbiCoreCommon
import VerbiCoreDomain

public extension AppSettingsStore {
    func addPrompt(_ prompt: PostProcessingPrompt) {
        deletedPromptIds.remove(prompt.id)
        userPrompts.append(prompt)
    }

    func updatePrompt(_ prompt: PostProcessingPrompt) {
        deletedPromptIds.remove(prompt.id)

        if let index = userPrompts.firstIndex(where: { $0.id == prompt.id }) {
            userPrompts[index] = prompt
        } else {
            userPrompts.append(prompt)
        }
    }

    func deletePrompt(id: UUID) {
        if PostProcessingPrompt.allPredefined.contains(where: { $0.id == id }) {
            deletedPromptIds.insert(id)
        }

        userPrompts.removeAll { $0.id == id }

        if selectedPromptId == id {
            selectedPromptId = nil
        }
    }

    func upsertDictationPrompt(_ prompt: PostProcessingPrompt) {
        deletedPromptIds.remove(prompt.id)

        if let index = dictationPrompts.firstIndex(where: { $0.id == prompt.id }) {
            dictationPrompts[index] = prompt
        } else {
            dictationPrompts.append(prompt)
        }
    }

    func deleteDictationPrompt(id: UUID) {
        if PostProcessingPrompt.allPredefined.contains(where: { $0.id == id }) {
            deletedPromptIds.insert(id)
        }

        dictationPrompts.removeAll { $0.id == id }
        userPrompts.removeAll { $0.id == id }

        if dictationSelectedPromptId == id {
            dictationSelectedPromptId = nil
        }
    }

    func upsertMeetingPrompt(_ prompt: PostProcessingPrompt) {
        deletedPromptIds.remove(prompt.id)

        if let index = meetingPrompts.firstIndex(where: { $0.id == prompt.id }) {
            meetingPrompts[index] = prompt
        } else {
            meetingPrompts.append(prompt)
        }
    }

    func deleteMeetingPrompt(id: UUID) {
        if PostProcessingPrompt.allPredefined.contains(where: { $0.id == id }) {
            deletedPromptIds.insert(id)
        }

        meetingPrompts.removeAll { $0.id == id }
        userPrompts.removeAll { $0.id == id }

        if selectedPromptId == id {
            selectedPromptId = nil
        }
    }

    func resetSystemPrompt() {
        systemPrompt = AIPromptTemplates.defaultSystemPrompt
    }

    func mergedPrompts(predefined: [PostProcessingPrompt], custom: [PostProcessingPrompt]) -> [PostProcessingPrompt] {
        let visiblePredefined = predefined.filter { !deletedPromptIds.contains($0.id) }
        var customById: [UUID: PostProcessingPrompt] = [:]
        for prompt in custom where !deletedPromptIds.contains(prompt.id) {
            customById[prompt.id] = prompt
        }
        let predefinedIds = Set(visiblePredefined.map(\.id))

        var merged: [PostProcessingPrompt] = visiblePredefined.map { prompt in
            customById[prompt.id] ?? prompt
        }

        merged.append(contentsOf: custom.filter { !deletedPromptIds.contains($0.id) && !predefinedIds.contains($0.id) })
        return merged
    }

    func deduplicatedPrompts(_ prompts: [PostProcessingPrompt]) -> [PostProcessingPrompt] {
        var seen = Set<UUID>()
        var result: [PostProcessingPrompt] = []
        result.reserveCapacity(prompts.count)

        for prompt in prompts where !seen.contains(prompt.id) {
            seen.insert(prompt.id)
            result.append(prompt)
        }

        return result
    }
}
