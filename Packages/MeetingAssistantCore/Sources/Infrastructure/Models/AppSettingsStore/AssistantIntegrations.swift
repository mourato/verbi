import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain

public extension AppSettingsStore {
    /// Active integration resolved from selected ID.
    var assistantSelectedIntegration: AssistantIntegrationConfig? {
        if let id = assistantSelectedIntegrationId,
           let selected = assistantIntegrations.first(where: { $0.id == id })
        {
            return selected
        }
        return assistantIntegrations.first
    }

    /// Snapshot of all currently configured shortcuts in the normalized in-house format.
    var configuredShortcutBindings: [ShortcutBinding] {
        var bindings: [ShortcutBinding] = []

        appendResolvedShortcutBinding(
            to: &bindings,
            actionID: .dictation,
            actionDisplayName: "settings.shortcuts.dictation".localized,
            shortcut: dictationShortcutDefinition,
            explicitGesture: dictationModifierShortcutGesture,
            legacyPresetKey: dictationSelectedPresetKey,
            activationMode: dictationShortcutActivationMode,
            allowReturnOrEnter: false,
        )

        appendResolvedShortcutBinding(
            to: &bindings,
            actionID: .assistant,
            actionDisplayName: "settings.assistant.toggle_command".localized,
            shortcut: assistantShortcutDefinition,
            explicitGesture: assistantModifierShortcutGesture,
            legacyPresetKey: assistantSelectedPresetKey,
            activationMode: assistantShortcutActivationMode,
            allowReturnOrEnter: false,
        )

        appendResolvedShortcutBinding(
            to: &bindings,
            actionID: .meeting,
            actionDisplayName: "settings.shortcuts.meeting".localized,
            shortcut: meetingShortcutDefinition,
            explicitGesture: meetingModifierShortcutGesture,
            legacyPresetKey: meetingSelectedPresetKey,
            activationMode: shortcutActivationMode,
        )

        if let cancelRecordingShortcutDefinition,
           !cancelRecordingShortcutDefinition.isEmpty,
           GlobalHotkeyMapper.descriptor(for: cancelRecordingShortcutDefinition) != nil
        {
            bindings.append(
                ShortcutBinding(
                    actionID: .cancelActiveRecording,
                    actionDisplayName: "settings.general.cancel_recording_shortcut".localized,
                    shortcut: cancelRecordingShortcutDefinition,
                ),
            )
        }

        if let meetingNotesShortcutDefinition,
           !meetingNotesShortcutDefinition.isEmpty,
           GlobalHotkeyMapper.descriptor(for: meetingNotesShortcutDefinition) != nil
        {
            bindings.append(
                ShortcutBinding(
                    actionID: .meetingNotes,
                    actionDisplayName: "settings.meetings.notes_panel.shortcut".localized,
                    shortcut: meetingNotesShortcutDefinition,
                ),
            )
        }

        for integration in assistantIntegrations where integration.isEnabled {
            let resolvedShortcut = integration.shortcutDefinition
                .flatMap {
                    normalizedInHouseShortcutDefinition(
                        $0,
                        activationMode: integration.shortcutActivationMode,
                        allowReturnOrEnter: false,
                    )
                } ??
                integration.modifierShortcutGesture
                .flatMap {
                    normalizedInHouseShortcutDefinition(
                        $0.asShortcutDefinition,
                        activationMode: integration.shortcutActivationMode,
                        allowReturnOrEnter: false,
                    )
                } ??
                integration.shortcutPresetKey
                .asLegacyModifierGesture(activationMode: integration.shortcutActivationMode)
                .flatMap {
                    normalizedInHouseShortcutDefinition(
                        $0.asShortcutDefinition,
                        activationMode: integration.shortcutActivationMode,
                        allowReturnOrEnter: false,
                    )
                }

            guard let resolvedShortcut, !resolvedShortcut.isEmpty else {
                continue
            }

            bindings.append(
                ShortcutBinding(
                    actionID: .assistantIntegration(integration.id),
                    actionDisplayName: integration.name,
                    shortcut: resolvedShortcut,
                ),
            )
        }

        return bindings
    }

