import SwiftUI

public struct SettingsContextMenuButton<MenuContent: View>: View {
    private let accessibilityLabel: String
    private let accessibilityHint: String?
    private let symbolColor: Color
    private let menuContent: () -> MenuContent

    public init(
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        symbolColor: Color = .secondary,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.symbolColor = symbolColor
        self.menuContent = menuContent
    }

    public var body: some View {
        Menu {
            menuContent()
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(symbolColor)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .highPriorityGesture(TapGesture())
        .accessibilityLabel(accessibilityLabel)
        .modifier(OptionalA11yHintModifier(accessibilityHint: accessibilityHint))
    }
}

private struct OptionalA11yHintModifier: ViewModifier {
    let accessibilityHint: String?

    func body(content: Content) -> some View {
        if let accessibilityHint, !accessibilityHint.isEmpty {
            content.accessibilityHint(accessibilityHint)
        } else {
            content
        }
    }
}

#Preview("Context Menu Button") {
    SettingsContextMenuButton(accessibilityLabel: "Actions") {
        Button("Edit") {}
        Button("Delete", role: .destructive) {}
    }
    .padding()
}
