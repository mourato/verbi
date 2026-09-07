import AppKit
import Combine
import KeyboardShortcuts
import MeetingAssistantCore
import os
import SwiftUI

extension AppDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppUpdaterContainer.shared.check()

        // Initialize Monitoring Services
        CrashReporter.shared.setup()
        PerformanceMonitor.shared.startMonitoring()
        configureNavigationService()
        configureCommandRouter()

        // Show onboarding if first launch
        if !settingsStore.hasCompletedOnboarding {
            showFirstLaunchOnboarding()
            return // Defer rest of setup until onboarding completes
        }

        setupMenuBar()
        verifyPrimaryInterfaceAfterLaunch()
        setupContextMenu()
        globalShortcutController.start()
        meetingNotesPaneShortcutController.start()
        recordingCancelShortcutController.start()
        setupCapabilityObservation()

        // Run auto-cleanup before model warmup so stale caches can be purged safely.
        Task {
            await performCleanup()
        }

        applyMeetingTranscriptionCapabilityState(isEnabled: settingsStore.isMeetingTranscriptionEnabled)
        assistantShortcutController.start()
        setupRecordingObservation()
        setupCommandMenuObservation()
        prewarmFloatingIndicatorIfEligible()
        updateMenuTitles() // Initial update

        localModelResidencyCoordinator.startMonitoring()

        configureUserInterfacePreferences()

        openSettingsOnLaunchIfEnabled()
        scheduleLaunchVisibilityRecovery()
        meetingNotesPaneController.setVisibilityHandler { [weak self] isVisible in
            self?.recordingManager.setMeetingNotesPanelVisible(isVisible)
        }
        MeetingReminderCoordinator.shared.attach(meetingNotesPaneController: meetingNotesPaneController)
        #if DEBUG
        scheduleRuntimeSmokeIfRequested()
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        localModelResidencyCoordinator.stopMonitoring()
        recordingCancelShortcutController.stop()
        meetingNotesPaneShortcutController.stop()
        PerformanceMonitor.shared.stopMonitoring()
        CrashReporter.shared.cleanup()
        MeetingReminderCoordinator.shared.detach()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard isCaptureActive else {
            return .terminateNow
        }

        guard terminationTask == nil else {
            return .terminateLater
        }

        terminationTask = Task { @MainActor [weak self] in
            await self?.stopActiveCaptureForTermination()
            self?.terminationTask = nil
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private var isCaptureActive: Bool {
        recordingManager.isRecording
            || recordingManager.isStartingRecording
            || assistantVoiceCommandService.isRecording
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func stopActiveCaptureForTermination() async {
        if recordingManager.isRecording {
            await recordingManager.stopRecording(transcribe: false)
        } else if recordingManager.isStartingRecording {
            await recordingManager.cancelRecording()
        }

        if assistantVoiceCommandService.isRecording {
            await assistantVoiceCommandService.cancelRecording()
        }
    }

    // MARK: - Onboarding

    func showFirstLaunchOnboarding() {
        promoteAppForWindowPresentation()
        presentOnboarding { [weak self] in
            self?.completeOnboarding()
        }
    }

    func presentOnboarding(completion: @escaping () -> Void) {
        let permissionViewModel = PermissionViewModel(
            manager: recordingManager.permissionStatus,
            requestMicrophone: { [weak self] in
                await self?.recordingManager.requestPermission(for: .microphone)
            },
            requestScreen: { [weak self] in
                await self?.recordingManager.requestPermission(for: .all)
            },
            openMicrophoneSettings: { [weak self] in
                self?.recordingManager.openMicrophoneSettings()
            },
            openScreenSettings: { [weak self] in
                self?.recordingManager.openPermissionSettings()
            },
            requestAccessibility: { [weak self] in
                self?.recordingManager.requestAccessibilityPermission()
            },
            openAccessibilitySettings: { [weak self] in
                self?.recordingManager.openAccessibilitySettings()
            },
        )

        let shortcutViewModel = ShortcutSettingsViewModel()
        let assistantShortcutViewModel = AssistantShortcutSettingsViewModel()
        let onboardingViewModel = OnboardingViewModel()
        let modelManager = FluidAIModelManager.shared

        onboardingController.showOnboarding(
            viewModel: onboardingViewModel,
            permissionViewModel: permissionViewModel,
            shortcutViewModel: shortcutViewModel,
            assistantShortcutViewModel: assistantShortcutViewModel,
            modelManager: modelManager,
            refreshPermissions: { [weak self] in
                await self?.recordingManager.checkPermission()
            },
            completion: completion,
        )
    }

    private func completeOnboarding() {
        settingsStore.hasCompletedOnboarding = true
        continueAppSetup()
    }

    private func continueAppSetup() {
        configureNavigationService()
        configureCommandRouter()
        setupMenuBar()
        verifyPrimaryInterfaceAfterLaunch()
        setupContextMenu()
        globalShortcutController.start()
        meetingNotesPaneShortcutController.start()
        recordingCancelShortcutController.start()
        setupCapabilityObservation()

        // Run auto-cleanup before model warmup so stale caches can be purged safely.
        Task {
            await performCleanup()
        }

        applyMeetingTranscriptionCapabilityState(isEnabled: settingsStore.isMeetingTranscriptionEnabled)
        assistantShortcutController.start()
        setupRecordingObservation()
        setupCommandMenuObservation()
        prewarmFloatingIndicatorIfEligible()
        updateMenuTitles()

        localModelResidencyCoordinator.startMonitoring()

        configureUserInterfacePreferences()

        openSettingsOnLaunchIfEnabled()
        scheduleLaunchVisibilityRecovery()
        MeetingReminderCoordinator.shared.attach()
    }

    private func openSettingsOnLaunchIfEnabled() {
        guard settingsStore.showSettingsOnLaunch else { return }
        promoteAppForWindowPresentation()
        NavigationService.shared.openSettings()
    }

    /// Keeps indicator prewarming out of the launch critical path.
    /// Classic style has a known NSPanel constraint-loop instability on some systems.
    private func prewarmFloatingIndicatorIfEligible() {
        guard settingsStore.recordingIndicatorEnabled else { return }
        guard settingsStore.recordingIndicatorStyle == .mini else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.floatingIndicatorController.prewarm()
        }
    }

    func promoteAppForWindowPresentation() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func verifyPrimaryInterfaceAfterLaunch() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let hasStatusButton = statusItem?.button != nil
            let isStatusItemVisible = statusItem?.isVisible ?? false
            guard hasStatusButton, isStatusItemVisible else {
                logger.fault("Primary UI did not initialize correctly. Presenting settings recovery window.")
                promoteAppForWindowPresentation()
                NavigationService.shared.openSettings()
                return
            }
        }
    }

    private func configureNavigationService() {
        NavigationService.shared.registerOpenOnboardingHandler { [weak self] in
            self?.promoteAppForWindowPresentation()
            self?.presentOnboarding {}
        }
        NavigationService.shared.setSettingsSidebarVisible(settingsStore.isSettingsSidebarVisible)
    }

    private func configureCommandRouter() {
        AppCommandRouter.shared.registerHandlers(
            .init(
                toggleDictation: { [weak self] in
                    self?.toggleRecordingFromMenu()
                },
                toggleMeeting: { [weak self] in
                    self?.startMeetingFromMenu()
                },
                toggleAssistant: { [weak self] in
                    self?.startAssistantFromMenu()
                },
                cancelCapture: { [weak self] in
                    self?.cancelRecordingFromMenu()
                },
                openSettings: { [weak self] in
                    self?.promoteAppForWindowPresentation()
                    NavigationService.shared.openSettings()
                },
                openHistory: { [weak self] in
                    self?.openHistory()
                },
                openOnboarding: { [weak self] in
                    self?.promoteAppForWindowPresentation()
                    self?.openOnboarding()
                },
                quit: { [weak self] in
                    self?.quitApp()
                },
            ),
        )
    }

    /// Ensures the app is recoverable when launch completes without any visible affordance.
    /// This protects against silent launch states where neither status item nor windows are visible.
    private func scheduleLaunchVisibilityRecovery() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }

            let hasStatusButton = statusItem?.button != nil
            let isStatusItemVisible = statusItem?.isVisible ?? false
            let hasVisibleWindow = NSApp.windows.contains(where: \.isVisible)

            guard !hasVisibleWindow else { return }
            guard !hasStatusButton || !isStatusItemVisible else { return }

            logger.fault("Launch recovery triggered: no visible status item and no visible window.")
            promoteAppForWindowPresentation()
            NavigationService.shared.openSettings()
        }
    }

    // MARK: - Document Handling (Disabled for Menu Bar App)

    /// Prevent the app from reopening windows when activated.
    /// This is critical for menu bar-only apps in SPM builds.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Do not create new windows when app is reactivated
        false
    }

    /// Prevent the app from opening untitled files on launch.
    /// Without this, AppKit calls this method and crashes in SPM builds.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // Menu bar apps don't open documents
        true
    }

    /// Prevent app from prompting to open a new document.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupRecordingObservation() {
        Publishers.MergeMany(
            recordingManager.isRecordingPublisher.map { _ in () }.eraseToAnyPublisher(),
            recordingManager.isStartingPublisher.map { _ in () }.eraseToAnyPublisher(),
            recordingManager.isTranscribingPublisher.map { _ in () }.eraseToAnyPublisher(),
            recordingManager.isForegroundTranscribingPublisher.map { _ in () }.eraseToAnyPublisher(),
            assistantVoiceCommandService.$isRecording.map { _ in () }.eraseToAnyPublisher(),
            assistantVoiceCommandService.$isProcessing.map { _ in () }.eraseToAnyPublisher(),
            recordingManager.currentMeetingPublisher.map { _ in () }.eraseToAnyPublisher(),
            recordingManager.$isMeetingNotesPanelVisible.map { _ in () }.eraseToAnyPublisher(),
            recordingManager.$automaticMeetingRecordingConfirmation.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.$cancelRecordingShortcutDefinition.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.$isMeetingTranscriptionEnabled.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.$isAssistantEnabled.map { _ in () }.eraseToAnyPublisher(),
            settingsStore.$isAssistantIntegrationsEnabled.map { _ in () }.eraseToAnyPublisher(),
        )
        // @Published emits in willSet; schedule refresh so re-reads observe committed values.
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.refreshRecordingUIState()
        }
        .store(in: &cancellables)

        // Show error on floating indicator when recording fails
        recordingManager.$meetingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                guard case let .failed(message) = state else { return }
                self?.floatingIndicatorController.showError(message, autoHideAfter: 4.0)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .meetingAssistantTranscriptionFailed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                let message = notification.userInfo?[AppNotifications.UserInfoKey.transcriptionErrorMessage] as? String
                self?.floatingIndicatorController.showError(
                    message ?? "notification.transcription_failed".localized,
                    autoHideAfter: 4.0,
                )
            }
            .store(in: &cancellables)

        refreshRecordingUIState()
    }

    private func setupCommandMenuObservation() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncCommandMenuStateIfNeeded(force: true)
            }
            .store(in: &cancellables)
    }

    private func refreshRecordingUIState() {
        let isRecording = recordingManager.isRecording
        let isStarting = recordingManager.isStartingRecording
        let isTranscribing = recordingManager.isForegroundTranscribing
        let isAssistantRecording = assistantVoiceCommandService.isRecording
        let isAssistantProcessing = assistantVoiceCommandService.isProcessing
        let automaticMeetingConfirmation = recordingManager.automaticMeetingRecordingConfirmation
        let isProcessing = isTranscribing || isAssistantProcessing
        let currentMeetingType = recordingManager.currentMeeting?.type
        let isAssistantOwnedOverlayVisible = floatingIndicatorController.isVisible && {
            switch floatingIndicatorController.renderState.kind {
            case .assistant, .assistantIntegration:
                true
            case .dictation, .meeting:
                false
            }
        }()
        let shouldDeferIndicatorUpdatesToAssistant = !isRecording
            && !isStarting
            && !isTranscribing
            && (isAssistantRecording || isAssistantProcessing || isAssistantOwnedOverlayVisible)
        let commandState = AppCommandState(
            recordingSection: MenuBarRecordingSectionState(
                isRecordingManagerActive: isRecording || isStarting || isTranscribing,
                recordingSource: recordingManager.recordingSource,
                capturePurpose: recordingManager.currentCapturePurpose,
                isAssistantRecording: isAssistantRecording || isAssistantOwnedOverlayVisible,
            ),
            cancelRecordingShortcutDefinition: settingsStore.cancelRecordingShortcutDefinition,
            meetingCapabilityEnabled: settingsStore.isMeetingTranscriptionEnabled,
            assistantCapabilityEnabled: settingsStore.isAssistantEnabled,
        )
        let renderState = RecordingUIRenderState(
            isRecording: isRecording,
            isStarting: isStarting,
            isTranscribing: isTranscribing,
            isAssistantRecording: isAssistantRecording,
            isAssistantProcessing: isAssistantProcessing,
            automaticMeetingRecordingConfirmation: automaticMeetingConfirmation,
            meetingTypeRawValue: currentMeetingType?.rawValue,
            isMeetingNotesPanelVisible: recordingManager.isMeetingNotesPanelVisible,
        )

        lastAppCommandState = commandState
        syncCommandMenuStateIfNeeded()
        updateMenuTitles()

        guard renderState != lastRecordingUIRenderState else {
            recordingCancelShortcutController.refresh()
            return
        }
        lastRecordingUIRenderState = renderState

        updateStatusIcon(isRecording: isRecording || isAssistantRecording || isStarting)
        if !shouldDeferIndicatorUpdatesToAssistant {
            updateFloatingIndicator(
                isRecording: isRecording,
                isAssistantRecording: isAssistantRecording,
                isStarting: isStarting,
                isProcessing: isProcessing,
                automaticMeetingConfirmation: automaticMeetingConfirmation,
                capturePurpose: recordingManager.currentCapturePurpose,
                recordingSource: recordingManager.recordingSource,
                meetingType: currentMeetingType,
            )
        }
        updateMeetingNotesPanel(isRecording: isRecording, capturePurpose: recordingManager.currentCapturePurpose)

        if isRecording || isStarting,
           settingsStore.recordingIndicatorEnabled,
           settingsStore.recordingIndicatorStyle != .none
        {
            recordingManager.noteIndicatorShownForStartIfNeeded()
        }

        updateMenuTitles()
        recordingCancelShortcutController.refresh()
    }

    func syncCommandMenuStateIfNeeded(force: Bool = false) {
        guard force || NSApp.isActive else {
            return
        }

        guard !isContextMenuOpen else {
            hasPendingCommandMenuSync = true
            return
        }

        AppCommandRouter.shared.update(state: lastAppCommandState)
        hasPendingCommandMenuSync = false
    }

    func recordingCancelShortcutStateSnapshot() -> RecordingCancelShortcutState {
        RecordingCancelShortcutState(
            isRecordingManagerCaptureActive: recordingManager.isRecording || recordingManager.isStartingRecording,
            isAssistantCaptureActive: assistantVoiceCommandService.isRecording,
        )
    }

    /// Toggle recording state when global shortcut is activated.
    func startRecording(source: RecordingSource) async {
        let purpose: CapturePurpose = source == .microphone ? .dictation : .meeting

        if purpose == .meeting, !settingsStore.isMeetingTranscriptionEnabled {
            AppLogger.info(
                "Meeting capture start blocked because meeting transcription capability is disabled",
                category: .uiController,
            )
            floatingIndicatorController.showError("recording.error.meeting_transcription_disabled".localized)
            return
        }

        if recordingManager.currentCapturePurpose == purpose,
           recordingManager.isRecording
        {
            await recordingManager.stopRecording(transcribe: true)
            return
        }

        if recordingManager.isRecording || recordingManager.isStartingRecording || assistantVoiceCommandService.isRecording {
            AppLogger.info(
                "Menu recording start blocked by active capture",
                category: .uiController,
                extra: [
                    "requestedPurpose": purpose == .dictation ? "dictation" : "meeting",
                    "activePurpose": recordingManager.currentCapturePurpose?.rawValue ?? "assistant",
                ],
            )
            floatingIndicatorController.showError("recording.error.mode_switch_blocked".localized)
            return
        }

        let triggerLabel = purpose == .dictation ? "menu.dictation" : "menu.meeting"
        await recordingManager.startCapture(
            purpose: purpose,
            requestedAt: Date(),
            triggerLabel: triggerLabel,
        )
    }

    private func setupCapabilityObservation() {
        guard !hasConfiguredCapabilityObservers else { return }
        hasConfiguredCapabilityObservers = true

        settingsStore.$isMeetingTranscriptionEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.applyMeetingTranscriptionCapabilityState(isEnabled: isEnabled)
                self?.refreshRecordingUIState()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .map { [settingsStore] _ in settingsStore.autoStartRecording }
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.applyAutomaticMeetingRecordingState()
            }
            .store(in: &cancellables)

        settingsStore.$isAssistantIntegrationsEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.assistantShortcutController.refresh()
                self?.refreshRecordingUIState()
            }
            .store(in: &cancellables)

        settingsStore.$isAssistantEnabled
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.applyAssistantCapabilityState(isEnabled: isEnabled)
                self?.refreshRecordingUIState()
            }
            .store(in: &cancellables)
    }

    private func maybeWarmupMeetingTranscriptionModel() {
        guard settingsStore.isMeetingTranscriptionEnabled else { return }

        Task { @MainActor in
            do {
                try await TranscriptionClient.shared.warmupModel()
            } catch {
                self.logger.error("Failed to warmup model: \(error.localizedDescription)")
            }
        }
    }

    private func applyMeetingTranscriptionCapabilityState(isEnabled: Bool) {
        applyAutomaticMeetingRecordingState()

        guard !isEnabled else {
            maybeWarmupMeetingTranscriptionModel()
            return
        }

        if recordingManager.currentCapturePurpose == .meeting,
           recordingManager.isRecording || recordingManager.isStartingRecording
        {
            Task {
                await recordingManager.cancelRecording()
            }
        }

        _ = FluidAIModelManager.shared.unloadDiarizationFromMemoryIfPossible()
        _ = FluidAIModelManager.shared.unloadASRFromMemoryIfPossible()
    }

    private func applyAssistantCapabilityState(isEnabled: Bool) {
        assistantShortcutController.refresh()

        guard !isEnabled else { return }

        if assistantVoiceCommandService.isRecording || assistantVoiceCommandService.isProcessing {
            Task {
                await assistantVoiceCommandService.cancelRecording()
            }
        }
    }

    private func applyAutomaticMeetingRecordingState() {
        recordingManager.setAutomaticMeetingRecordingEnabled(
            settingsStore.isMeetingTranscriptionEnabled && settingsStore.autoStartRecording,
        )
    }

    #if DEBUG
    private func scheduleRuntimeSmokeIfRequested() {
        guard ProcessInfo.processInfo.environment["MA_RUNTIME_SMOKE"] == "recording-start" else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            Task { @MainActor [weak self] in
                await self?.runRuntimeRecordingSmoke()
            }
        }
    }

    private func runRuntimeRecordingSmoke() async {
        print("RUNTIME_SMOKE: START recording-start")
        await startRecording(source: .microphone)

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if recordingManager.isRecording {
                await recordingManager.cancelRecording()
                print("RUNTIME_SMOKE: PASS recording-start")
                NSApp.terminate(nil)
                return
            }

            if recordingManager.lastError != nil {
                print("RUNTIME_SMOKE: FAIL recording-start")
                await cancelRuntimeSmokeCaptureIfNeeded()
                NSApp.terminate(nil)
                return
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        print("RUNTIME_SMOKE: FAIL recording-start timeout")
        await cancelRuntimeSmokeCaptureIfNeeded()
        NSApp.terminate(nil)
    }

    private func cancelRuntimeSmokeCaptureIfNeeded() async {
        guard recordingManager.isRecording || recordingManager.isStartingRecording else { return }
        await recordingManager.cancelRecording()
    }
    #endif

}
