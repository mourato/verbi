import SwiftUI

public struct MAEmptyStateView: View {
    public enum Emphasis {
        case compact
        case prominent
    }

    private let iconName: String
    private let title: String
    private let message: String?
    private let emphasis: Emphasis

    public init(
        iconName: String = "tray",
        title: String,
        message: String? = nil,
        emphasis: Emphasis = .prominent
    ) {
        self.iconName = iconName
        self.title = title
        self.message = message
        self.emphasis = emphasis
    }

    public var body: some View {
        VStack(spacing: stackSpacing) {
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppDesignSystem.Colors.neutral)
                .frame(width: iconContainerSize, height: iconContainerSize)
                .background(AppDesignSystem.Colors.neutral.opacity(0.08))
                .clipShape(Circle())

            VStack(spacing: AppDesignSystem.Layout.spacing6) {
                Text(title)
                    .font(titleFont)
                    .fontWeight(.semibold)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(contentPadding)
        .accessibilityElement(children: .combine)
    }

    private var isProminent: Bool {
        emphasis == .prominent
    }

    private var iconSize: CGFloat {
        isProminent ? 56 : 32
    }

    private var iconContainerSize: CGFloat {
        isProminent ? 112 : 64
    }

    private var stackSpacing: CGFloat {
        isProminent ? 24 : 16
    }

    private var contentPadding: CGFloat {
        isProminent ? 24 : 12
    }

    private var titleFont: Font {
        isProminent ? .system(size: 24) : .headline
    }
}

#Preview("Prominent") {
    MAEmptyStateView(
        iconName: "clock.arrow.circlepath",
        title: "No transcriptions",
        message: "Record a meeting to get started."
    )
    .frame(width: 560, height: 420)
}

#Preview("Compact") {
    MAEmptyStateView(
        iconName: "tray",
        title: "No upcoming events",
        message: "There are no events scheduled.",
        emphasis: .compact
    )
    .frame(width: 420)
    .padding()
}
