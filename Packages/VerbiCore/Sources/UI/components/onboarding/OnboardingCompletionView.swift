import SwiftUI

public struct OnboardingCompletionView: View {
    let readiness: OnboardingMeetingRecordingReadiness
    let onStartUsing: () -> Void

    public init(
        readiness: OnboardingMeetingRecordingReadiness,
        onStartUsing: @escaping () -> Void
    ) {
        self.readiness = readiness
        self.onStartUsing = onStartUsing
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "checkmark.circle.fill")
                    .resizable().scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundStyle(.green)
            }

            Text("onboarding.completion.title".localized)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(readiness.completionSubtitleKey.localized)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button("onboarding.completion.button".localized, action: onStartUsing)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .frame(maxWidth: 350)
        }
        .padding(32)
    }
}

#Preview {
    OnboardingCompletionView(
        readiness: OnboardingMeetingRecordingReadiness(
            microphoneGranted: true,
            screenRecordingGranted: true,
            transcriptionModelReady: true,
            isMeetingRecordingEnabled: true,
            wasSkipped: false
        ),
        onStartUsing: {}
    )
    .frame(width: 600, height: 500)
}
