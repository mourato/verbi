import Foundation
import KeyboardShortcuts
import MeetingAssistantCore

@MainActor
extension AssistantShortcutController {
    func refreshEventMonitors() {
        guard settings.isAssistantEnabled else {
            removeEventMonitors()
            return
        }

        // Global runtime now uses direct hotkeys + KeyboardShortcuts custom handlers.
        // Keep monitor backend disabled for global capture.
        inputBackend.stopAllMonitoring()
        refreshDirectHotkeys()

        runShortcutCaptureHealthCheck(
            source: "refresh_event_monitors",
            expectation: expectedShortcutCaptureBackends()
        )

        AppLogger.debug(
            "Assistant shortcut hotkey refresh",
            category: .assistant,
            extra: [
                "assistantInHouseHotkeys": hotkeyBackend.registeredHotkeyCount,
                "assistantCustomEnabled": isAssistantCustomShortcutEnabled,
                "integrationCustomEnabledCount": integrationCustomEnabledCount
            ]
        )
    }

    func refreshCustomShortcutRegistration() {
        guard settings.isAssistantEnabled else {
            KeyboardShortcuts.disable(.assistantCommand)
            return
        }

        switch settings.assistantSelectedPresetKey {
        case .custom where settings.assistantModifierShortcutGesture == nil && settings.assistantShortcutDefinition == nil:
            KeyboardShortcuts.enable(.assistantCommand)
        default:
            KeyboardShortcuts.disable(.assistantCommand)
        }
    }

    func refreshIntegrationCustomShortcutRegistrations() {
        let currentIDs = Set(settings.assistantIntegrations.map(\.id))
        for removedID in registeredIntegrationShortcutIDs.subtracting(currentIDs) {
            KeyboardShortcuts.disable(.assistantIntegration(removedID))
            integrationShortcutHandlers.removeValue(forKey: removedID)
            integrationPresetStates.removeValue(forKey: removedID)
        }

        guard settings.isAssistantEnabled, settings.isAssistantIntegrationsEnabled else {
            for integrationID in currentIDs {
                KeyboardShortcuts.disable(.assistantIntegration(integrationID))
            }
            registeredIntegrationShortcutIDs = currentIDs
            return
        }

        for integration in settings.assistantIntegrations {
            let shortcutName = KeyboardShortcuts.Name.assistantIntegration(integration.id)

            if !registeredIntegrationShortcutIDs.contains(integration.id) {
                KeyboardShortcuts.onKeyDown(for: shortcutName) { [weak self] in
                    Task { @MainActor in
                        await self?.handleIntegrationCustomShortcutDown(integrationID: integration.id)
                    }
                }

                KeyboardShortcuts.onKeyUp(for: shortcutName) { [weak self] in
                    Task { @MainActor in
                        await self?.handleIntegrationCustomShortcutUp(integrationID: integration.id)
                    }
                }
            }

            if integration.isEnabled,
               integration.shortcutDefinition == nil,
               integration.modifierShortcutGesture == nil,
               integration.shortcutPresetKey == .custom
            {
                KeyboardShortcuts.enable(shortcutName)
            } else {
                KeyboardShortcuts.disable(shortcutName)
            }
        }

        registeredIntegrationShortcutIDs = currentIDs
    }

    func removeEventMonitors() {
        inputBackend.stopAllMonitoring()
        hotkeyBackend.unregisterAll()
        shortcutLayerKeySuppressor.stop()
        runShortcutCaptureHealthCheck(
            source: "event_monitors_removed",
            expectation: ShortcutCaptureBackendExpectation.none
        )
    }

    private func refreshDirectHotkeys() {
        var registrations: [HotkeyRegistration] = []

        if let assistantRegistration = assistantInHouseRegistration() {
            registrations.append(assistantRegistration)
        }

        registrations.append(contentsOf: integrationInHouseRegistrations())
        hotkeyBackend.registerAll(registrations)
    }

