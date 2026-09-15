import Combine
import Foundation
import MeetingAssistantCore

@MainActor
final class AssistantShortcutController {
    let assistantService: AssistantVoiceCommandService
    let settings: AppSettingsStore
    var cancellables = Set<AnyCancellable>()

    let inputBackend: ShortcutInputBackend
    let hotkeyBackend: GlobalHotkeyBackend
    let shortcutRouter = ShortcutEventRoutingOrchestrator()
    var integrationShortcutHandlers: [UUID: SmartShortcutHandler] = [:]
    var integrationPresetStates: [UUID: ShortcutActivationState] = [:]
    var registeredIntegrationShortcutIDs = Set<UUID>()
    let layerTimeoutNanoseconds: UInt64 = 1_000_000_000
    var shortcutLayerStateMachine = AssistantShortcutLayerStateMachine()
    var shortcutLayerTask: Task<Void, Never>?
    var lastLayerLeaderTapTime: Date?
    let shortcutLayerFeedbackController = ShortcutLayerFeedbackController()
    let shortcutLayerKeySuppressor = ShortcutLayerKeySuppressor()

    // MARK: - Integration Leader Mode (legacy state retained, currently disabled in global path)

    var integrationLeaderModeStateMachine = IntegrationLeaderModeStateMachine()
    var integrationLeaderModeTask: Task<Void, Never>?
    let integrationLeaderModeTimeoutSeconds: TimeInterval = 2.0

    var isShortcutLayerArmed: Bool {
        shortcutLayerStateMachine.state == .armed
    }

    lazy var shortcutHandler = SmartShortcutHandler(
        doubleTapInterval: currentDoubleTapInterval,
        isRecordingProvider: { [weak self] in self?.assistantService.isRecording ?? false },
        actionHandler: { [weak self] (action: SmartShortcutHandler.Action) in
            guard let self else { return }
            Task {
                await self.performAction(action)
            }
        }
    )

    let presetState = ShortcutActivationState()
    let healthCheckIntervalSeconds: TimeInterval = 15
    var healthCheckTimer: Timer?
    var shortcutCaptureHealthSnapshot: ShortcutCaptureHealthSnapshot?
    var isStarted = false

    init(
        assistantService: AssistantVoiceCommandService,
        settings: AppSettingsStore,
        inputBackend: ShortcutInputBackend? = nil,
        hotkeyBackend: GlobalHotkeyBackend? = nil
    ) {
        self.assistantService = assistantService
        self.settings = settings
        self.inputBackend = inputBackend ?? Self.makeDefaultInputBackend()
        self.hotkeyBackend = hotkeyBackend ?? Self.makeDefaultHotkeyBackend()
        configureInputBackendHandlers()
    }

    private static func makeDefaultInputBackend() -> ShortcutInputBackend {
        SystemShortcutInputBackend()
    }

    private static func makeDefaultHotkeyBackend() -> GlobalHotkeyBackend {
        CarbonGlobalHotkeyBackend()
    }

    func emitShortcutDetected(
        shortcutTarget: String,
        source: String,
        trigger: ShortcutActivationMode
    ) {
        emitShortcutDetected(
            shortcutTarget: shortcutTarget,
            source: source,
            triggerToken: trigger.rawValue
        )
    }

    func emitShortcutDetected(
        shortcutTarget: String,
        source: String,
        triggerToken: String
    ) {
        ShortcutTelemetry.emit(
            .shortcutDetected(
                pipeline: "assistant_shortcuts",
                scope: "assistant",
                shortcutTarget: shortcutTarget,
                source: source,
                trigger: triggerToken
            ),
            category: .assistant
        )
    }

    func emitShortcutRejected(
        shortcutTarget: String,
        source: String,
        trigger: ShortcutActivationMode? = nil,
        reason: String
    ) {
        emitShortcutRejected(
            shortcutTarget: shortcutTarget,
            source: source,
            triggerToken: triggerToken(for: trigger),
            reason: reason
        )
    }

    func emitShortcutRejected(
        shortcutTarget: String,
        source: String,
        triggerToken: String,
        reason: String
    ) {
        ShortcutTelemetry.emit(
            .shortcutRejected(
                pipeline: "assistant_shortcuts",
                scope: "assistant",
                shortcutTarget: shortcutTarget,
                source: source,
                trigger: triggerToken,
                reason: reason
            ),
            category: .assistant
        )
    }

