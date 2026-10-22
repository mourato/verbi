import Foundation
import MeetingAssistantCoreDomain

public actor RecordingExclusivityCoordinator {
    public static let shared = RecordingExclusivityCoordinator()

    private var activeMode: CaptureMode?

    /// Compatibility name for callers that distinguish the active mode type.
    public typealias ActiveMode = CaptureMode

    /// Compatibility name for callers that distinguish recording modes.
    public typealias RecordingMode = CaptureMode

    private init() {}

    /// Backward-compatible entry point used by older tests/callers.
    public func beginRecording() -> Bool {
        beginRecording(mode: .meeting)
    }

    public func beginRecording(mode: CaptureMode) -> Bool {
        guard mode != .assistant, activeMode == nil else {
            return false
        }

        activeMode = mode
        return true
    }

    public func endRecording() {
        guard activeMode == .dictation || activeMode == .meeting else {
            return
        }

        activeMode = nil
    }

    public func beginAssistant() -> Bool {
        guard activeMode == nil else {
            return false
        }

        activeMode = .assistant
        return true
    }

    public func endAssistant() {
        guard activeMode == .assistant else {
            return
        }

        activeMode = nil
    }

    public func activeModeSnapshot() -> CaptureMode? {
        activeMode
    }

    public func activeRecordingMode() -> CaptureMode? {
        switch activeMode {
        case .dictation:
            .dictation
        case .meeting:
            .meeting
        case .assistant, .none:
            nil
        }
    }

    public func isRecordingActive(mode: CaptureMode) -> Bool {
        mode != .assistant && activeMode == mode
    }

    public func blockingMode(for requestedMode: CaptureMode) -> CaptureMode? {
        guard let activeMode, activeMode != requestedMode else {
            return nil
        }
        return activeMode
    }
}
