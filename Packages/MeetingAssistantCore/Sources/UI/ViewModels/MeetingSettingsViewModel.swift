import AppKit
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
public class MeetingSettingsViewModel: ObservableObject {
    @Published var settings: AppSettingsStore
    @Published public var showPromptEditor = false
    @Published public var editingPrompt: PostProcessingPrompt?
    @Published public var showDeleteConfirmation = false
    @Published public var promptToDelete: PostProcessingPrompt?

    private var cancellables = Set<AnyCancellable>()

    public init(settings: AppSettingsStore = .shared) {
        self.settings = settings

        // Forward settings changes
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Prompt Management

    public var availablePrompts: [PostProcessingPrompt] {
        settings.meetingAvailablePrompts
    }

    public var selectedPromptId: UUID? {
        settings.selectedPromptId
    }

    public var isMeetingPostProcessingEnabled: Bool {
        !settings.isMeetingPostProcessingDisabled
    }

    public func setMeetingPostProcessingEnabled(_ isEnabled: Bool) {
        if isEnabled {
            if settings.selectedPromptId == AppSettingsStore.noPostProcessingPromptId {
                settings.selectedPromptId = nil
            }
        } else {
            settings.meetingTypeAutoDetectEnabled = false
            settings.selectedPromptId = AppSettingsStore.noPostProcessingPromptId
        }
    }

    public func selectPrompt(_ id: UUID, forceSelect: Bool = false) {
        let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil
            : .easeInOut(duration: 0.2)

        withAnimation(animation) {
            if forceSelect {
                settings.meetingTypeAutoDetectEnabled = false
                settings.selectedPromptId = id
            } else {
                settings.selectedPromptId = (settings.selectedPromptId == id) ? nil : id
            }
        }
    }

    public func handleSavePrompt(_ prompt: PostProcessingPrompt) {
        settings.upsertMeetingPrompt(prompt)
        showPromptEditor = false
        editingPrompt = nil
    }

    public func confirmDeletePrompt(_ prompt: PostProcessingPrompt) {
        promptToDelete = prompt
        showDeleteConfirmation = true
    }

    public func executeDelete() {
        if let prompt = promptToDelete {
            settings.deleteMeetingPrompt(id: prompt.id)
        }
        showDeleteConfirmation = false
        promptToDelete = nil
    }

    public func prepareCopy(of prompt: PostProcessingPrompt, asDuplicate: Bool) {
        var newTitle = prompt.title
        if asDuplicate {
            newTitle = "\(prompt.title) (\("settings.post_processing.duplicate".localized))"
        }

        let newPrompt = PostProcessingPrompt(
            id: UUID(),
            title: newTitle,
            promptText: prompt.promptText,
            isActive: prompt.isActive,
            icon: prompt.icon,
            description: prompt.description,
            isPredefined: false
        )
        editingPrompt = newPrompt
        showPromptEditor = true
    }

    // MARK: - Export Configuration

    public func selectExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        if panel.runModal() == .OK {
            settings.summaryExportFolder = panel.url
        }
    }
}
