import SwiftUI
import VerbiCoreCommon

public struct MeetingQuestionComposerTextView: View {
    @Binding private var text: String
    private let placeholder: String
    private let minHeight: CGFloat
    private let maxHeight: CGFloat
    private let sendOnReturn: Bool
    private let onSubmit: () -> Void
    private let focused: FocusState<Bool>.Binding

    public init(
        text: Binding<String>,
        placeholder: String,
        minHeight: CGFloat = 36,
        maxHeight: CGFloat = 140,
        sendOnReturn: Bool = false,
        focused: FocusState<Bool>.Binding,
        onSubmit: @escaping () -> Void
    ) {
        _text = text
        self.placeholder = placeholder
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.sendOnReturn = sendOnReturn
        self.focused = focused
        self.onSubmit = onSubmit
    }

    public var body: some View {
        TextField(
            placeholder,
            text: $text,
            axis: .vertical
        )
        .focused(focused)
        .textFieldStyle(.plain)
        .lineLimit(1 ... 5)
        .frame(minHeight: minHeight, maxHeight: maxHeight, alignment: .topLeading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(AppDesignSystem.Colors.settingsCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                .stroke(AppDesignSystem.Colors.settingsCardStroke, lineWidth: 1)
        )
        .onKeyPress(.return, phases: .down) { press in
            if press.modifiers.contains(.command) {
                onSubmit()
                return .handled
            }

            if sendOnReturn, !press.modifiers.contains(.shift) {
                onSubmit()
                return .handled
            }

            return .ignored
        }
    }
}

#Preview("Question composer") {
    @Previewable @FocusState var focused: Bool
    @Previewable @State var text = "How can I improve the onboarding flow?"

    MeetingQuestionComposerTextView(
        text: $text,
        placeholder: "transcription.qa.placeholder".localized,
        focused: $focused,
        onSubmit: {}
    )
    .frame(width: 420)
    .padding()
}
