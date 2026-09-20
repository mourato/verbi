import AppKit
import Combine
import MeetingAssistantCore

@MainActor
final class GlobalShortcutController {
    private let recordingManager: RecordingManager
    private let settings: AppSettingsStore
    private let hotkeyBackend: GlobalHotkeyBackend
    private var cancellables = Set<AnyCancellable>()

    private lazy var dictationHandler = SmartShortcutHandler(
        doubleTapInterval: currentDoubleTapInterval,
        isRecordingProvider: { [weak self] in self?.isCaptureActive(for: .dictation) ?? false },
        actionHandler: { [weak self] action in
            Task { @MainActor [weak self] in
                await self?.performAction(action, for: .dictation)
            }
        }
    )

    private lazy var meetingHandler = SmartShortcutHandler(
        doubleTapInterval: currentDoubleTapInterval,
        isRecordingProvider: { [weak self] in self?.isCaptureActive(for: .meeting) ?? false },
        actionHandler: { [weak self] action in
            Task { @MainActor [weak self] in
                await self?.performAction(action, for: .meeting)
            }
        }
    )

    private let healthCheckIntervalSeconds: TimeInterval = 15
    private var healthCheckTimer: Timer?
    private(set) var shortcutCaptureHealthSnapshot: ShortcutCaptureHealthSnapshot?

    init(
        recordingManager: RecordingManager,
        settings: AppSettingsStore,
        hotkeyBackend: GlobalHotkeyBackend? = nil
    ) {
        self.recordingManager = recordingManager
        self.settings = settings
        self.hotkeyBackend = hotkeyBackend ?? Self.makeDefaultHotkeyBackend()
    }

    private static func makeDefaultHotkeyBackend() -> GlobalHotkeyBackend {
        CarbonGlobalHotkeyBackend()
    }

    convenience init(recordingManager: RecordingManager) {
        self.init(recordingManager: recordingManager, settings: .shared, hotkeyBackend: nil)
    }

