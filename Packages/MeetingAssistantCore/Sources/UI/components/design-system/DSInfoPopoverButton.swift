import SwiftUI

public struct DSInfoPopoverButton: View {
    private let title: String
    private let message: String
    private let iconSystemName: String
    private let accessibilityLabel: String
    @State private var isPopoverPresented = false

    public init(
        title: String,
        message: String,
        iconSystemName: String = "info.circle",
        accessibilityLabel: String? = nil
    ) {
        self.title = title
        self.message = message
        self.iconSystemName = iconSystemName
        self.accessibilityLabel = accessibilityLabel ?? title
    }

    public var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            Image(systemName: iconSystemName)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(AppDesignSystem.Layout.cardPadding)
            .frame(width: 340, alignment: .leading)
        }
    }
}

#Preview {
    DSInfoPopoverButton(
        title: "External remap (optional)",
        message: "Map double-modifier gestures externally and assign F18/F19/F20 in the app."
    )
    .padding()
}
