import MeetingAssistantCoreCommon
import SwiftUI

struct RecordingSilenceWarningOverlay: View {
    @Binding var isDialogPresented: Bool
    let onContinue: () -> Void
    let onStop: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        Button {
            isDialogPresented = true
        } label: {
            Text("recording_indicator.silence_warning".localized)
                .font(.caption.bold())
                .foregroundStyle(AppDesignSystem.Colors.overlayStatusForeground)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: true, vertical: true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(AppDesignSystem.Colors.recordingOverlayBackground)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(AppDesignSystem.Colors.recordingIndicatorStroke, lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(0.2),
            radius: AppDesignSystem.Layout.shadowRadiusSmall,
            x: AppDesignSystem.Layout.shadowX,
            y: AppDesignSystem.Layout.shadowYSmall
        )
        .contentShape(Capsule())
        .accessibilityLabel("recording_indicator.silence_warning".localized)
        .accessibilityHint("recording_indicator.silence_warning.accessibility_hint".localized)
        .confirmationDialog(
            "recording_indicator.silence_warning.confirmation.title".localized,
            isPresented: $isDialogPresented
        ) {
            Button("recording_indicator.silence_warning.action.continue".localized) {
                onContinue()
            }
            Button("recording_indicator.silence_warning.action.stop".localized) {
                onStop()
            }
            Button("recording_indicator.silence_warning.action.discard".localized, role: .destructive) {
                onDiscard()
            }
        }
    }
}

struct RecordingPostProcessingWarningOverlay: View {
    let descriptor: RecordingPostProcessingWarningDescriptor
    let onOpenSettings: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppDesignSystem.Colors.overlayStatusForeground)

            Text(descriptor.localizedMessage)
                .font(.caption.bold())
                .foregroundStyle(AppDesignSystem.Colors.overlayStatusForeground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Button("recording_indicator.post_processing_warning.open_settings".localized) {
                descriptor.openSettings(using: onOpenSettings)
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppDesignSystem.Colors.overlayStatusForeground)
            .underline()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppDesignSystem.Colors.warning.opacity(0.95))
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .strokeBorder(AppDesignSystem.Colors.recordingIndicatorStroke, lineWidth: 1)
        )
        .shadow(
            color: .black.opacity(0.2),
            radius: AppDesignSystem.Layout.shadowRadiusSmall,
            x: AppDesignSystem.Layout.shadowX,
            y: AppDesignSystem.Layout.shadowYSmall
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("recording_indicator.post_processing_warning.open_settings".localized)
    }
}

#Preview("Warning overlays") {
    VStack(spacing: 16) {
        RecordingSilenceWarningOverlay(
            isDialogPresented: .constant(false),
            onContinue: {},
            onStop: {},
            onDiscard: {}
        )

        RecordingPostProcessingWarningOverlay(
            descriptor: RecordingPostProcessingWarningDescriptor(
                issue: .missingAPIKey,
                mode: .meeting
            ),
            onOpenSettings: { _ in }
        )
    }
    .padding()
    .frame(width: 360)
}
