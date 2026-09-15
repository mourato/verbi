import MeetingAssistantCoreCommon
import SwiftUI

public struct DictationStylePromptEditorView: View {
    @Binding private var promptInstructions: String
    @FocusState private var isPromptEditorFocused: Bool
    private let onCancel: () -> Void

    public init(
        promptInstructions: Binding<String>,
        onCancel: @escaping () -> Void
    ) {
        _promptInstructions = promptInstructions
        self.onCancel = onCancel
    }

    public var body: some View {
        ModeEditorDrawer(
            headerStyle: .back,
            title: "settings.styles.editor.prompt".localized,
            onBack: onCancel
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("settings.styles.editor.prompt_hint".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $promptInstructions)
                    .font(.body)
                    .frame(minHeight: 320)
                    .focused($isPromptEditorFocused)
                    .padding(AppDesignSystem.Layout.textAreaPadding)
                    .background(AppDesignSystem.Colors.subtleFill2)
                    .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
                    .accessibilityLabel("settings.styles.editor.prompt".localized)
            }
        }
        .onAppear {
            isPromptEditorFocused = true
        }
    }
}

#Preview("Prompt Editor") {
    DictationStylePromptEditorView(
        promptInstructions: .constant("Prefer concise bullets and list action items at the end."),
        onCancel: {}
    )
}
