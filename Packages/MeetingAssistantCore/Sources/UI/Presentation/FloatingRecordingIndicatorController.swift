import AppKit
import Combine
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Mode for the floating indicator.
public enum FloatingRecordingIndicatorMode: Sendable, Equatable {
    case starting
    case confirmingAutomaticMeetingStart(deadline: Date, duration: TimeInterval)
    case recording
    case processing
    case error(message: String)
}

/// Controller that manages the floating recording indicator window.
/// Uses NSPanel to create a non-activating floating overlay.
@MainActor
public final class FloatingRecordingIndicatorController: ObservableObject {
    // MARK: - Properties

    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private let audioMonitor: AudioLevelMonitor
    private let settingsStore: AppSettingsStore
    private let processingStateStore: RecordingIndicatorProcessingStateStore
    private var cancellables = Set<AnyCancellable>()
    private var currentRenderState = RecordingIndicatorRenderState(mode: .recording, kind: .dictation)
    private var currentProcessingSnapshot: RecordingIndicatorProcessingSnapshot?
    private var visibilityTransitionID: UInt64 = 0
    private var deferredGeometryTask: Task<Void, Never>?
    private var onStopAction: @Sendable () -> Void = {
        Task { @MainActor in
            await RecordingManager.shared.stopRecording()
        }
    }

    private var onCancelAction: @Sendable () -> Void = {
        Task { @MainActor in
            await RecordingManager.shared.cancelRecording()
        }
    }

    /// Whether the indicator is currently visible.
    @Published public private(set) var isVisible = false
    public var renderState: RecordingIndicatorRenderState {
        currentRenderState
    }

    public var processingSnapshot: RecordingIndicatorProcessingSnapshot? {
        currentProcessingSnapshot
    }

    // MARK: - Configuration

    private enum Constants {
        static let panelHeightClassic: CGFloat = AppDesignSystem.Layout.recordingIndicatorClassicHeight
        static let panelHeightMini: CGFloat = AppDesignSystem.Layout.recordingIndicatorMiniHeight
        static let panelHeightSuper: CGFloat = AppDesignSystem.Layout.recordingIndicatorSuperHeight
        static let panelWidthError: CGFloat = AppDesignSystem.Layout.recordingIndicatorPanelWidth
        static let screenPadding: CGFloat = 40
        static let panelShadowInset: CGFloat = AppDesignSystem.Layout.recordingIndicatorMainShadowRadius
            + abs(AppDesignSystem.Layout.recordingIndicatorMainShadowY)
            + 4
    }

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private var prefersReducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - Initialization

    /// Creates a new floating recording indicator controller.
    /// - Parameters:
    ///   - audioMonitor: The audio monitor to use for waveform data.
    ///   - settingsStore: The settings store for configuration.
    public init(
        audioMonitor: AudioLevelMonitor = AudioLevelMonitor(),
        settingsStore: AppSettingsStore = .shared,
        processingStateStore: RecordingIndicatorProcessingStateStore = .shared
    ) {
        self.audioMonitor = audioMonitor
        self.settingsStore = settingsStore
        self.processingStateStore = processingStateStore
        currentProcessingSnapshot = processingStateStore.currentSnapshot
        setupBindings()
    }

    deinit {
        deferredGeometryTask?.cancel()
    }

    // MARK: - Public API

    /// Show the floating indicator.
    /// Automatically reads style and position from settings.
    /// - Parameter mode: Whether to present recording or processing visuals.
    public func show(mode: FloatingRecordingIndicatorMode = .recording) {
        onStopAction = {
            Task { @MainActor in
                await RecordingManager.shared.stopRecording()
            }
        }
        onCancelAction = {
            Task { @MainActor in
                await RecordingManager.shared.cancelRecording()
            }
        }
        show(mode: mode, onStop: onStopAction, onCancel: onCancelAction)
    }

    public func show(
        mode: FloatingRecordingIndicatorMode = .recording,
        onStop: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void
    ) {
        guard shouldShowIndicator(for: mode) else { return }
        let renderState = currentRenderState.with(mode: mode)
        show(renderState: renderState, onStop: onStop, onCancel: onCancel)
    }

    public func show(renderState: RecordingIndicatorRenderState) {
        onStopAction = {
            Task { @MainActor in
                await RecordingManager.shared.stopRecording()
            }
        }
        onCancelAction = {
            Task { @MainActor in
                await RecordingManager.shared.cancelRecording()
            }
        }
        show(renderState: renderState, onStop: onStopAction, onCancel: onCancelAction)
    }

