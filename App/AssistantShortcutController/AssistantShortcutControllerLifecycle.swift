import AppKit
import Combine
import Foundation
import MeetingAssistantCore

@MainActor
extension AssistantShortcutController {
    func start() {
        guard !isStarted else { return }
        isStarted = true

        observeSettings()
        observeAssistantRecordingState()
        observeLifecycleEvents()
        applyGlobalDoubleTapInterval()
        refreshIntegrationCustomShortcutRegistrations()
        refreshEventMonitors()
        startShortcutCaptureHealthChecks()
    }

    func refresh() {
        guard isStarted else { return }
        resetShortcutState()
        refreshIntegrationCustomShortcutRegistrations()
        refreshEventMonitors()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        stopShortcutCaptureHealthChecks()
        removeEventMonitors()
        resetShortcutState()
        registeredIntegrationShortcutIDs.removeAll()
        integrationShortcutHandlers.removeAll()
        integrationPresetStates.removeAll()
        cancellables.removeAll()

        runShortcutCaptureHealthCheck(
            source: "controller_stop",
            expectation: ShortcutCaptureBackendExpectation.none
        )
    }

    private func observeSettings() {
        settings.$isAssistantEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetShortcutState()
                self?.refreshIntegrationCustomShortcutRegistrations()
                self?.refreshEventMonitors()
            }
            .store(in: &cancellables)

        settings.$assistantSelectedPresetKey
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetShortcutState()
                self?.refreshEventMonitors()
            }
            .store(in: &cancellables)

        settings.$assistantShortcutActivationMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetShortcutState()
            }
            .store(in: &cancellables)

        settings.$shortcutDoubleTapIntervalMilliseconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyGlobalDoubleTapInterval()
                self?.resetShortcutState()
            }
            .store(in: &cancellables)

        settings.$assistantShortcutDefinition
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetShortcutState()
                self?.refreshEventMonitors()
            }
            .store(in: &cancellables)

        settings.$assistantModifierShortcutGesture
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetShortcutState()
                self?.refreshEventMonitors()
            }
            .store(in: &cancellables)

        settings.$assistantIntegrations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetShortcutState()
                self?.refreshIntegrationCustomShortcutRegistrations()
                self?.refreshEventMonitors()
            }
            .store(in: &cancellables)
    }

    private func observeAssistantRecordingState() {
        assistantService.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshEventMonitors()
            }
            .store(in: &cancellables)
    }

    private func observeLifecycleEvents() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.runShortcutCaptureHealthCheck(source: "app_became_active")
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, isShortcutLayerArmed else {
                    return
                }

                disarmShortcutLayer(
                    showFeedback: false,
                    event: .cancelledByEscapeOrBlur,
                    transitionSource: "app_will_resign_active"
                )
            }
            .store(in: &cancellables)
    }
}