    func shortcutConflict(for candidate: ShortcutBinding) -> ShortcutConflict? {
        if Self.isSystemReservedShortcut(candidate.shortcut) {
            return ShortcutConflict(
                candidate: candidate,
                conflicting: ShortcutBinding(
                    actionID: .systemReserved,
                    actionDisplayName: "macOS",
                    shortcut: candidate.shortcut,
                ),
                reason: .systemReserved,
            )
        }

        return ModifierShortcutConflictService.conflict(
            for: candidate,
            in: configuredShortcutBindings,
            context: ShortcutConflictContext(),
        )
    }

    var shortcutConflicts: [ShortcutConflict] {
        ModifierShortcutConflictService.allConflicts(
            in: configuredShortcutBindings,
            context: ShortcutConflictContext(),
        )
    }

    func upsertAssistantIntegration(_ integration: AssistantIntegrationConfig) {
        if let index = assistantIntegrations.firstIndex(where: { $0.id == integration.id }) {
            var updated = assistantIntegrations
            updated[index] = integration
            assistantIntegrations = updated
        } else {
            var updated = assistantIntegrations
            updated.append(integration)
            assistantIntegrations = updated

            if assistantSelectedIntegrationId == nil {
                assistantSelectedIntegrationId = integration.id
            }
        }
    }

    func removeAssistantIntegration(id: UUID) {
        let filtered = assistantIntegrations.filter { $0.id != id }
        guard filtered.count != assistantIntegrations.count else { return }
        assistantIntegrations = filtered
    }

    private static func isSystemReservedShortcut(_ shortcut: ShortcutDefinition) -> Bool {
        guard shortcut.trigger == .singleTap,
              let primaryKey = shortcut.primaryKey
        else {
            return false
        }

        let hasCommand = shortcut.modifiers.contains { modifier in
            switch modifier {
            case .command, .leftCommand, .rightCommand:
                true
            default:
                false
            }
        }
        let hasShift = shortcut.modifiers.contains { modifier in
            switch modifier {
            case .shift, .leftShift, .rightShift:
                true
            default:
                false
            }
        }
        let hasOption = shortcut.modifiers.contains { modifier in
            switch modifier {
            case .option, .leftOption, .rightOption:
                true
            default:
                false
            }
        }
        let hasControl = shortcut.modifiers.contains { modifier in
            switch modifier {
            case .control, .leftControl, .rightControl:
                true
            default:
                false
            }
        }

        guard hasCommand, !hasOption, !hasControl else {
            return false
        }

        if primaryKey.kind == .space {
            return true
        }

        let token = primaryKey.display.lowercased()
        if hasShift {
            return token == "z"
        }

        switch token {
        case "a", "c", "f", "h", "m", "n", "o", "p", "q", "s", "v", "w", "x", "z", ",":
            return true
        default:
            return false
        }
    }
}

extension AppSettingsStore {
    static func resolveShortcutDefinition(
        explicitGesture: ModifierShortcutGesture?,
        legacyPresetKey: PresetShortcutKey,
        activationMode: ShortcutActivationMode,
        allowReturnOrEnter: Bool = true,
    ) -> ShortcutDefinition? {
        if let explicitGesture {
            return normalizedInHouseShortcutDefinition(
                explicitGesture.asShortcutDefinition,
                activationMode: activationMode,
                allowReturnOrEnter: allowReturnOrEnter,
            )
        }

        guard let legacyGesture = legacyPresetKey.asLegacyModifierGesture(activationMode: activationMode) else {
            return nil
        }

        return normalizedInHouseShortcutDefinition(
            legacyGesture.asShortcutDefinition,
            activationMode: activationMode,
            allowReturnOrEnter: allowReturnOrEnter,
        )
    }