    public func show(
        renderState: RecordingIndicatorRenderState,
        onStop: @escaping @Sendable () -> Void,
        onCancel: @escaping @Sendable () -> Void
    ) {
        onStopAction = onStop
        onCancelAction = onCancel

        guard shouldShowIndicator(for: renderState.mode) else { return }
        if renderState.mode != .processing {
            resetProcessingSnapshot()
        }
        let wasVisible = isVisible
        visibilityTransitionID &+= 1
        currentRenderState = renderState
        isVisible = true

        let panel = ensurePanel(for: renderState)

        updateMode(renderState.mode)
        updateContent()
        applyPanelGeometry(panel, deferIfPanelVisible: wasVisible)

        presentPanel(panel, animated: !wasVisible)
    }

    /// Hide the floating indicator.
    public func hide() {
        guard let panelToHide = panel else { return }
        visibilityTransitionID &+= 1
        let transitionID = visibilityTransitionID
        deferredGeometryTask?.cancel()
        deferredGeometryTask = nil

        isVisible = false
        updateContent()
        resetProcessingSnapshot()

        // Stop monitoring audio levels
        audioMonitor.stopMonitoring()

        dismissPanel(panelToHide, transitionID: transitionID)

        if let hostingView {
            hostingView.rootView = AnyView(EmptyView())
            if panelToHide.contentView !== hostingView {
                panelToHide.contentView = hostingView
            }
        }
    }

    /// Pre-creates the panel and hosting view so the first recording indicator paint is immediate.
    public func prewarm() {
        guard !isRunningTests else { return }
        guard settingsStore.recordingIndicatorEnabled, settingsStore.recordingIndicatorStyle != .none else { return }
        let panel = ensurePanel(for: RecordingIndicatorRenderState(mode: .starting, kind: .dictation))
        updateMode(.starting)
        updateContent()
        applyPanelGeometry(panel, deferIfPanelVisible: false)
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    /// Update the floating indicator mode without recreating the panel.
    public func update(mode: FloatingRecordingIndicatorMode) {
        guard isVisible else { return }
        update(renderState: currentRenderState.with(mode: mode))
    }

    public func update(renderState: RecordingIndicatorRenderState) {
        guard isVisible else { return }
        if renderState.mode != .processing {
            resetProcessingSnapshot()
        }
        currentRenderState = renderState
        updateMode(renderState.mode)
        updateContent()

        if let panel {
            applyPanelGeometry(panel, deferIfPanelVisible: true)
        }
    }

    public func showError(_ message: String, autoHideAfter delay: TimeInterval = 3.0) {
        show(mode: .error(message: message))
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.hide()
        }
    }

    public func updateProcessingSnapshot(_ snapshot: RecordingIndicatorProcessingSnapshot) {
        processingStateStore.update(snapshot: snapshot)
    }

    public func resetProcessingSnapshot() {
        processingStateStore.reset()
    }

    /// Update indicator position without recreating the panel.
    public func updatePosition() {
        guard let panel else { return }
        applyPanelGeometry(panel, deferIfPanelVisible: panel.isVisible)
    }

    // MARK: - Private Helpers

    private func ensurePanel(for renderState: RecordingIndicatorRenderState) -> NSPanel {
        let style = settingsStore.recordingIndicatorStyle
        let contentSize = panelContentSize(for: style, renderState: renderState)

        if let panel {
            return panel
        }

        let contentRect = NSRect(x: 0, y: 0, width: contentSize.width, height: contentSize.height)
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false

        self.panel = panel
        return panel
    }

    private func setupBindings() {
        // Observe position changes
        settingsStore.$recordingIndicatorPosition
            .dropFirst()
            .sink { [weak self] _ in
                self?.updatePosition()
            }
            .store(in: &cancellables)

        // Observe style changes and apply them without forcing hide/show cycles.
        settingsStore.$recordingIndicatorStyle
            .dropFirst()
            .sink { [weak self] newStyle in
                guard let self else { return }
                if newStyle == .none {
                    hide()
                    return
                }
                guard isVisible else { return }
                update(renderState: currentRenderState)
            }
            .store(in: &cancellables)

        processingStateStore.$currentSnapshot
            .sink { [weak self] snapshot in
                guard let self else { return }
                currentProcessingSnapshot = snapshot
                guard isVisible, currentRenderState.mode == .processing else { return }
                updateContent()
                if let panel {
                    applyPanelGeometry(panel, deferIfPanelVisible: true)
                }
            }
            .store(in: &cancellables)
    }

