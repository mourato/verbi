import MeetingAssistantCoreCommon
import SwiftUI

struct AutoMeetingConfirmationPill: View {
    let size: FloatingRecordingIndicatorView.IndicatorSize
    let timing: (deadline: Date, duration: TimeInterval)?
    let isAnimationActive: Bool
    let onCancel: @Sendable () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: FloatingRecordingIndicatorViewUtilities.contentSpacing(for: size)) {
            statusDot

            countdownText
                .frame(
                    width: FloatingRecordingIndicatorViewUtilities.confirmationMessageWidth(for: size),
                    alignment: .leading
                )

            ActionIconButton(
                symbol: "xmark",
                helpKey: "recording_indicator.auto_meeting_confirmation.cancel.help",
                keyboardShortcut: .escape,
                style: .warning
            ) {
                onCancel()
            }
        }
        .padding(.horizontal, FloatingRecordingIndicatorViewUtilities.horizontalPadding(for: size, expanded: false))
        .frame(
            width: FloatingRecordingIndicatorViewUtilities.confirmationPillWidth(for: size),
            height: FloatingRecordingIndicatorViewUtilities.controlHeight(for: size)
        )
        .background(.ultraThinMaterial)
        .background(fill)
        .overlay(
            Capsule()
                .strokeBorder(AppDesignSystem.Colors.recordingIndicatorStroke, lineWidth: 1.2)
        )
        .clipShape(Capsule())
        .contentShape(Capsule())
        .shadow(
            color: .black.opacity(0.15),
            radius: AppDesignSystem.Layout.recordingIndicatorMainShadowRadius,
            x: AppDesignSystem.Layout.shadowX,
            y: AppDesignSystem.Layout.recordingIndicatorMainShadowY
        )
        .accessibilityLabel(message(at: Date()))
    }

    private var statusDot: some View {
        Circle()
            .fill(AppDesignSystem.Colors.accent)
            .frame(
                width: AppDesignSystem.Layout.recordingIndicatorDotSize,
                height: AppDesignSystem.Layout.recordingIndicatorDotSize
            )
            .modifier(PulsingModifier(isActive: isAnimationActive, speed: 1.2))
    }

    private var countdownText: some View {
        Group {
            if isAnimationActive, !reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                    Text(message(at: context.date))
                        .contentTransition(.numericText())
                }
            } else {
                Text(message(at: Date()))
            }
        }
        .font(Font(FloatingRecordingIndicatorViewUtilities.confirmationFont(for: size)))
        .foregroundStyle(AppDesignSystem.Colors.overlayForeground)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var fill: some View {
        Group {
            if isAnimationActive, !reduceMotion {
                TimelineView(.periodic(from: .now, by: 0.2)) { context in
                    fillShape(progress: progress(at: context.date))
                }
            } else {
                fillShape(progress: 1)
            }
        }
        .background(AppDesignSystem.Colors.recordingIndicatorMaterialTint)
    }

    private func fillShape(progress: CGFloat) -> some View {
        GeometryReader { proxy in
            Rectangle()
                .fill(AppDesignSystem.Colors.recording.opacity(0.22))
                .frame(width: proxy.size.width * progress)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func message(at date: Date) -> String {
        let seconds = max(0, Int(ceil((timing?.deadline ?? date).timeIntervalSince(date))))
        if seconds == 1 {
            return "recording_indicator.auto_meeting_confirmation.countdown.one".localized
        }
        return "recording_indicator.auto_meeting_confirmation.countdown.other".localized(with: seconds)
    }

    private func progress(at date: Date) -> CGFloat {
        guard let timing, timing.duration > 0 else { return 1 }
        let remaining = max(0, timing.deadline.timeIntervalSince(date))
        return CGFloat(min(1, max(0, 1 - (remaining / timing.duration))))
    }
}
