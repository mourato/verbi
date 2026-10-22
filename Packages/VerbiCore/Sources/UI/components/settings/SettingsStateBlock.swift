import SwiftUI

public struct SettingsStateBlock: View {
    public enum Kind {
        case loading
        case empty
        case warning
        case success
    }

    private let kind: Kind
    private let title: String
    private let message: String?
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        kind: Kind,
        title: String,
        message: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        DSCard {
            HStack(alignment: .top, spacing: 12) {
                icon

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)

                    if let message, !message.isEmpty {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let actionTitle, let action {
                        Button(actionTitle) {
                            action()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(width: 24, height: 24)
        case .empty:
            Image(systemName: "tray")
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppDesignSystem.Colors.warning)
                .frame(width: 24, height: 24)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppDesignSystem.Colors.success)
                .frame(width: 24, height: 24)
        }
    }
}

#Preview("Warning State") {
    SettingsStateBlock(
        kind: .warning,
        title: "Could not load this section",
        message: "Try again in a few seconds."
    )
    .padding()
}
