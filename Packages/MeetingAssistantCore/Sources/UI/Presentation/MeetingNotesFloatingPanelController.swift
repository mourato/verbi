import AppKit
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import SwiftUI

@MainActor
public final class MeetingNotesFloatingPanelController {
    private let paneController: MeetingNotesPaneController

    public init(paneController: MeetingNotesPaneController = MeetingNotesPaneController()) {
        self.paneController = paneController
    }

    public var isVisible: Bool {
        paneController.isVisible
    }

    public func show(
        content: MeetingNotesContent,
        documentId: String = "meeting-notes-panel",
        onTextChange: @escaping (MeetingNotesContent) -> Void,
        onClose: @escaping () -> Void
    ) {
        _ = content
        _ = documentId
        _ = onTextChange

        if let meetingID = RecordingManager.shared.currentMeeting?.id {
            paneController.summon(scope: .meetingSession(meetingID: meetingID))
        } else {
            paneController.summon()
        }

        paneController.setVisibilityHandler { isVisible in
            if !isVisible {
                onClose()
            }
        }
    }

    public func hide() {
        paneController.dismiss()
    }
}

#if DEBUG
    #Preview("Meeting Notes Floating Panel") {
        MeetingNotesMarkdownEditor(
            content: .constant(MeetingNotesContent(plainText: "- Revisar backlog\n- Alinhar owners para Q2")),
            documentId: "meeting-notes-panel-preview"
        )
        .frame(width: 620, height: 300)
    }
#endif
