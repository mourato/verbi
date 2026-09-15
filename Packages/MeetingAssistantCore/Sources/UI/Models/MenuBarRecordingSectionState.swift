import MeetingAssistantCoreDomain

public enum MenuBarRecordingSectionState: Equatable, Sendable {
    case idle
    case dictationActive
    case meetingActive
    case assistantActive

    public init(
        isRecordingManagerActive: Bool,
        recordingSource: RecordingSource,
        capturePurpose: CapturePurpose? = nil,
        isAssistantRecording: Bool
    ) {
        if isAssistantRecording {
            self = .assistantActive
            return
        }

        guard isRecordingManagerActive else {
            self = .idle
            return
        }

        if let capturePurpose {
            switch capturePurpose {
            case .dictation:
                self = .dictationActive
            case .meeting:
                self = .meetingActive
            }
            return
        }

        switch recordingSource {
        case .microphone:
            self = .dictationActive
        case .system, .all:
            self = .meetingActive
        }
    }
}
