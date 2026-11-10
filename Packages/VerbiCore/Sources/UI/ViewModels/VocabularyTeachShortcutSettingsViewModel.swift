import Combine
import Foundation
import VerbiCoreCommon
import VerbiCoreInfrastructure

@MainActor
public final class VocabularyTeachShortcutSettingsViewModel: ObservableObject {
    private let settings = AppSettingsStore.shared
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingShortcutChange = false

    @Published public var vocabularyTeachShortcutDefinition: ShortcutDefinition?
    @Published public var vocabularyTeachShortcutConflictMessage: String?

    public init() {
        vocabularyTeachShortcutDefinition = settings.vocabularyTeachShortcutDefinition
        vocabularyTeachShortcutConflictMessage = nil
        setupBindings()
    }

    private func setupBindings() {
        $vocabularyTeachShortcutDefinition
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                self?.handleShortcutDefinitionChange(newValue)
            }
            .store(in: &cancellables)
    }

    private func handleShortcutDefinitionChange(_ newValue: ShortcutDefinition?) {
        guard !isApplyingShortcutChange else {
            return
        }

        guard let newValue else {
            settings.vocabularyTeachShortcutDefinition = nil
            vocabularyTeachShortcutConflictMessage = nil
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
            actionID: .vocabularyTeach,
            actionDisplayName: "settings.shortcuts.teach_correction".localized,
            shortcut: normalizedValue
        )

        if let conflict = settings.shortcutConflict(for: candidate) {
            revertChange(with: conflictMessage(for: conflict))
            return
        }

        settings.vocabularyTeachShortcutDefinition = normalizedValue
        vocabularyTeachShortcutConflictMessage = nil
    }

    private func revertChange(with message: String) {
        isApplyingShortcutChange = true
        vocabularyTeachShortcutDefinition = settings.vocabularyTeachShortcutDefinition
        vocabularyTeachShortcutConflictMessage = message
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
