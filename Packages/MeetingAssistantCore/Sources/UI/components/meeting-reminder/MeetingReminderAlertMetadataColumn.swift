import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import SwiftUI

struct MeetingReminderAlertMetadataColumn: View {
    let event: MeetingCalendarEventSnapshot
    let now: Date
    let alertState: MeetingReminderAlertState

    var body: some View {
        VStack(alignment: .leading, spacing: MeetingReminderAlertMetrics.leftColumnSpacing) {
            statePill
            Text(displayTitle)
                .font(.system(size: 56, weight: .semibold))
                .tracking(-2)
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            timeRow
            metaRow
        }
    }

    private var statePill: some View {
        HStack(spacing: 10) {
            stateDot
            Text(
                "\("meeting_reminder.overlay.status.meeting".localized) · \(alertState.statusSuffix(now: now, start: event.startDate).uppercased())"
            )
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(.white.opacity(0.6))
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stateDot: some View {
        switch alertState.dotKind {
        case .none:
            EmptyView()
        case .live:
            MeetingReminderPulsingDot(color: Color(red: 0.18, green: 0.63, blue: 0.29))
        case .urgent:
            MeetingReminderPulsingDot(color: Color(red: 0.91, green: 0.39, blue: 0.23))
        }
    }

    private var timeRow: some View {
        HStack(spacing: 14) {
            Text(timeString(event.startDate))
                .monospacedDigit()
            Rectangle()
                .fill(.white.opacity(0.4))
                .frame(width: 18, height: 1)
            Text(timeString(event.endDate))
                .monospacedDigit()
        }
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(.white.opacity(0.85))
    }

    @ViewBuilder
    private var metaRow: some View {
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !location.isEmpty || !event.attendees.isEmpty {
            HStack(spacing: 16) {
                if !location.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 13))
                        Text(location)
                            .font(.system(size: 13))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.55))
                }

                if !event.attendees.isEmpty {
                    if !location.isEmpty {
                        Circle()
                            .fill(.white.opacity(0.3))
                            .frame(width: 3, height: 3)
                    }
                    HStack(spacing: 8) {
                        MeetingReminderAvatarStack(names: event.attendees)
                        if event.attendees.count > 4 {
                            Text("+ \(event.attendees.count - 4)")
                                .font(.system(size: 13).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private var displayTitle: String {
        let trimmed = event.trimmedTitle
        return trimmed.isEmpty ? "metrics.calendar.event.untitled".localized : trimmed
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
