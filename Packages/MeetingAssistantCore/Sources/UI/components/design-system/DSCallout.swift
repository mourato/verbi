import SwiftUI

public struct DSCallout: View {
    public enum Kind {
        case info
        case warning
        case error

        var symbolName: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .error: "xmark.octagon.fill"
            }
        }

        var tintColor: Color {
            switch self {
            case .info: AppDesignSystem.Colors.accent
            case .warning: AppDesignSystem.Colors.warning
            case .error: AppDesignSystem.Colors.error
            }
        }

        var backgroundColor: Color {
            tintColor.opacity(0.1)
        }

        var strokeColor: Color {
            tintColor.opacity(0.2)
        }
    }

    private let kind: Kind
    private let title: String
    private let message: String

    public init(kind: Kind, title: String, message: String) {
        self.kind = kind
        self.title = title
        self.message = message
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: kind.symbolName)
                .font(.title2)
                .foregroundStyle(kind.tintColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(kind.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesignSystem.Layout.cardCornerRadius)
                .stroke(kind.strokeColor, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Callout Kinds") {
    VStack(spacing: 12) {
        DSCallout(
            kind: .info,
            title: "Information",
            message: "This action is available and ready to use."
        )
        DSCallout(
            kind: .warning,
            title: "Warning",
            message: "Your model is not installed yet."
        )
        DSCallout(
            kind: .error,
            title: "Error",
            message: "We could not validate this configuration."
        )
    }
    .padding()
    .frame(width: 480)
}
