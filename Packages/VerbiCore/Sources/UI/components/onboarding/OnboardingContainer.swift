import SwiftUI

public struct OnboardingContainer<Content: View>: View {
    private let content: () -> Content

    @ScaledMetric(relativeTo: .body) private var horizontalPadding: CGFloat = 32
    @ScaledMetric(relativeTo: .body) private var verticalPadding: CGFloat = 20

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        ZStack {
            SettingsWindowBackground()

            content()
                .frame(maxWidth: 680, maxHeight: .infinity)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
        }
        .frame(
            minWidth: 520,
            idealWidth: 620,
            maxWidth: .infinity,
            minHeight: 460,
            idealHeight: 520,
            maxHeight: .infinity
        )
    }
}

#Preview {
    OnboardingContainer {
        Text("onboarding.title".localized)
    }
    .frame(width: 620, height: 520)
}
