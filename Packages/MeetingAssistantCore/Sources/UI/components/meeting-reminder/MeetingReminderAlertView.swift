import MeetingAssistantCoreDomain
import SwiftUI

struct MeetingReminderAlertView: View {
    let event: MeetingCalendarEventSnapshot
    let prefersRecordPrimary: Bool
    let onPrimary: () -> Void
    let onJoin: () -> Void
    let onNotes: () -> Void
    let onDismiss: () -> Void
    let onSnooze: (Int) -> Void
    let onSnoozeUntilEnd: () -> Void

    @State private var now = Date()
    @State private var snoozeOpen = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var alertState: MeetingReminderAlertState {
        MeetingReminderAlertState.compute(now: now, start: event.startDate)
    }

    var body: some View {
        ZStack {
            backdrop
            card
                .frame(maxWidth: MeetingReminderAlertMetrics.cardMaxWidth)
                .padding(MeetingReminderAlertMetrics.outerPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .onReceive(timer) { date in
            now = date
        }
    }

    private var backdrop: some View {
        ZStack {
            if reduceTransparency {
                AppDesignSystem.Colors.overlayBackground
            } else {
                MeetingReminderMeshBackdrop()
                RadialGradient(
                    colors: [.clear, .black.opacity(0.25)],
                    center: .center,
                    startRadius: 300,
                    endRadius: 1400
                )
                .blendMode(.multiply)
            }
        }
        .ignoresSafeArea()
    }

    private var card: some View {
        HStack(alignment: .center, spacing: MeetingReminderAlertMetrics.columnSpacing) {
            MeetingReminderAlertMetadataColumn(event: event, now: now, alertState: alertState)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1.1)
            MeetingReminderAlertActionsColumn(
                event: event,
                prefersRecordPrimary: prefersRecordPrimary,
                onPrimary: onPrimary,
                onJoin: onJoin,
                onNotes: onNotes,
                onDismiss: onDismiss,
                onSnooze: onSnooze,
                onSnoozeUntilEnd: onSnoozeUntilEnd,
                snoozeOpen: $snoozeOpen
            )
            .frame(minWidth: 300, idealWidth: 360, maxWidth: 400)
            .layoutPriority(1.0)
        }
        .padding(.vertical, MeetingReminderAlertMetrics.cardPaddingVertical)
        .padding(.horizontal, MeetingReminderAlertMetrics.cardPaddingHorizontal)
        .background(glassBackground)
        .overlay(glassBorder)
        .clipShape(RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.cardCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 80, x: 0, y: 30)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var glassBackground: some View {
        if reduceTransparency {
            Color(red: 0.11, green: 0.10, blue: 0.13)
        } else {
            ZStack {
                VisualEffectView(material: .fullScreenUI, blendingMode: .withinWindow)
                LinearGradient(
                    colors: [Color.black.opacity(0.05), Color.black.opacity(0.18)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [Color.white.opacity(0.16), .clear],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.4)
                )
            }
        }
    }

    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: MeetingReminderAlertMetrics.cardCornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.30), Color.white.opacity(0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
    }
}