    func start() {
        observeSettings()
        observeLifecycleEvents()
        applyGlobalDoubleTapInterval()
        refreshEventMonitors()
        startShortcutCaptureHealthChecks()
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.stopShortcutCaptureHealthChecks()
            self?.hotkeyBackend.unregisterAll()
            self?.runShortcutCaptureHealthCheck(
                source: "controller_deinit",
                expectation: ShortcutCaptureBackendExpectation.none
            )
        }
    }

    private func observeSettings() {
        observeRegistrationInputs(settings.$dictationSelectedPresetKey.map { _ in () }.eraseToAnyPublisher())
        observeRegistrationInputs(settings.$meetingSelectedPresetKey.map { _ in () }.eraseToAnyPublisher())
        observeRegistrationInputs(settings.$dictationShortcutDefinition.map { _ in () }.eraseToAnyPublisher())
        observeRegistrationInputs(settings.$meetingShortcutDefinition.map { _ in () }.eraseToAnyPublisher())
        observeRegistrationInputs(settings.$dictationModifierShortcutGesture.map { _ in () }.eraseToAnyPublisher())
        observeRegistrationInputs(settings.$meetingModifierShortcutGesture.map { _ in () }.eraseToAnyPublisher())
        observeRegistrationInputs(settings.$isMeetingTranscriptionEnabled.map { _ in () }.eraseToAnyPublisher())

        observeResetOnly(settings.$shortcutActivationMode.map { _ in () }.eraseToAnyPublisher())
        observeResetOnly(settings.$dictationShortcutActivationMode.map { _ in () }.eraseToAnyPublisher())

        settings.$shortcutDoubleTapIntervalMilliseconds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyGlobalDoubleTapInterval()
                self?.resetShortcutState()
            }
            .store(in: &cancellables)
    }

    private func observeRegistrationInputs(_ publisher: AnyPublisher<Void, Never>) {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetShortcutState()
                self?.refreshEventMonitors()
            }
            .store(in: &cancellables)
    }

    private func observeResetOnly(_ publisher: AnyPublisher<Void, Never>) {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetShortcutState()
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
    }

    private func refreshEventMonitors() {
        refreshDirectHotkeys()
        runShortcutCaptureHealthCheck(source: "refresh_event_monitors", expectation: expectedShortcutCaptureBackends())

        AppLogger.debug(
            "Global shortcut hotkey refresh",
            category: .uiController,
            extra: [
                "inHouseHotkeys": hotkeyBackend.registeredHotkeyCount
            ]
        )
    }

    private func refreshDirectHotkeys() {
        var registrations: [HotkeyRegistration] = []

        if let dictationRegistration = inHouseRegistration(for: .dictation) {
            registrations.append(dictationRegistration)
        }

        if let meetingRegistration = inHouseRegistration(for: .meeting) {
            registrations.append(meetingRegistration)
        }

        hotkeyBackend.registerAll(registrations)
    }

    private func inHouseRegistration(for type: ShortcutType) -> HotkeyRegistration? {
        guard isCapabilityEnabled(for: type) else { return nil }

        let definition: ShortcutDefinition? = switch type {
        case .dictation:
            settings.dictationShortcutDefinition
        case .meeting:
            settings.meetingShortcutDefinition
        }

        guard let definition,
              let descriptor = GlobalHotkeyMapper.descriptor(for: definition)
        else {
            return nil
        }

        let activationMode = definition.trigger.asShortcutActivationMode
        let target = shortcutTarget(for: type)
        return HotkeyRegistration(
            id: "global.\(target)",
            keyCode: descriptor.keyCode,
            modifiers: descriptor.modifiers,
            onKeyDown: { [weak self] in
                guard let self else { return }
                emitShortcutDetected(
                    for: type,
                    source: "in_house_hotkey",
                    trigger: activationMode
                )
                Task { @MainActor [weak self] in
                    await self?.handleShortcutDown(for: type, activationModeOverride: activationMode)
                }
            },
            onKeyUp: { [weak self] in
                guard let self else { return }
                Task { @MainActor [weak self] in
                    await self?.handleShortcutUp(for: type, activationModeOverride: activationMode)
                }
            }
        )
    }

    func expectedShortcutCaptureBackends() -> ShortcutCaptureBackendExpectation {
        ShortcutCaptureBackendExpectation(
            needsGlobalCapture: hotkeyBackend.registeredHotkeyCount > 0,
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
            pipeline: "global_shortcuts",
            scope: "global",
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
            scope: .global,
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
            category: .uiController
        )
    }

    func handleShortcutDown(
        for type: ShortcutType,
        activationModeOverride: ShortcutActivationMode? = nil
    ) {
        guard isCapabilityEnabled(for: type) else { return }

        let handler = type == .dictation ? dictationHandler : meetingHandler
        handler.handleShortcutDown(activationMode: activationModeOverride ?? activationMode(for: type))
    }

    func handleShortcutUp(
        for type: ShortcutType,
        activationModeOverride: ShortcutActivationMode? = nil
    ) {
        guard isCapabilityEnabled(for: type) else { return }

        let handler = type == .dictation ? dictationHandler : meetingHandler
        handler.handleShortcutUp(activationMode: activationModeOverride ?? activationMode(for: type))
    }

    func performAction(_ action: SmartShortcutHandler.Action, for type: ShortcutType) async {
        guard isCapabilityEnabled(for: type) else {
            emitShortcutRejected(
                for: type,
                source: "shortcut_engine",
                trigger: activationMode(for: type),
                reason: "capability_disabled"
            )
            return
        }

        switch action {
        case .startRecording:
            if let blockingMode = await RecordingExclusivityCoordinator.shared
                .blockingMode(for: requestedExclusivityMode(for: type))
            {
                emitShortcutRejected(
                    for: type,
                    source: "shortcut_engine",
                    trigger: activationMode(for: type),
                    reason: "blocked_by_active_\(blockingMode.rawValue)_capture"
                )
                return
            }

            let purpose: CapturePurpose = type == .dictation ? .dictation : .meeting
            let triggerLabel = type == .dictation ? "shortcut.dictation" : "shortcut.meeting"
            await recordingManager.startCapture(
                purpose: purpose,
                requestedAt: Date(),
                triggerLabel: triggerLabel
            )
        case .stopRecording:
            guard isCaptureActive(for: type) else {
                let blockingMode = await RecordingExclusivityCoordinator.shared
                    .blockingMode(for: requestedExclusivityMode(for: type))
                let reason = if let blockingMode {
                    "stop_ignored_active_\(blockingMode.rawValue)_capture"
                } else {
                    "stop_ignored_no_active_capture"
                }
                emitShortcutRejected(
                    for: type,
                    source: "shortcut_engine",
                    trigger: activationMode(for: type),
                    reason: reason
                )
                return
            }
            await recordingManager.stopRecording()
        }
    }

    func resetShortcutState() {
        dictationHandler.reset()
        meetingHandler.reset()
    }

    var currentDoubleTapInterval: TimeInterval {
        settings.shortcutDoubleTapIntervalMilliseconds / 1000
    }

    func applyGlobalDoubleTapInterval() {
        let interval = currentDoubleTapInterval
        dictationHandler.setDoubleTapInterval(interval)
        meetingHandler.setDoubleTapInterval(interval)
    }

    func activationMode(for type: ShortcutType) -> ShortcutActivationMode {
        switch type {
        case .dictation:
            settings.dictationShortcutActivationMode
        case .meeting:
            settings.shortcutActivationMode
        }
    }

    func emitShortcutDetected(
        for type: ShortcutType,
        source: String,
        trigger: ShortcutActivationMode
    ) {
        ShortcutTelemetry.emit(
            .shortcutDetected(
                pipeline: "global_shortcuts",
                scope: "global",
                shortcutTarget: shortcutTarget(for: type),
                source: source,
                trigger: trigger.rawValue
            ),
            category: .uiController
        )
    }

    func emitShortcutRejected(
        for type: ShortcutType,
        source: String,
        trigger: ShortcutActivationMode,
        reason: String
    ) {
        ShortcutTelemetry.emit(
            .shortcutRejected(
                pipeline: "global_shortcuts",
                scope: "global",
                shortcutTarget: shortcutTarget(for: type),
                source: source,
                trigger: trigger.rawValue,
                reason: reason
            ),
            category: .uiController
        )
    }

    func shortcutTarget(for type: ShortcutType) -> String {
        switch type {
        case .dictation:
            "dictation"
        case .meeting:
            "meeting"
        }
    }

    private func isCaptureActive(for type: ShortcutType) -> Bool {
        let expectedPurpose: CapturePurpose = type == .dictation ? .dictation : .meeting
        guard recordingManager.currentCapturePurpose == expectedPurpose else {
            return false
        }

        return recordingManager.isRecording || recordingManager.isStartingRecording
    }

    private func requestedExclusivityMode(for type: ShortcutType) -> RecordingExclusivityCoordinator.ActiveMode {
        switch type {
        case .dictation:
            .dictation
        case .meeting:
            .meeting
        }
    }

    private func isCapabilityEnabled(for type: ShortcutType) -> Bool {
        switch type {
        case .dictation:
            true
        case .meeting:
            settings.isMeetingTranscriptionEnabled
        }
    }
}

enum ShortcutType {
    case dictation
    case meeting
}
