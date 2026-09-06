import Combine
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure

@MainActor
public final class MeetingNotesShortcutSettingsViewModel: ObservableObject {
    private let settings = AppSettingsStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingShortcutChange = false

    @Published public var meetingNotesShortcutDefinition: ShortcutDefinition?
    @Published public var meetingNotesShortcutConflictMessage: String?

    public init() {
        meetingNotesShortcutDefinition = settings.meetingNotesShortcutDefinition
        meetingNotesShortcutConflictMessage = nil
        setupBindings()
    }

    private func setupBindings() {
        $meetingNotesShortcutDefinition
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.handleMeetingNotesShortcutDefinitionChange(newValue)
            }
            .store(in: &cancellables)
    }

    private func handleMeetingNotesShortcutDefinitionChange(_ newValue: ShortcutDefinition?) {
        guard !isApplyingShortcutChange else {
            return
        }

        guard let newValue else {
            settings.meetingNotesShortcutDefinition = nil
            meetingNotesShortcutConflictMessage = nil
            return
        }

        guard let normalizedValue = ShortcutDefinitionNormalizer.normalized(newValue) else {
            revertChange(with: "settings.shortcuts.modifier.primary_key_required".localized)
            return
        }

        guard GlobalHotkeyMapper.descriptor(for: normalizedValue) != nil else {
            revertChange(with: "settings.general.cancel_recording_shortcut_unsupported".localized)
            return
        }

        let candidate = ShortcutBinding(
            actionID: .meetingNotes,
            actionDisplayName: "settings.meetings.notes_panel.shortcut".localized,
            shortcut: normalizedValue,
        )

        if let conflict = settings.shortcutConflict(for: candidate) {
            revertChange(with: conflictMessage(for: conflict))
            return
        }

        settings.meetingNotesShortcutDefinition = normalizedValue
        meetingNotesShortcutConflictMessage = nil
    }

    private func revertChange(with message: String) {
        isApplyingShortcutChange = true
        meetingNotesShortcutDefinition = settings.meetingNotesShortcutDefinition
        meetingNotesShortcutConflictMessage = message
        isApplyingShortcutChange = false
    }

    private func conflictMessage(for conflict: ShortcutConflict) -> String {
        switch conflict.reason {
        case .systemReserved:
            "settings.shortcuts.modifier.system_reserved".localized
        case .layerLeaderKeyCollision,
             .identicalSignature,
             .effectiveModifierOverlap,
             .sideSpecificVsAgnosticOverlap,
             .assistantIntegrationConcurrentActivation:
            "settings.shortcuts.modifier.conflict".localized(with: conflict.conflicting.actionDisplayName)
        }
    }
}
