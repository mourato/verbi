import SwiftUI

public struct DSCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var accessibilityReduceTransparency
    @Environment(\.settingsReduceTransparencyPreview) private var reduceTransparencyPreview

    public enum Style {
        case standard
        case settings
    }

    private let style: Style
    private let settingsSurfaceIntensity: AppDesignSystem.SettingsSurfaceIntensity
    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let content: Content

    public init(
        style: Style = .standard,
        settingsSurfaceIntensity: AppDesignSystem.SettingsSurfaceIntensity = .subtle,
        cornerRadius: CGFloat = AppDesignSystem.Layout.cardCornerRadius,
        padding: CGFloat = AppDesignSystem.Layout.cardPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.settingsSurfaceIntensity = settingsSurfaceIntensity
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppDesignSystem.Layout.itemSpacing) {
            content
        }
        .padding(padding)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        switch style {
        case .standard:
            shape
                .fill(AppDesignSystem.Colors.cardBackground)
                .overlay {
                    shape.stroke(AppDesignSystem.Colors.cardStroke, lineWidth: 0.5)
                }
        case .settings:
            // One surface treatment: semantic fill (+ stroke). Do not stack
            // regularMaterial under an opaque tint — that competed with the
            // Settings window canvas for ordinary collection content.
            shape
                .fill(
                    AppDesignSystem.Colors.settingsMaterialCardFill(
                        reduceTransparency: reduceTransparency,
                        intensity: settingsSurfaceIntensity
                    )
                )
                .overlay {
                    shape.stroke(settingsCardStroke, lineWidth: settingsCardStrokeWidth)
                }
        }
    }

    private var reduceTransparency: Bool {
        accessibilityReduceTransparency || reduceTransparencyPreview
    }

    private var settingsCardStroke: Color {
        AppDesignSystem.Colors.settingsMaterialCardStroke(
            increaseContrast: AppDesignSystem.Accessibility.increaseContrast
        )
    }

    private var settingsCardStrokeWidth: CGFloat {
        AppDesignSystem.Accessibility.increaseContrast ? 0.75 : 0.5
    }
}

#Preview("DSCard") {
    DSCard {
        VStack(alignment: .leading, spacing: 8) {
            Text("Design System Card")
                .font(.headline)
            Text("A reusable card with a subtle material background and corner treatment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    .padding()
    .frame(width: 280)
}
