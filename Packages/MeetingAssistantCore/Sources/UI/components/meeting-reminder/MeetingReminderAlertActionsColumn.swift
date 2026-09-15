import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

struct MeetingReminderAlertActionsColumn: View {
    let event: MeetingCalendarEventSnapshot
    let prefersRecordPrimary: Bool
    let onPrimary: () -> Void
    let onJoin: () -> Void
    let onNotes: () -> Void
    let onDismiss: () -> Void
    let onSnooze: (Int) -> Void
    let onSnoozeUntilEnd: () -> Void

    @Binding var snoozeOpen: Bool

    var body: some View {
        VStack(spacing: MeetingReminderAlertMetrics.rightColumnSpacing) {
            primaryActionButtons
            notesButton
            actionsRow
            keyboardHint
        }
    }

    @ViewBuilder
    private var primaryActionButtons: some View {
        if prefersRecordPrimary {
            recordButton
                .keyboardShortcut(.defaultAction)
            if event.joinURL != nil {
                joinButton
            }
        } else if event.joinURL != nil {
            joinButton
                .keyboardShortcut(.defaultAction)
        } else {
            recordButton
                .keyboardShortcut(.defaultAction)
        }
    }

    private var recordButton: some View {
        Button(action: onPrimary) {
            HStack {
                HStack(spacing: 10) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                    Text("meeting_reminder.overlay.primary.record".localized)
                        .font(.system(size: 16, weight: .semibold))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 16))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(recordGradient, in: RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.primaryCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.primaryCornerRadius)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            }
            .shadow(color: AppDesignSystem.Colors.recording.opacity(0.6), radius: 20, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .meetingReminderClickCursor()
    }

    @ViewBuilder
    private var joinButton: some View {
        if event.joinURL != nil {
            Button(action: prefersRecordPrimary ? onJoin : onPrimary) {
                HStack {
                    HStack(spacing: 10) {
                        platformBadge
                        Text(joinLabel)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .background(joinGradient, in: RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.primaryCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.primaryCornerRadius)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: AppDesignSystem.Colors.accent.opacity(0.6), radius: 20, x: 0, y: 6)
            }
            .buttonStyle(.plain)
            .meetingReminderClickCursor()
        }
    }

    private var notesButton: some View {
        Button(action: onNotes) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                    .font(.system(size: 14))
                Text("meeting_reminder.overlay.secondary.notes".localized)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.secondaryCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.secondaryCornerRadius)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .meetingReminderClickCursor()
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            Button {
                snoozeOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 14))
                    Text("meeting_reminder.overlay.secondary.snooze".localized)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(snoozeOpen ? 180 : 0))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.secondaryCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.secondaryCornerRadius)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .meetingReminderClickCursor()
            .animation(.easeOut(duration: 0.16), value: snoozeOpen)
            .frame(maxWidth: .infinity)

            Button(action: onDismiss) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                    Text("meeting_reminder.overlay.secondary.dismiss".localized)
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.secondaryCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.secondaryCornerRadius)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .meetingReminderClickCursor()
            .keyboardShortcut(.cancelAction)
        }
        .overlay(alignment: .bottomLeading) {
            if snoozeOpen {
                snoozeDropdown
                    .offset(y: -58)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)))
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.16), value: snoozeOpen)
    }

    private var snoozeDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("meeting_reminder.overlay.snooze.header".localized)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ForEach(MeetingReminderScheduler.SnoozeInterval.allCases, id: \.rawValue) { interval in
                snoozeOption(label: snoozeTitle(for: interval)) {
                    onSnooze(interval.rawValue)
                    snoozeOpen = false
                }
            }

            Divider().padding(.vertical, 4)
            snoozeOption(label: "meeting_reminder.overlay.snooze.until_end".localized) {
                onSnoozeUntilEnd()
                snoozeOpen = false
            }
        }
        .padding(6)
        .frame(width: MeetingReminderAlertMetrics.snoozeDropdownWidth)
        .background(
            Color(red: 0.11, green: 0.10, blue: 0.13).opacity(0.98),
            in: RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.secondaryCornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.secondaryCornerRadius)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 24, x: 0, y: 10)
    }

    private func snoozeOption(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .meetingReminderClickCursor()
    }

    private var keyboardHint: some View {
        HStack(spacing: 14) {
            Text("meeting_reminder.overlay.keyboard.return".localized(with: primaryKeyboardLabel))
            Text("meeting_reminder.overlay.keyboard.esc".localized(with: "meeting_reminder.overlay.secondary.dismiss".localized))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.white.opacity(0.35))
        .padding(.top, 2)
    }

    private var recordGradient: LinearGradient {
        LinearGradient(
            colors: [AppDesignSystem.Colors.recording, AppDesignSystem.Colors.recording.opacity(0.82)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var joinGradient: LinearGradient {
        LinearGradient(
            colors: [AppDesignSystem.Colors.accent, AppDesignSystem.Colors.accent.opacity(0.82)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var platformBadge: some View {
        let url = event.joinURL?.absoluteString.lowercased() ?? ""
        let color = if url.contains("zoom.us") {
            Color(red: 0.23, green: 0.54, blue: 0.82)
        } else if url.contains("teams.microsoft") || url.contains("teams.live") {
            Color(red: 0.42, green: 0.42, blue: 0.82)
        } else if url.contains("meet.google") {
            Color(red: 0.23, green: 0.66, blue: 0.42)
        } else {
            Color(red: 0.53, green: 0.53, blue: 0.53)
        }

        return ZStack {
            RoundedRectangle(cornerRadius: 6).fill(color)
            Image(systemName: "video.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }

    private var joinLabel: String {
        let url = event.joinURL?.absoluteString.lowercased() ?? ""
        if url.contains("zoom.us") {
            return "meeting_reminder.overlay.join.zoom".localized
        }
        if url.contains("teams.microsoft") || url.contains("teams.live") {
            return "meeting_reminder.overlay.join.teams".localized
        }
        if url.contains("meet.google") {
            return "meeting_reminder.overlay.join.meet".localized
        }
        if url.contains("webex.com") {
            return "meeting_reminder.overlay.join.webex".localized
        }
        return "meeting_reminder.overlay.join.generic".localized
    }

    private var primaryKeyboardLabel: String {
        if prefersRecordPrimary {
            return "meeting_reminder.overlay.primary.record".localized
        }
        if event.joinURL != nil {
            return joinLabel
        }
        return "meeting_reminder.overlay.primary.record".localized
    }

    private func snoozeTitle(for interval: MeetingReminderScheduler.SnoozeInterval) -> String {
        switch interval {
        case .one: "meeting_reminder.overlay.snooze.1".localized
        case .five: "meeting_reminder.overlay.snooze.5".localized
        case .ten: "meeting_reminder.overlay.snooze.10".localized
        case .fifteen: "meeting_reminder.overlay.snooze.15".localized
        }
    }
}
