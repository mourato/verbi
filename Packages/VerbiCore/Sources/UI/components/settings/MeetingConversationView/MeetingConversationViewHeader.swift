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

    /// One chip with the width it occupies in its row and its height.
    private struct PlacedChip {
        var index: Int
        var width: CGFloat
        var height: CGFloat
    }

    /// Breaks chips into rows, left to right, starting a new row when the next
    /// chip does not fit. A chip wider than the column is constrained to the
    /// column width so its text truncates instead of overflowing. Shared by
    /// measurement and placement so the two can never desync.
    private func breakIntoRows(sizes: [CGSize], maxWidth: CGFloat) -> [[PlacedChip]] {
        var rows: [[PlacedChip]] = []
        var current: [PlacedChip] = []
        var cursorX: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let width = min(size.width, maxWidth)
            if !current.isEmpty, cursorX + horizontalSpacing + width > maxWidth {
                rows.append(current)
                current = []
                cursorX = 0
            } else if !current.isEmpty {
                cursorX += horizontalSpacing
            }
            current.append(PlacedChip(index: index, width: width, height: size.height))
            cursorX += width
        }
        if !current.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private func rowHeight(_ row: [PlacedChip]) -> CGFloat {
        row.map(\.height).max() ?? 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        _ = cache
        guard !subviews.isEmpty else { return .zero }
        let maxWidth = proposal.width ?? .infinity
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = breakIntoRows(sizes: sizes, maxWidth: maxWidth)
        let height = rows.map { rowHeight($0) }.reduce(0, +)
            + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        if maxWidth.isInfinite {
            let width = rows.map { row in
                row.reduce(0) { $0 + $1.width } + CGFloat(max(0, row.count - 1)) * horizontalSpacing
            }.max() ?? 0
            return CGSize(width: width, height: height)
        }
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        _ = cache
        _ = proposal
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = breakIntoRows(sizes: sizes, maxWidth: bounds.width)
        var cursorY = bounds.minY
        for row in rows {
            let height = rowHeight(row)
            var cursorX = bounds.minX
            for chip in row {
                subviews[chip.index].place(
                    at: CGPoint(x: cursorX, y: cursorY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: chip.width, height: height)
                )
                cursorX += chip.width + horizontalSpacing
            }
            cursorY += height + verticalSpacing
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
