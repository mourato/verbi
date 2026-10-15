import AppKit
import Foundation
import MeetingAssistantCoreDomain
import SwiftUI

/// Non-blocking toast surface presenting detected meeting status and actions.
public struct MeetingDetectionToastView: View {
    public let state: MeetingDetectionToastState
    public let onRecord: () -> Void
    public let onChooseTemplate: () -> Void
    public let onRecordWithoutSummary: () -> Void
    public let onStop: () -> Void
    public let onContinue: () -> Void
    public let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        state: MeetingDetectionToastState,
        onRecord: @escaping () -> Void = {},
        onChooseTemplate: @escaping () -> Void = {},
        onRecordWithoutSummary: @escaping () -> Void = {},
        onStop: @escaping () -> Void = {},
        onContinue: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onRecord = onRecord
        self.onChooseTemplate = onChooseTemplate
        self.onRecordWithoutSummary = onRecordWithoutSummary
        self.onStop = onStop
        self.onContinue = onContinue
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            appIconView

            metadataColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            actionArea
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 380, height: 88)
        .background(toastBackground)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - App Icon

    private var appIconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .frame(width: 48, height: 48)

            Image(systemName: state.app.icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AppDesignSystem.Colors.accent)
                .accessibilityHidden(true)

            if case let .ended(_, _, countdownSeconds, totalCountdownSeconds) = state {
                CountdownRing(
                    countdownSeconds: countdownSeconds,
                    totalCountdownSeconds: totalCountdownSeconds
                )
            }
        }
        .frame(width: 54, height: 54)
        .accessibilityLabel(state.appName)
    }

    // MARK: - Metadata Column

    private var metadataColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            titleView
            subtitleView
        }
    }

    @ViewBuilder
    private var titleView: some View {
        switch state {
        case .detected:
            Text("toast.meeting_detected".localized)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        case .recording:
            HStack(spacing: 6) {
                PulsingDotView()
                Text("toast.recording_meeting".localized)
                    .font(.system(size: 15.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        case .ended:
            Text("toast.meeting_ending".localized)
                .font(.system(size: 15.5, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var subtitleView: some View {
        switch state {
        case .detected:
            Text(state.appName)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case let .recording(_, _, startedAt):
            TimelineView(.periodic(from: startedAt, by: 1.0)) { context in
                Text(formatElapsedTime(since: startedAt, at: context.date))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case let .ended(_, _, countdownSeconds, _):
            Text(String(format: "toast.ending_countdown".localized, countdownSeconds))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Action Area

    @ViewBuilder
    private var actionArea: some View {
        switch state {
        case .detected:
            splitRecordButton
        case .recording:
            stopButton
        case .ended:
            continueButton
        }
    }

    private var splitRecordButton: some View {
        HStack(spacing: 0) {
            Button(action: onRecord) {
                Text("toast.action.record".localized)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GhostButtonStyle())
            .accessibilityLabel("toast.action.record".localized)

            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 24)

            Menu {
                Button("toast.menu.choose_template".localized, action: onChooseTemplate)
                Button("toast.menu.record_without_summary".localized, action: onRecordWithoutSummary)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 46)
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("toast.menu.options".localized)
        }
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var stopButton: some View {
        Button(action: onStop) {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)

                Text("toast.action.stop".localized)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(GhostButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityLabel("toast.action.stop".localized)
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            Text("toast.action.continue".localized)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .frame(height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(GhostButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityLabel("toast.action.continue".localized)
    }

    // MARK: - Toast Background

    private var toastBackground: some View {
        ZStack {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            } else {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            }
        }
    }

    private func formatElapsedTime(since start: Date, at current: Date) -> String {
        let elapsed = max(0, Int(current.timeIntervalSince(start)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Supporting Views

private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

private struct PulsingDotView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            if !reduceMotion {
                Circle()
                    .fill(Color.red.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .scaleEffect(isPulsing ? 1.4 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.8)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            if !reduceMotion {
                isPulsing = true
            }
        }
    }
}

private struct CountdownRing: View {
    let countdownSeconds: Int
    let totalCountdownSeconds: Int

    private var progress: Double {
        guard totalCountdownSeconds > 0 else { return 0 }
        return Double(countdownSeconds) / Double(totalCountdownSeconds)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .trim(from: 0, to: CGFloat(progress))
            .stroke(
                AppDesignSystem.Colors.accent,
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .frame(width: 52, height: 52)
            .animation(.linear(duration: 1.0), value: countdownSeconds)
    }
}