    func emitLayerArmed(source: String, trigger: String) {
        ShortcutTelemetry.emit(
            .layerArmed(
                pipeline: "assistant_shortcuts",
                scope: "assistant",
                source: source,
                trigger: trigger,
                timeoutMs: layerTimeoutMilliseconds
            ),
            category: .assistant
        )
    }

    func emitLayerTimeout(source: String) {
        ShortcutTelemetry.emit(
            .layerTimeout(
                pipeline: "assistant_shortcuts",
                scope: "assistant",
                source: source,
                timeoutMs: layerTimeoutMilliseconds
            ),
            category: .assistant
        )
    }

    var layerTimeoutMilliseconds: Int {
        Int(layerTimeoutNanoseconds / 1_000_000)
    }

    func triggerToken(for mode: ShortcutActivationMode?) -> String {
        mode?.rawValue ?? "unknown"
    }

    convenience init(assistantService: AssistantVoiceCommandService) {
        self.init(
            assistantService: assistantService,
            settings: .shared,
            inputBackend: nil,
            hotkeyBackend: nil
        )
    }

    private func configureInputBackendHandlers() {
        inputBackend.setFlagsChangedHandler { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        inputBackend.setKeyDownHandler { [weak self] event in
            self?.handleKeyDown(event)
        }

        inputBackend.setKeyUpHandler { [weak self] event in
            self?.handleKeyUp(event)
        }
    }

    deinit {
        Task { @MainActor [weak self] in
            self?.stopShortcutCaptureHealthChecks()
            self?.removeEventMonitors()
        }
    }
}

struct RecordingCancelShortcutState: Equatable {
    var isRecordingManagerCaptureActive: Bool
    var isAssistantCaptureActive: Bool

    var hasAnyActiveCapture: Bool {
        isRecordingManagerCaptureActive || isAssistantCaptureActive
    }
}

@MainActor
final class RecordingCancelShortcutController {
    private let settings: AppSettingsStore
    private let hotkeyBackend: GlobalHotkeyBackend
    private let stateProvider: @MainActor () -> RecordingCancelShortcutState
    private let cancelRecordingManagerCapture: @MainActor () async -> Void
    private let cancelAssistantCapture: @MainActor () async -> Void

    private let hotkeyID = "global.cancel_active_recording"
    private var isStarted = false
    private var isRegistered = false
    private var registeredDefinition: ShortcutDefinition?

    init(
        settings: AppSettingsStore? = nil,
        hotkeyBackend: GlobalHotkeyBackend? = nil,
        stateProvider: @escaping @MainActor () -> RecordingCancelShortcutState,
        cancelRecordingManagerCapture: @escaping @MainActor () async -> Void,
        cancelAssistantCapture: @escaping @MainActor () async -> Void
    ) {
        self.settings = settings ?? .shared
        self.hotkeyBackend = hotkeyBackend ?? CarbonGlobalHotkeyBackend()
        self.stateProvider = stateProvider
        self.cancelRecordingManagerCapture = cancelRecordingManagerCapture
        self.cancelAssistantCapture = cancelAssistantCapture
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        refresh()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        unregister()
    }

    func refresh() {
        guard isStarted else { return }

        let state = stateProvider()
        guard state.hasAnyActiveCapture,
              let definition = settings.cancelRecordingShortcutDefinition,
              let descriptor = GlobalHotkeyMapper.descriptor(for: definition)
        else {
            unregister()
            return
        }

        guard !isRegistered || registeredDefinition != definition else {
            return
        }

        let registration = HotkeyRegistration(
            id: hotkeyID,
            keyCode: descriptor.keyCode,
            modifiers: descriptor.modifiers,
            onKeyDown: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await handleCancelHotkeyPressed()
                }
            },
            onKeyUp: {}
        )

        hotkeyBackend.registerAll([registration])
        isRegistered = hotkeyBackend.registeredHotkeyCount > 0
        registeredDefinition = isRegistered ? definition : nil
    }

    private func unregister() {
        guard isRegistered || hotkeyBackend.registeredHotkeyCount > 0 else {
            registeredDefinition = nil
            return
        }

        hotkeyBackend.unregisterAll()
        isRegistered = false
        registeredDefinition = nil
    }

    private func handleCancelHotkeyPressed() async {
        let state = stateProvider()

        if state.isAssistantCaptureActive {
            await cancelAssistantCapture()
        }

        if state.isRecordingManagerCaptureActive {
            await cancelRecordingManagerCapture()
        }
    }
}