    private func updateContent() {
        guard let panel else { return }
        let panelSize = panelContentSize(for: settingsStore.recordingIndicatorStyle, renderState: currentRenderState)
        let shadowInset = Constants.panelShadowInset
        let contentWidth = max(1, panelSize.width - (shadowInset * 2))
        let contentHeight = max(1, panelSize.height - (shadowInset * 2))

        let indicatorView = FloatingRecordingIndicatorView(
            audioMonitor: audioMonitor,
            style: settingsStore.recordingIndicatorStyle,
            renderState: currentRenderState,
            processingSnapshot: currentProcessingSnapshot,
            isAnimationActive: isVisible && !prefersReducedMotion,
            onStop: onStopAction,
            onCancel: onCancelAction
        )
        let rootView = AnyView(
            indicatorView
                // Keep a fixed hosting size so NSHostingView doesn't try to animate the NSPanel
                // dimensions in response to transient overlay/layout updates.
                .frame(width: contentWidth, height: contentHeight, alignment: .center)
                .padding(shadowInset)
                .frame(width: panelSize.width, height: panelSize.height, alignment: .center)
        )
        if let hostingView {
            hostingView.rootView = rootView
            if panel.contentView !== hostingView {
                panel.contentView = hostingView
            }
        } else {
            let newHostingView = NSHostingView(rootView: rootView)
            hostingView = newHostingView
            panel.contentView = newHostingView
        }
    }

    private func updateMode(_ mode: FloatingRecordingIndicatorMode) {
        switch mode {
        case .starting, .confirmingAutomaticMeetingStart:
            audioMonitor.stopMonitoring()
        case .recording:
            audioMonitor.stopMonitoring()
            audioMonitor.startMonitoring()
        case .processing:
            audioMonitor.stopMonitoring()
        case .error:
            audioMonitor.stopMonitoring()
        }
    }

    private func panelHeight(
        for style: RecordingIndicatorStyle,
        mode: FloatingRecordingIndicatorMode
    ) -> CGFloat {
        switch mode {
        case .error:
            return Constants.panelHeightClassic
        case .starting, .confirmingAutomaticMeetingStart, .recording, .processing:
            switch style {
            case .classic:
                return Constants.panelHeightClassic
            case .mini:
                return Constants.panelHeightMini
            case .super:
                let layout = RecordingIndicatorOverlayLayout.resolve(
                    renderState: currentRenderState.with(mode: mode),
                    settingsStore: settingsStore
                )
                return FloatingRecordingIndicatorViewUtilities.superCardHeight(
                    layout: layout,
                    renderState: currentRenderState.with(mode: mode)
                )
            case .none:
                return Constants.panelHeightMini
            }
        }
    }

    private func panelWidth(
        for style: RecordingIndicatorStyle,
        renderState: RecordingIndicatorRenderState
    ) -> CGFloat {
        switch renderState.mode {
        case .error:
            return Constants.panelWidthError
        case .starting, .confirmingAutomaticMeetingStart, .recording, .processing:
            let layout = RecordingIndicatorOverlayLayout.resolve(
                renderState: renderState,
                settingsStore: settingsStore
            )
            if style == .super {
                return FloatingRecordingIndicatorViewUtilities.superCardWidth(
                    layout: layout,
                    renderState: renderState,
                    processingSnapshot: currentProcessingSnapshot
                )
            }
            let auxiliaryUnitWidth = auxiliaryUnitWidth(for: style)
            let mainOnlyWidth = panelMainOnlyWidth(for: style, renderState: renderState, layout: layout)
            let indicatorSize: FloatingRecordingIndicatorView.IndicatorSize = switch style {
            case .classic:
                .classic
            case .mini, .none:
                .mini
            case .super:
                .super
            }
            let auxiliaryCount = FloatingRecordingIndicatorViewUtilities.externalAuxiliaryControlCount(
                for: indicatorSize,
                renderState: renderState,
                layout: layout
            )
            return mainOnlyWidth + (CGFloat(auxiliaryCount) * auxiliaryUnitWidth)
        }
    }

    private func panelMainOnlyWidth(
        for style: RecordingIndicatorStyle,
        renderState: RecordingIndicatorRenderState,
        layout: RecordingIndicatorOverlayLayout
    ) -> CGFloat {
        let indicatorSize: FloatingRecordingIndicatorView.IndicatorSize = switch style {
        case .classic:
            .classic
        case .mini, .none:
            .mini
        case .super:
            .super
        }

        let collapsedWidth = FloatingRecordingIndicatorViewUtilities.mainPillWidth(
            for: indicatorSize,
            renderState: renderState,
            layout: layout,
            expanded: false,
            processingSnapshot: currentProcessingSnapshot
        )
        let expandedWidth = FloatingRecordingIndicatorViewUtilities.mainPillWidth(
            for: indicatorSize,
            renderState: renderState,
            layout: layout,
            expanded: true,
            processingSnapshot: currentProcessingSnapshot
        )
        return max(collapsedWidth, expandedWidth)
    }