    private func assistantInHouseRegistration() -> HotkeyRegistration? {
        guard settings.isAssistantEnabled,
              let definition = settings.assistantShortcutDefinition,
              let descriptor = GlobalHotkeyMapper.descriptor(for: definition)
        else {
            return nil
        }

        let activationMode = definition.trigger.asShortcutActivationMode
        return HotkeyRegistration(
            id: "assistant.main",
            keyCode: descriptor.keyCode,
            modifiers: descriptor.modifiers,
            onKeyDown: { [weak self] in
                guard let self else { return }
                emitShortcutDetected(
                    shortcutTarget: "assistant",
                    source: "in_house_hotkey",
                    trigger: activationMode
                )
                Task { @MainActor [weak self] in
                    await self?.handleShortcutDown(activationModeOverride: activationMode)
                }
            },
            onKeyUp: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.handleShortcutUp(activationModeOverride: activationMode)
                }
            }
        )
    }

    private func integrationInHouseRegistrations() -> [HotkeyRegistration] {
        guard settings.isAssistantEnabled, settings.isAssistantIntegrationsEnabled else {
            return []
        }

        return settings.assistantIntegrations.compactMap { integration in
            guard integration.isEnabled,
                  let definition = integration.shortcutDefinition,
                  let descriptor = GlobalHotkeyMapper.descriptor(for: definition)
            else {
                return nil
            }

            let activationMode = definition.trigger.asShortcutActivationMode
            return HotkeyRegistration(
                id: "assistant.integration.\(integration.id.uuidString)",
                keyCode: descriptor.keyCode,
                modifiers: descriptor.modifiers,
                onKeyDown: { [weak self] in
                    guard let self else { return }
                    emitShortcutDetected(
                        shortcutTarget: "integration",
                        source: "integration_in_house_hotkey",
                        trigger: activationMode
                    )
                    Task { @MainActor [weak self] in
                        await self?.handleIntegrationShortcutDown(
                            integrationID: integration.id,
                            activationModeOverride: activationMode
                        )
                    }
                },
                onKeyUp: { [weak self] in
                    Task { @MainActor [weak self] in
                        await self?.handleIntegrationShortcutUp(
                            integrationID: integration.id,
                            activationModeOverride: activationMode
                        )
                    }
                }
            )
        }
    }

    var isAssistantCustomShortcutEnabled: Bool {
        settings.isAssistantEnabled
            && settings.assistantSelectedPresetKey == .custom
            && settings.assistantModifierShortcutGesture == nil
            && settings.assistantShortcutDefinition == nil
    }

    var integrationCustomEnabledCount: Int {
        guard settings.isAssistantEnabled, settings.isAssistantIntegrationsEnabled else {
            return 0
        }

        return settings.assistantIntegrations.count(where: { integration in
            integration.isEnabled
                && integration.shortcutDefinition == nil
                && integration.modifierShortcutGesture == nil
                && integration.shortcutPresetKey == .custom
        })
    }

    func expectedShortcutCaptureBackends() -> ShortcutCaptureBackendExpectation {
        let hasAnyGlobalShortcut = hotkeyBackend.registeredHotkeyCount > 0
            || isAssistantCustomShortcutEnabled
            || integrationCustomEnabledCount > 0

        return ShortcutCaptureBackendExpectation(
            needsGlobalCapture: hasAnyGlobalShortcut,
            needsFlagsMonitor: false,
            needsKeyDownMonitor: false,
            needsKeyUpMonitor: false,
            needsEventTap: false
        )
    }

    func startShortcutCaptureHealthChecks() {
        stopShortcutCaptureHealthChecks()
        runShortcutCaptureHealthCheck(source: "controller_start")

        let timer = Timer.scheduledTimer(withTimeInterval: healthCheckIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runShortcutCaptureHealthCheck(source: "periodic")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        healthCheckTimer = timer
    }

    func stopShortcutCaptureHealthChecks() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
    }

    func runShortcutCaptureHealthCheck(
        source: String,
        expectation: ShortcutCaptureBackendExpectation? = nil
    ) {
        let expectedBackends = expectation ?? expectedShortcutCaptureBackends()
        let previousSnapshot = shortcutCaptureHealthSnapshot
        let snapshot = ShortcutCaptureHealthSnapshot(
            pipeline: "assistant_shortcuts",
            scope: "assistant",
            source: source,
            expectation: expectedBackends,
            accessibilityTrusted: true,
            flagsMonitorActive: false,
            keyDownMonitorActive: false,
            keyUpMonitorActive: false,
            eventTapActive: false
        )

        shortcutCaptureHealthSnapshot = snapshot
        ShortcutCaptureHealthStore.updateHealth(
            scope: .assistant,
            result: snapshot.result.rawValue,
            reasonToken: snapshot.result == .degraded ? snapshot.reasonToken : "",
            requiresGlobalCapture: snapshot.requiresGlobalCapture,
            accessibilityTrusted: snapshot.accessibilityTrusted,
            eventTapExpected: snapshot.eventTapExpected,
            eventTapActive: snapshot.eventTapActive
        )
        emitShortcutCaptureHealthTransitionIfNeeded(previous: previousSnapshot, current: snapshot)
    }

    func emitShortcutCaptureHealthTransitionIfNeeded(
        previous: ShortcutCaptureHealthSnapshot?,
        current: ShortcutCaptureHealthSnapshot
    ) {
        guard previous?.operationalSignature != current.operationalSignature else {
            return
        }

        ShortcutTelemetry.emit(
            .captureHealthChanged(
                pipeline: current.pipeline,
                scope: current.scope,
                source: current.source,
                result: current.result.rawValue,
                previousResult: previous?.result.rawValue,
                reason: current.result == .degraded ? current.reasonToken : nil,
                requiresGlobalCapture: current.requiresGlobalCapture,
                accessibilityTrusted: current.accessibilityTrusted,
                flagsMonitorExpected: current.flagsMonitorExpected,
                flagsMonitorActive: current.flagsMonitorActive,
                keyDownMonitorExpected: current.keyDownMonitorExpected,
                keyDownMonitorActive: current.keyDownMonitorActive,
                keyUpMonitorExpected: current.keyUpMonitorExpected,
                keyUpMonitorActive: current.keyUpMonitorActive,
                eventTapExpected: current.eventTapExpected,
                eventTapActive: current.eventTapActive,
                checkedAtEpochMs: Int64(current.checkedAt.timeIntervalSince1970 * 1000)
            ),
            category: .assistant
        )
    }
}
