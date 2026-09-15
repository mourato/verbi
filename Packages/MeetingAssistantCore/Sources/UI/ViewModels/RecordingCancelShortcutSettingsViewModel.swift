import Combine
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure

@MainActor
public final class RecordingCancelShortcutSettingsViewModel: ObservableObject {
    private let settings = AppSettingsStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingShortcutChange = false

    @Published public var cancelRecordingShortcutDefinition: ShortcutDefinition?
    @Published public var cancelRecordingShortcutConflictMessage: String?

    public init() {
        cancelRecordingShortcutDefinition = settings.cancelRecordingShortcutDefinition
        cancelRecordingShortcutConflictMessage = nil
        setupBindings()
    }

    private func setupBindings() {
        $cancelRecordingShortcutDefinition
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.handleCancelRecordingShortcutDefinitionChange(newValue)
            }
            .store(in: &cancellables)
    }

    private func handleCancelRecordingShortcutDefinitionChange(_ newValue: ShortcutDefinition?) {
        guard !isApplyingShortcutChange else {
            return
        }

        guard let newValue else {
            settings.cancelRecordingShortcutDefinition = nil
            cancelRecordingShortcutConflictMessage = nil
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
            actionID: .cancelActiveRecording,
            actionDisplayName: "settings.general.cancel_recording_shortcut".localized,
            shortcut: normalizedValue
        )

        if let conflict = settings.shortcutConflict(for: candidate) {
            revertChange(with: conflictMessage(for: conflict))
            return
        }

        settings.cancelRecordingShortcutDefinition = normalizedValue
        cancelRecordingShortcutConflictMessage = nil
    }

    private func revertChange(with message: String) {
        isApplyingShortcutChange = true
        cancelRecordingShortcutDefinition = settings.cancelRecordingShortcutDefinition
        cancelRecordingShortcutConflictMessage = message
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
