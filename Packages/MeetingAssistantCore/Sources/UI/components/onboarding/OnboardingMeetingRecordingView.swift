import SwiftUI

// MARK: - Onboarding Meeting Recording View

public struct OnboardingMeetingRecordingView: View {
    let readiness: OnboardingMeetingRecordingReadiness
    let onEnable: () -> Void
    let onOpenPermissions: () -> Void
    let onOpenModels: () -> Void
    let onContinue: () -> Void
    let onSkip: (() -> Void)?

    public init(
        readiness: OnboardingMeetingRecordingReadiness,
        onEnable: @escaping () -> Void,
        onOpenPermissions: @escaping () -> Void,
        onOpenModels: @escaping () -> Void,
        onContinue: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.readiness = readiness
        self.onEnable = onEnable
        self.onOpenPermissions = onOpenPermissions
        self.onOpenModels = onOpenModels
        self.onContinue = onContinue
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(spacing: 20) {
            header
                .padding(.top, 20)

            VStack(spacing: 12) {
                readinessRow(
                    iconName: "mic.fill",
                    titleKey: "onboarding.meeting_recording.microphone",
                    isSatisfied: readiness.microphoneGranted
                )

                readinessRow(
                    iconName: "rectangle.on.rectangle",
                    titleKey: "onboarding.meeting_recording.screen_recording",
                    isSatisfied: readiness.screenRecordingGranted
                )

                readinessRow(
                    iconName: "waveform",
                    titleKey: "onboarding.meeting_recording.local_model",
                    isSatisfied: readiness.transcriptionModelReady
                )
            }
            .padding(.horizontal, 20)

            if !readiness.prerequisitesSatisfied {
                missingPrerequisitesActions
            }

            resourceNote

            Spacer()

            navigationButtons
                .padding(.bottom, 24)
        }
        .frame(maxWidth: 550)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.badge.waveform")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("onboarding.meeting_recording.title".localized)
                .font(.title2)
                .fontWeight(.bold)

            Text("onboarding.meeting_recording.subtitle".localized)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var missingPrerequisitesActions: some View {
        HStack(spacing: 12) {
            if !readiness.microphoneGranted || !readiness.screenRecordingGranted {
                Button("onboarding.meeting_recording.open_permissions".localized, action: onOpenPermissions)
                    .buttonStyle(.bordered)
            }

            if !readiness.transcriptionModelReady {
                Button("onboarding.meeting_recording.open_models".localized, action: onOpenModels)
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.regular)
    }

    private var resourceNote: some View {
        Text("onboarding.meeting_recording.resource_note".localized)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
    }

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            if onSkip != nil {
                Button(action: { onSkip?() }) {
                    Text("onboarding.skip".localized)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
            }

            Button(action: primaryAction) {
                Text(primaryButtonKey.localized)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!readiness.prerequisitesSatisfied)
        }
        .frame(maxWidth: 400)
    }

    private var primaryButtonKey: String {
        readiness.isMeetingRecordingEnabled
            ? "onboarding.continue"
            : "onboarding.meeting_recording.enable"
    }

    private func primaryAction() {
        if readiness.isMeetingRecordingEnabled {
            onContinue()
        } else {
            onEnable()
        }
    }

    private func readinessRow(iconName: String, titleKey: String, isSatisfied: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)

            Text(titleKey.localized)
                .font(.subheadline)
                .foregroundStyle(.primary)

            Spacer()

            Label(
                statusKey(isSatisfied: isSatisfied).localized,
                systemImage: isSatisfied ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(isSatisfied ? Color.green : Color.orange)
            .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private func statusKey(isSatisfied: Bool) -> String {
        isSatisfied
            ? "onboarding.meeting_recording.status.ready"
            : "onboarding.meeting_recording.status.needs_setup"
    }
}

#Preview {
    OnboardingMeetingRecordingView(
        readiness: OnboardingMeetingRecordingReadiness(
            microphoneGranted: true,
            screenRecordingGranted: true,
            transcriptionModelReady: false,
            isMeetingRecordingEnabled: false,
            wasSkipped: false
        ),
        onEnable: {},
        onOpenPermissions: {},
        onOpenModels: {},
        onContinue: {},
        onSkip: {}
    )
    .frame(width: 600, height: 550)
}