    private func auxiliaryUnitWidth(for style: RecordingIndicatorStyle) -> CGFloat {
        let indicatorSize: FloatingRecordingIndicatorView.IndicatorSize = switch style {
        case .classic:
            .classic
        case .mini, .none:
            .mini
        case .super:
            .super
        }

        return FloatingRecordingIndicatorViewUtilities.promptSize(for: indicatorSize)
            + AppDesignSystem.Layout.recordingIndicatorPromptGap
    }

    private func shouldShowIndicator(for mode: FloatingRecordingIndicatorMode) -> Bool {
        switch mode {
        case .error:
            true
        case .starting, .confirmingAutomaticMeetingStart, .recording, .processing:
            settingsStore.recordingIndicatorEnabled && settingsStore.recordingIndicatorStyle != .none
        }
    }

    private func presentPanel(_ panel: NSPanel, animated: Bool) {
        if isRunningTests || prefersReducedMotion || !animated {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            return
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        animatePanelAlpha(panel, to: 1, duration: 0.12)
    }

    private func dismissPanel(_ panel: NSPanel, transitionID: UInt64) {
        if isRunningTests || prefersReducedMotion {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard let self, let panel else { return }
                guard visibilityTransitionID == transitionID else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    private func animatePanelAlpha(
        _ panel: NSPanel,
        to alphaValue: CGFloat,
        duration: TimeInterval
    ) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            panel.animator().alphaValue = alphaValue
        }
    }

    private func panelContentSize(
        for style: RecordingIndicatorStyle,
        renderState: RecordingIndicatorRenderState
    ) -> NSSize {
        let contentWidth = panelWidth(for: style, renderState: renderState)
        let contentHeight = panelHeight(for: style, mode: renderState.mode)
        let inset = Constants.panelShadowInset * 2
        return NSSize(width: contentWidth + inset, height: contentHeight + inset)
    }

    private func applyPanelGeometry(_ panel: NSPanel, deferIfPanelVisible: Bool) {
        deferredGeometryTask?.cancel()
        deferredGeometryTask = nil

        if !deferIfPanelVisible {
            applyPanelFrame(panel)
            return
        }

        deferredGeometryTask = Task { @MainActor [weak self, weak panel] in
            await Task.yield()
            guard let self, let panel else { return }
            applyPanelFrame(panel)
            deferredGeometryTask = nil
        }
    }

    private func applyPanelFrame(_ panel: NSPanel) {
        let style = settingsStore.recordingIndicatorStyle
        let contentSize = panelContentSize(for: style, renderState: currentRenderState)
        guard let frame = panelFrame(for: panel, contentSize: contentSize, position: settingsStore.recordingIndicatorPosition) else {
            return
        }

        panel.setFrame(frame, display: true)
    }

    private func panelFrame(
        for panel: NSPanel,
        contentSize: NSSize,
        position: RecordingIndicatorPosition
    ) -> NSRect? {
        guard let screen = activeTargetScreen(for: panel) else { return nil }
        let screenFrame = screen.visibleFrame
        let frameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size

        let x = screenFrame.origin.x + (screenFrame.width - frameSize.width) / 2

        let y: CGFloat = switch position {
        case .top:
            screenFrame.origin.y + screenFrame.height - frameSize.height - Constants.screenPadding + Constants.panelShadowInset
        case .bottom:
            screenFrame.origin.y + Constants.screenPadding - Constants.panelShadowInset
        }

        return NSRect(origin: NSPoint(x: x, y: y), size: frameSize)
    }

    private func activeTargetScreen(for panel: NSPanel) -> NSScreen? {
        if let keyWindowScreen = NSApp.keyWindow?.screen {
            return keyWindowScreen
        }

        if let mainWindowScreen = NSApp.mainWindow?.screen {
            return mainWindowScreen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return mouseScreen
        }

        return panel.screen ?? NSScreen.main
    }

    // MARK: - Testing Hooks

    func invokeStopActionForTesting() {
        onStopAction()
    }

    func invokeCancelActionForTesting() {
        onCancelAction()
    }

    func panelWidthForTesting(
        style: RecordingIndicatorStyle,
        renderState: RecordingIndicatorRenderState,
        processingSnapshot: RecordingIndicatorProcessingSnapshot? = nil
    ) -> CGFloat {
        let previousSnapshot = currentProcessingSnapshot
        currentProcessingSnapshot = processingSnapshot
        defer { currentProcessingSnapshot = previousSnapshot }
        return panelWidth(for: style, renderState: renderState)
    }

    func panelHeightForTesting(
        style: RecordingIndicatorStyle,
        renderState: RecordingIndicatorRenderState
    ) -> CGFloat {
        let previousRenderState = currentRenderState
        currentRenderState = renderState
        defer { currentRenderState = previousRenderState }
        return panelHeight(for: style, mode: renderState.mode)
    }
}
