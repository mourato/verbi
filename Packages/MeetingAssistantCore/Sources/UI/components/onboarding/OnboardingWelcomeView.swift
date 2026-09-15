import SwiftUI

// MARK: - Onboarding Welcome View

/// The first step of the onboarding flow, welcoming the user.
public struct OnboardingWelcomeView: View {
    let onGetStarted: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 100

    public init(onGetStarted: @escaping () -> Void) {
        self.onGetStarted = onGetStarted
    }

    public var body: some View {
        VStack(spacing: AppDesignSystem.Layout.spacing24) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .resizable().scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            Text("onboarding.welcome.title".localized)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)

            Text("onboarding.welcome.subtitle".localized)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)

            Spacer()

            Button("onboarding.welcome.button".localized, action: onGetStarted)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: 300)
        }
        .padding(32)
    }
}

// MARK: - Preview

#Preview {
    OnboardingWelcomeView(onGetStarted: {})
        .frame(width: 620, height: 520)
}
