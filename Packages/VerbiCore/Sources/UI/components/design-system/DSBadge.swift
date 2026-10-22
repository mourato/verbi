import SwiftUI

public struct DSBadge: View {
    public enum Kind {
        case success
        case warning
        case error
        case neutral

        var background: Color {
            switch self {
            case .success: AppDesignSystem.Colors.success
            case .warning: AppDesignSystem.Colors.warning
            case .error: AppDesignSystem.Colors.error
            case .neutral: AppDesignSystem.Colors.neutral
            }
        }
    }

    private let text: String
    private let kind: Kind

    public init(_ text: String, kind: Kind) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(kind.background))
            .foregroundStyle(Color.white)
            .accessibilityLabel(text)
    }
}

#Preview("Badge Kinds") {
    HStack(spacing: 8) {
        DSBadge("Success", kind: .success)
        DSBadge("Warning", kind: .warning)
        DSBadge("Error", kind: .error)
        DSBadge("Neutral", kind: .neutral)
    }
    .padding()
}
