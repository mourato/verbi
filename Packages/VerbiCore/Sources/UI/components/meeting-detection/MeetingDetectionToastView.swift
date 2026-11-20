import AppKit
import Foundation
import SwiftUI
import VerbiCoreDomain

public struct MeetingDetectionToastView: View {
    public let state: MeetingDetectionToastState
    public let onRecord: () -> Void
    public let onRecordWithoutSummary: () -> Void
    public let onStop: () -> Void
    public let onKeepRecording: () -> Void
    public let onDismiss: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var isHovering = false
    @FocusState private var dismissFocused: Bool

    public init(
        state: MeetingDetectionToastState,
        onRecord: @escaping () -> Void = {},
        onRecordWithoutSummary: @escaping () -> Void = {},
        onStop: @escaping () -> Void = {},
        onKeepRecording: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onRecord = onRecord
        self.onRecordWithoutSummary = onRecordWithoutSummary
        self.onStop = onStop
        self.onKeepRecording = onKeepRecording
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 12) {
            appIconView

            metadataColumn
                .frame(maxWidth: .infinity, alignment: .leading)

            actionArea
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: MeetingDetectionToastController.Constants.toastWidth)
        .frame(minHeight: 76, maxHeight: 96)
        .background(toastBackground)
        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(toastStroke, lineWidth: 0.5)
        )
        .overlay(alignment: .topLeading) {
            dismissButton
                .opacity(showsDismissButton ? 1 : 0)
                .animation(AppleMotion.animation(reduceMotion: reduceMotion, kind: .default), value: showsDismissButton)
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var isEndPromptState: Bool {
        if case .endPrompt = state {
            return true
        }
        return false
    }

    private var showsDismissButton: Bool {
        isHovering || dismissFocused || voiceOverEnabled || isEndPromptState
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focused($dismissFocused)
        .allowsHitTesting(showsDismissButton)
        .accessibilityLabel("toast.action.dismiss".localized)
        .padding(2)
        .contentShape(Rectangle())
    }

    private var recordPillFill: Color {
        reduceTransparency ? Color(nsColor: .controlColor) : .white
    }

    private var recordPillText: Color {
        reduceTransparency ? .primary : Color.black.opacity(0.85)
    }

    private var endPromptPlateFill: Color {
        reduceTransparency ? Color(nsColor: .controlBackgroundColor) : .white.opacity(0.9)
    }

    private var toastStroke: Color {
        reduceTransparency ? Color(nsColor: .separatorColor) : .white.opacity(0.1)
    }

    private var appIconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .frame(width: 40, height: 40)

            Image(systemName: state.app.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .accessibilityHidden(true)
        }
        .frame(width: 40, height: 40)
        .accessibilityLabel(state.appName)
    }

    private var metadataColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            titleView
            subtitleView
        }
    }

    private var titleView: some View {
        Text(state.appName)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var subtitleView: some View {
        switch state {
        case .detected:
            Text("toast.meeting_detected".localized)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case let .recording(_, _, startedAt):
            TimelineView(.periodic(from: startedAt, by: 1.0)) { context in
                Text("toast.recording_meeting".localized + " · " + formatElapsedTime(since: startedAt, at: context.date))
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case let .endPrompt(_, _, _, deadline):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, Int(ceil(deadline.timeIntervalSince(context.date))))
                Text("toast.meeting_end_prompt".localized(with: remaining))
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch state {
        case .detected:
            splitRecordButton
        case .recording:
            stopButton
        case .endPrompt:
            meetingEndPromptActions
        }
    }

    private var splitRecordButton: some View {
        HStack(spacing: 2) {
            Button(action: onRecord) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text("toast.action.record".localized)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(recordPillText)
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(recordPillFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("toast.action.record".localized)

            Menu {
                Button("toast.menu.record_without_summary".localized, action: onRecordWithoutSummary)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 34)
                    .contentShape(Rectangle())
                    .accessibilityHidden(true)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("toast.menu.options".localized)
        }
    }

    private var stopButton: some View {
        Button(action: onStop) {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)

                Text("toast.action.stop".localized)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(recordPillFill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("toast.action.stop".localized)
    }

    private var meetingEndPromptActions: some View {
        VStack(spacing: 2) {
            Button(action: onStop) {
                Text("toast.action.stop_now".localized)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GhostButtonStyle())
            .accessibilityLabel("toast.action.stop_now".localized)

            Button(action: onKeepRecording) {
                Text("toast.action.keep_recording".localized)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(GhostButtonStyle())
            .accessibilityLabel("toast.action.keep_recording".localized)
        }
        .frame(width: 126)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(endPromptPlateFill)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var toastBackground: some View {
        ZStack {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            } else {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                    .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
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

private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

#Preview("Meeting end prompt") {
    MeetingDetectionToastView(
        state: .endPrompt(
            app: .zoom,
            appName: "Zoom",
            startedAt: .now,
            deadline: .now.addingTimeInterval(30)
        )
    )
}
