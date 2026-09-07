import SwiftUI

struct SettingsSearchField: View {
    private enum Layout {
        static let height: CGFloat = 30
    }

    enum Style {
        case standard
        case history
    }

    @Binding var text: String
    let placeholder: String
    var style: Style = .standard

    var body: some View {
        switch style {
        case .standard:
            nativeField(style: .standard)
        case .history:
            DSCard(
                style: .settings,
                cornerRadius: AppDesignSystem.Layout.largeCornerRadius,
                padding: 0,
            ) {
                nativeField(style: .sidebar)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
    }

    private func nativeField(style: NativeSearchField.Style) -> some View {
        NativeSearchField(
            text: $text,
            placeholder: placeholder,
            style: style,
        )
        .frame(height: Layout.height)
    }
}

#Preview("Settings Search Field") {
    SettingsSearchField(
        text: .constant("Transcript"),
        placeholder: "settings.transcriptions.search_placeholder".localized,
        style: .history,
    )
    .padding(16)
    .frame(width: 320)
}
