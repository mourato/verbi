import SwiftUI

private struct SettingsInlineListPreviewItem: Identifiable {
    let id = UUID()
    let title: String
}

public struct SettingsInlineList<Item: Identifiable, RowContent: View>: View {
    public enum State {
        case ready
        case loading(title: String, message: String? = nil)
        case warning(title: String, message: String? = nil)
    }

    public enum ContainerStyle {
        case card
        case plain
    }

    private let items: [Item]
    private let emptyText: String
    private let state: State
    private let containerStyle: ContainerStyle
    private let rowContent: (Item) -> RowContent

    public init(
        items: [Item],
        emptyText: String,
        state: State = .ready,
        containerStyle: ContainerStyle = .card,
        @ViewBuilder rowContent: @escaping (Item) -> RowContent
    ) {
        self.items = items
        self.emptyText = emptyText
        self.state = state
        self.containerStyle = containerStyle
        self.rowContent = rowContent
    }

    public var body: some View {
        switch state {
        case let .loading(title, message):
            SettingsStateBlock(kind: .loading, title: title, message: message)
        case let .warning(title, message):
            SettingsStateBlock(kind: .warning, title: title, message: message)
        case .ready:
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            Text(emptyText)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            switch containerStyle {
            case .card:
                rows
                    .background(AppDesignSystem.Colors.subtleFill2)
                    .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
            case .plain:
                rows
            }
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                rowContent(item)

                if index < items.count - 1 {
                    Divider()
                }
            }
        }
    }
}

#Preview("Settings inline list") {
    SettingsInlineList(
        items: [
            SettingsInlineListPreviewItem(title: "Slack"),
            SettingsInlineListPreviewItem(title: "Teams"),
            SettingsInlineListPreviewItem(title: "Zoom")
        ],
        emptyText: "No items found"
    ) { item in
        Text(item.title)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }
    .frame(width: 320)
    .padding()
}
