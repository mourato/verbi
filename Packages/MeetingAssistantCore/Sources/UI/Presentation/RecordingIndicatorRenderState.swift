import Foundation
import MeetingAssistantCoreDomain

public enum RecordingIndicatorKind: Sendable, Equatable {
    case dictation
    case assistant
    case assistantIntegration
    case meeting
}

public struct RecordingIndicatorRenderState: Sendable, Equatable {
    public let mode: FloatingRecordingIndicatorMode
    public let kind: RecordingIndicatorKind
    public let assistantIntegrationID: UUID?
    public let meetingType: MeetingType?

    public init(
        mode: FloatingRecordingIndicatorMode,
        kind: RecordingIndicatorKind,
        assistantIntegrationID: UUID? = nil,
        meetingType: MeetingType? = nil
    ) {
        self.mode = mode
        self.kind = kind
        self.assistantIntegrationID = assistantIntegrationID
        self.meetingType = meetingType
    }

    public func with(mode: FloatingRecordingIndicatorMode) -> RecordingIndicatorRenderState {
        RecordingIndicatorRenderState(
            mode: mode,
            kind: kind,
            assistantIntegrationID: assistantIntegrationID,
            meetingType: meetingType
        )
    }

    public static func fromLegacy(mode: FloatingRecordingIndicatorMode, meetingType: MeetingType?) -> RecordingIndicatorRenderState {
        let kind: RecordingIndicatorKind = meetingType == nil ? .dictation : .meeting
        return RecordingIndicatorRenderState(
            mode: mode,
            kind: kind,
            assistantIntegrationID: nil,
            meetingType: meetingType
        )
    }

    public static func forRecordingSource(
        mode: FloatingRecordingIndicatorMode,
        recordingSource: RecordingSource,
        meetingType: MeetingType?
    ) -> RecordingIndicatorRenderState {
        switch recordingSource {
        case .microphone:
            RecordingIndicatorRenderState(
                mode: mode,
                kind: .dictation,
                assistantIntegrationID: nil,
                meetingType: nil
            )
        case .system, .all:
            RecordingIndicatorRenderState(
                mode: mode,
                kind: .meeting,
                assistantIntegrationID: nil,
                meetingType: meetingType
            )
        }
    }
}
