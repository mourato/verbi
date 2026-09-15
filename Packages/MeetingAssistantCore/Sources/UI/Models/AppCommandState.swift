import MeetingAssistantCoreInfrastructure

public struct AppCommandState: Equatable, Sendable {
    public var recordingSection: MenuBarRecordingSectionState
    public var cancelRecordingShortcutDefinition: ShortcutDefinition?
    public var meetingCapabilityEnabled: Bool
    public var assistantCapabilityEnabled: Bool

    public init(
        recordingSection: MenuBarRecordingSectionState = .idle,
        cancelRecordingShortcutDefinition: ShortcutDefinition? = nil,
        meetingCapabilityEnabled: Bool = true,
        assistantCapabilityEnabled: Bool = true
    ) {
        self.recordingSection = recordingSection
        self.cancelRecordingShortcutDefinition = cancelRecordingShortcutDefinition
        self.meetingCapabilityEnabled = meetingCapabilityEnabled
        self.assistantCapabilityEnabled = assistantCapabilityEnabled
    }

    public var dictationTitleKey: String {
        recordingSection == .dictationActive ? "menubar.stop_dictation" : "menubar.dictate"
    }

    public var meetingTitleKey: String {
        recordingSection == .meetingActive ? "menubar.stop_recording" : "menubar.record_meeting"
    }

    public var assistantTitleKey: String {
        recordingSection == .assistantActive ? "menubar.stop_assistant" : "menubar.assistant"
    }

    public var cancelTitleKey: String {
        "menubar.cancel_recording"
    }

    public var showsDictationAction: Bool {
        recordingSection == .idle || recordingSection == .dictationActive
    }

    public var showsMeetingAction: Bool {
        meetingCapabilityEnabled && (recordingSection == .idle || recordingSection == .meetingActive)
    }

    public var showsAssistantAction: Bool {
        assistantCapabilityEnabled && (recordingSection == .idle || recordingSection == .assistantActive)
    }

    public var showsCancelAction: Bool {
        recordingSection != .idle
    }
}
