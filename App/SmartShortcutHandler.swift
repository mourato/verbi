import AppKit
import Foundation
import MeetingAssistantCore

/// Adapter used by app controllers while we migrate from legacy activation modes
/// to the in-house shortcut engine contract.
@MainActor
final class SmartShortcutHandler {
    enum Action {
        case startRecording
        case stopRecording
    }

    private(set) var isPressed = false
    private let executionEngine: ShortcutExecutionEngine

    private let actionHandler: (Action) -> Void
    private let isRecordingProvider: () -> Bool

    init(
        holdThreshold: TimeInterval = 0.5,
        doubleTapInterval: TimeInterval = 0.25,
        isRecordingProvider: @escaping () -> Bool,
        actionHandler: @escaping (Action) -> Void
    ) {
        executionEngine = ShortcutExecutionEngine(
            holdThreshold: holdThreshold,
            doubleTapInterval: doubleTapInterval
        )
        self.isRecordingProvider = isRecordingProvider
        self.actionHandler = actionHandler
    }

    func reset() {
        isPressed = false
        executionEngine.reset()
    }

    func setDoubleTapInterval(_ interval: TimeInterval) {
        executionEngine.updateDoubleTapInterval(interval)
    }

    func handleShortcutDown(activationMode: ShortcutActivationMode) {
        switch activationMode {
        case .toggle:
            applyActions(executionEngine.handleDown(trigger: .singleTap, isRecording: isRecordingProvider()))
        case .hold:
            applyActions(executionEngine.handleDown(trigger: .hold, isRecording: isRecordingProvider()))
        case .holdOrToggle:
            applyActions(executionEngine.handleHoldOrToggleDown(isRecording: isRecordingProvider()))
        case .doubleTap:
            break
        }
    }

    func handleShortcutUp(activationMode: ShortcutActivationMode) {
        switch activationMode {
        case .hold:
            applyActions(executionEngine.handleUp(trigger: .hold, isRecording: isRecordingProvider()))
        case .holdOrToggle:
            applyActions(executionEngine.handleHoldOrToggleUp())
        case .doubleTap:
            applyActions(executionEngine.handleUp(trigger: .doubleTap, isRecording: isRecordingProvider()))
        case .toggle:
            break
        }
    }

    func handleModifierChange(isActive: Bool) {
        if isActive, !isPressed {
            isPressed = true
        } else if !isActive, isPressed {
            isPressed = false
        }
    }

    // MARK: - ShortcutInputEvent handlers (for pluggable backend)

    func handleFlagsChanged(inputEvent _: ShortcutInputEvent) {
        // No-op for flags changed in SmartShortcutHandler
        // This is handled at a higher level in the routing orchestrator
    }

    func handleKeyDown(inputEvent _: ShortcutInputEvent) {
        // No-op for key down - handled via handleShortcutDown with activation mode
    }

    func handleKeyUp(inputEvent _: ShortcutInputEvent) {
        // No-op for key up - handled via handleShortcutUp with activation mode
    }

    private func applyActions(_ actions: [ShortcutExecutionAction]) {
        for action in actions {
            switch action {
            case .start:
                actionHandler(.startRecording)
            case .stop:
                actionHandler(.stopRecording)
            }
        }
    }
}
