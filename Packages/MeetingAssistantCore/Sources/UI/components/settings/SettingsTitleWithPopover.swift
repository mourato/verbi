import SwiftUI

public struct SettingsTitleWithPopover: View {
    private let title: String
    private let helperTitle: String?
    private let helperMessage: String?
    private let font: Font
    private let fontWeight: Font.Weight?

    public init(
        title: String,
        helperTitle: String? = nil,
        helperMessage: String? = nil,
        font: Font = .body,
        fontWeight: Font.Weight? = nil
    ) {
        self.title = title
        self.helperTitle = helperTitle
        self.helperMessage = helperMessage
        self.font = font
        self.fontWeight = fontWeight
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 6) {
            titleView
                .layoutPriority(1)

            if let helperMessage, !helperMessage.isEmpty {
                DSInfoPopoverButton(
                    title: helperTitle ?? title,
                    message: helperMessage,
                    accessibilityLabel: title
                )
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        let text = Text(title)
            .font(font)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

        if let fontWeight {
            text.fontWeight(fontWeight)
        } else {
            text
        }
    }
}

#Preview {
    SettingsTitleWithPopover(
        title: "Auto-export summaries",
        helperMessage: "Automatically saves the meeting summary as Markdown in the selected folder."
    )
    .padding()
}