    func appendResolvedShortcutBinding(
        to bindings: inout [ShortcutBinding],
        actionID: ModifierShortcutActionID,
        actionDisplayName: String,
        shortcut: ShortcutDefinition?,
        explicitGesture: ModifierShortcutGesture?,
        legacyPresetKey: PresetShortcutKey,
        activationMode: ShortcutActivationMode,
        allowReturnOrEnter: Bool = true,
    ) {
        let resolvedShortcut = shortcut ??
            Self.resolveShortcutDefinition(
                explicitGesture: explicitGesture,
                legacyPresetKey: legacyPresetKey,
                activationMode: activationMode,
                allowReturnOrEnter: allowReturnOrEnter,
            )
        guard let resolvedShortcut, !resolvedShortcut.isEmpty else {
            return
        }

        bindings.append(
            ShortcutBinding(
                actionID: actionID,
                actionDisplayName: actionDisplayName,
                shortcut: resolvedShortcut,
            ),
        )
    }

    func synchronizeAssistantIntegrationsState() {
        var normalizedIntegrations = assistantIntegrations

        if normalizedIntegrations.isEmpty {
            normalizedIntegrations = [AssistantIntegrationConfig.defaultRaycast]
        }

        normalizedIntegrations = normalizedIntegrations.map { integration in
            var normalized = integration

            let normalizedShortcut = normalized.shortcutDefinition
                .flatMap {
                    normalizedInHouseShortcutDefinition(
                        $0,
                        activationMode: normalized.shortcutActivationMode,
                        allowReturnOrEnter: false,
                    )
                } ??
                normalized.modifierShortcutGesture
                .flatMap {
                    normalizedInHouseShortcutDefinition(
                        $0.asShortcutDefinition,
                        activationMode: normalized.shortcutActivationMode,
                        allowReturnOrEnter: false,
                    )
                } ??
                normalized.shortcutPresetKey
                .asLegacyModifierGesture(activationMode: normalized.shortcutActivationMode)
                .flatMap {
                    normalizedInHouseShortcutDefinition(
                        $0.asShortcutDefinition,
                        activationMode: normalized.shortcutActivationMode,
                        allowReturnOrEnter: false,
                    )
                }
            normalized.shortcutDefinition = normalizedShortcut

            if let canonicalGesture = normalized.shortcutDefinition?.asModifierShortcutGesture {
                normalized.modifierShortcutGesture = canonicalGesture
                normalized.shortcutPresetKey = .custom
                normalized.shortcutActivationMode = canonicalGesture.triggerMode.asShortcutActivationMode
            }

            guard normalized.id == AssistantIntegrationConfig.raycastDefaultID else {
                return normalized
            }

            normalized.shortcutPresetKey = .custom
            normalized.shortcutActivationMode = .toggle
            normalized.deepLink = AssistantIntegrationConfig.defaultRaycastDeepLink
            if normalized.shortcutDefinition == nil {
                normalized.shortcutDefinition = AssistantIntegrationConfig.defaultRaycast.shortcutDefinition
            }
            return normalized
        }

        if normalizedIntegrations != assistantIntegrations {
            isSynchronizingAssistantIntegrations = true
            assistantIntegrations = normalizedIntegrations
            isSynchronizingAssistantIntegrations = false
        }

        if let selectedID = assistantSelectedIntegrationId,
           assistantIntegrations.contains(where: { $0.id == selectedID }) == false
        {
            assistantSelectedIntegrationId = assistantIntegrations.first?.id
        }

        if assistantSelectedIntegrationId == nil {
            assistantSelectedIntegrationId = assistantIntegrations.first?.id
        }

        if let raycast = assistantIntegrations.first(where: { $0.id == AssistantIntegrationConfig.raycastDefaultID }) {
            assistantRaycastEnabled = raycast.isEnabled
            assistantRaycastDeepLink = raycast.deepLink
        }
    }
}
