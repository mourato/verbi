import MeetingAssistantCoreCommon
import SwiftUI

public struct SummaryTemplateEditorSheet: View {
    private enum Constants {
        static let sheetWidth: CGFloat = 520
        static let sheetHeight: CGFloat = 460
        static let editorMinHeight: CGFloat = 280
    }

    @State private var summaryTemplate: String
    private let onSave: (String) -> Void
    private let onCancel: () -> Void

    public init(
        initialTemplate: String,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _summaryTemplate = State(initialValue: initialTemplate)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("settings.meetings.template_desc".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("settings.meetings.template.editor_hint".localized)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $summaryTemplate)
                        .font(.body.monospaced())
                        .frame(minHeight: Constants.editorMinHeight)
                        .padding(AppDesignSystem.Layout.textAreaPadding)
                        .background(AppDesignSystem.Colors.textBackground)
                        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                                .stroke(AppDesignSystem.Colors.separator, lineWidth: 1)
                        )
                }
                .padding()
            }

            Divider()
            footer
        }
        .frame(width: Constants.sheetWidth, height: Constants.sheetHeight)
        .background {
            SettingsWindowBackground()
        }
    }

    private var header: some View {
        HStack {
            Text("settings.meetings.template.editor_title".localized)
                .font(.headline)
            Spacer()
        }
        .padding()
        .background(AppDesignSystem.Colors.settingsGlassBackground)
    }

    private var footer: some View {
        HStack {
            Button("common.cancel".localized) {
                onCancel()
            }
            .keyboardShortcut(.escape)

            Spacer()

            Button("common.save".localized) {
                onSave(summaryTemplate.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .tint(AppDesignSystem.Colors.accent)
            .disabled(summaryTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
        .background(AppDesignSystem.Colors.settingsGlassBackground)
    }
}

#Preview {
    SummaryTemplateEditorSheet(
        initialTemplate: """
        # {{meeting_title}}
        - Date: {{meeting_date}}

        {{summary}}
        """,
        onSave: { _ in },
        onCancel: {}
    )
}
