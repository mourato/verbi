import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain

/// Meeting detail header: the resolved title plus a wrapping row of static chips.
///
/// Spec: DESIGN.md "Meeting detail" (epic #164, issue #160). This view owns
/// only the title and the chips rows; the Copy menu belongs to #162 and the
/// tabs below belong to #161.
struct MeetingConversationViewHeader: View {
    let meeting: CaptureSession

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesignSystem.Layout.spacing8) {
            Text(meeting.resolvedTitle)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.tail)
                .help(meeting.resolvedTitle)
            MeetingDetailChipsLayout {
                dateChip
                if meeting.endTime != nil {
                    durationChip
                }
                if !participantNames.isEmpty {
                    participantsChip
                }
                sourceChip
            }
        }
        .padding(.horizontal, AppDesignSystem.Layout.spacing16)
        .padding(.top, AppDesignSystem.Layout.spacing16)
        .padding(.bottom, AppDesignSystem.Layout.spacing16)
    }

    private var dateChip: some View {
        chip(
            text: dateText,
            systemImage: "calendar",
            accessibilityLabel: "meeting.detail.date.accessibility".localized(with: dateText),
            helpText: dateText
        )
    }

    private var durationChip: some View {
        chip(
            text: meeting.formattedDuration,
            systemImage: "timer",
            accessibilityLabel: "meeting.detail.duration.accessibility".localized(with: meeting.formattedDuration),
            helpText: meeting.formattedDuration,
            font: .callout.monospacedDigit()
        )
    }

    private var participantsChip: some View {
        chip(
            text: participantsText,
            systemImage: "person.2",
            accessibilityLabel: "meeting.detail.participants.accessibility".localized(with: participantsText),
            helpText: participantNames.joined(separator: ", ")
        )
    }

    private var sourceChip: some View {
        chip(
            text: meeting.appName,
            systemImage: meeting.appIcon,
            accessibilityLabel: "meeting.detail.source.accessibility".localized(with: meeting.appName),
            helpText: meeting.appName
        )
    }

    private func chip(
        text: String,
        systemImage: String,
        accessibilityLabel: String,
        helpText: String,
        font: Font = .callout
    ) -> some View {
        Label(text, systemImage: systemImage)
            .font(font)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, AppDesignSystem.Layout.spacing8)
            .padding(.vertical, AppDesignSystem.Layout.spacing4)
            .background(
                AppDesignSystem.Colors.subtleFill,
                in: RoundedRectangle(
                    cornerRadius: AppDesignSystem.Layout.chipCornerRadius,
                    style: .continuous
                )
            )
            .help(helpText)
            .accessibilityLabel(accessibilityLabel)
    }

    private var dateText: String {
        meeting.startTime.formatted(
            .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()
        )
    }

    private var participantNames: [String] {
        (meeting.linkedCalendarEvent?.attendees ?? []).filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var participantsText: String {
        let shown = participantNames.prefix(2).joined(separator: ", ")
        let remaining = participantNames.count - min(2, participantNames.count)
        guard remaining > 0 else { return shown }
        return "\(shown) \("meeting.detail.participants.remaining".localized(with: remaining))"
    }
}

/// Left-to-right wrapping flow for the meeting detail chips.
///
/// An HStack never wraps, so the spec calls for a small custom Layout: chips
/// sit left to right with spacing8 and start a new line when the next chip
/// does not fit. A single chip wider than the column is constrained to the
/// column width so its text truncates with a tail ellipsis instead of
/// overflowing.
struct MeetingDetailChipsLayout: Layout {
    var horizontalSpacing: CGFloat = AppDesignSystem.Layout.spacing8
    var verticalSpacing: CGFloat = AppDesignSystem.Layout.spacing8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        _ = cache
        guard !subviews.isEmpty else { return .zero }
        let maxWidth = proposal.width ?? .infinity
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let width = min(ideal.width, maxWidth)
            if cursorX > 0, cursorX + horizontalSpacing + width > maxWidth {
                cursorX = 0
                cursorY += rowHeight + verticalSpacing
                rowHeight = 0
            } else if cursorX > 0 {
                cursorX += horizontalSpacing
            }
            rowHeight = max(rowHeight, ideal.height)
            cursorX += width
        }
        let width = maxWidth.isInfinite ? cursorX : maxWidth
        return CGSize(width: width, height: cursorY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        _ = cache
        _ = proposal
        let maxWidth = bounds.width
        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let ideal = subview.sizeThatFits(.unspecified)
            let width = min(ideal.width, maxWidth)
            if cursorX > 0, cursorX + horizontalSpacing + width > maxWidth {
                cursorX = 0
                cursorY += rowHeight + verticalSpacing
                rowHeight = 0
            } else if cursorX > 0 {
                cursorX += horizontalSpacing
            }
            rowHeight = max(rowHeight, ideal.height)
            subview.place(
                at: CGPoint(x: bounds.minX + cursorX, y: bounds.minY + cursorY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: rowHeight)
            )
            cursorX += width
        }
    }
}

#Preview("Meeting detail header") {
    MeetingConversationViewHeader(meeting: CaptureSession(
        app: .zoom,
        title: "Launch planning",
        linkedCalendarEvent: MeetingCalendarEventSnapshot(
            eventIdentifier: "preview-event",
            title: "Launch planning",
            startDate: Date(timeIntervalSince1970: 1_762_795_800),
            endDate: Date(timeIntervalSince1970: 1_762_796_520),
            attendees: ["Kara", "Ray", "Mo", "Jo"]
        ),
        state: .completed,
        startTime: Date(timeIntervalSince1970: 1_762_795_800),
        endTime: Date(timeIntervalSince1970: 1_762_796_520)
    ))
    .frame(width: 560)
}

#Preview("Meeting detail header narrow") {
    MeetingConversationViewHeader(meeting: CaptureSession(
        app: .zoom,
        title: "A very long meeting title that needs two lines before it truncates with an ellipsis",
        linkedCalendarEvent: MeetingCalendarEventSnapshot(
            eventIdentifier: "preview-event",
            title: "A very long meeting title",
            startDate: Date(timeIntervalSince1970: 1_762_795_800),
            endDate: Date(timeIntervalSince1970: 1_762_796_520),
            attendees: ["Kara Whitfield", "Raymond Duarte", "Mo", "Jo"]
        ),
        state: .completed,
        startTime: Date(timeIntervalSince1970: 1_762_795_800),
        endTime: Date(timeIntervalSince1970: 1_762_796_520)
    ))
    .frame(width: 220)
}
