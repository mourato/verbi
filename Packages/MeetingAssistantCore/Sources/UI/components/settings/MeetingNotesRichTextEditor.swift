import AppKit
import MeetingAssistantCoreCommon
import SwiftUI

// MARK: - Rich Text Editor Shell

struct MeetingNotesRichTextEditor: View {
    private static let toolbarControlWidth: CGFloat = 16
    private static let toolbarControlHeight: CGFloat = 16

    @Binding var content: MeetingNotesContent
    @StateObject private var editorController = MeetingNotesRichTextController()
    @State private var isShowingLinkEditor = false
    @State private var linkInput = ""

    init(content: Binding<MeetingNotesContent>) {
        _content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            toolbar
            shortcutsHint
            MeetingNotesRichTextRepresentable(
                content: $content,
                controller: editorController,
                fontFamilyKey: MeetingNotesTypographyDefaults.systemFontFamilyKey,
                fontSize: CGFloat(MeetingNotesTypographyDefaults.defaultFontSize),
            )
        }
        .sheet(isPresented: $isShowingLinkEditor) {
            linkEditorSheet
        }
    }

    private var shortcutsHint: some View {
        Text("meeting_notes.rich_text.shortcuts.cheatsheet".localized)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            toolbarButton(
                title: "meeting_notes.rich_text.toolbar.bold".localized,
                systemImage: "bold",
                isActive: editorController.isBoldEnabled,
            ) {
                editorController.toggleBold()
            }

            toolbarButton(
                title: "meeting_notes.rich_text.toolbar.italic".localized,
                systemImage: "italic",
                isActive: editorController.isItalicEnabled,
            ) {
                editorController.toggleItalic()
            }

            toolbarButton(
                title: "meeting_notes.rich_text.toolbar.ordered_list".localized,
                systemImage: "list.number",
            ) {
                editorController.toggleOrderedList()
            }

            toolbarButton(
                title: "meeting_notes.rich_text.toolbar.unordered_list".localized,
                systemImage: "list.bullet",
            ) {
                editorController.toggleUnorderedList()
            }

            toolbarButton(
                title: "meeting_notes.rich_text.toolbar.link".localized,
                systemImage: "link",
            ) {
                linkInput = editorController.selectedLinkString ?? "https://"
                isShowingLinkEditor = true
            }

            Spacer(minLength: 0)
        }
    }

    private var linkEditorSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("meeting_notes.rich_text.link_sheet.title".localized)
                .font(.headline)

            TextField("meeting_notes.rich_text.link_sheet.placeholder".localized, text: $linkInput)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    applyLinkAndDismiss()
                }

            HStack(spacing: 8) {
                Spacer()
                Button("common.cancel".localized) {
                    isShowingLinkEditor = false
                }
                .keyboardShortcut(.cancelAction)

                Button("meeting_notes.rich_text.link_sheet.apply".localized) {
                    applyLinkAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func applyLinkAndDismiss() {
        editorController.applyLink(linkInput)
        isShowingLinkEditor = false
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        isActive: Bool? = nil,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: Self.toolbarControlWidth, height: Self.toolbarControlHeight)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(isActive == true ? .accentColor : nil)
        .accessibilityLabel(title)
        .help(title)
    }
}

#Preview("Meeting Notes Rich Text Editor") {
    PreviewStateContainer(MeetingNotesContent.empty) { content in
        MeetingNotesRichTextEditor(content: content)
            .frame(width: 700, height: 280)
            .padding(12)
    }
}
