import AppKit
import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain

struct MeetingConversationViewHeader: View {
    let meeting: CaptureSession
    let copy: MeetingCopyContent

    @State private var justCopied = false
    @State private var copyRevertTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesignSystem.Layout.spacing8) {
            HStack(alignment: .firstTextBaseline) {
                Text(meeting.resolvedTitle)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .help(meeting.resolvedTitle)
                Spacer(minLength: AppDesignSystem.Layout.spacing8)
                copyMenu
            }
            MeetingDetailChipsLayout {
                dateChip
                if chipTexts.duration != nil {
                    durationChip
                }
                if chipTexts.participants != nil {
                    participantsChip
                }
                sourceChip
            }
        }
        .padding(.horizontal, AppDesignSystem.Layout.spacing16)
        .padding(.top, AppDesignSystem.Layout.spacing16)
        .padding(.bottom, AppDesignSystem.Layout.spacing16)
    }

    private var chipTexts: MeetingDetailChipTexts {
        MeetingDetailChipTexts(meeting: meeting)
    }

    private var dateChip: some View {
        chip(
            text: chipTexts.date,
            systemImage: "calendar",
            accessibilityLabel: "meeting.detail.date.accessibility".localized(with: chipTexts.date),
            helpText: chipTexts.date
        )
    }

    private var durationChip: some View {
        let duration = chipTexts.duration ?? ""
        return chip(
            text: duration,
            systemImage: "timer",
            accessibilityLabel: "meeting.detail.duration.accessibility".localized(with: duration),
            helpText: duration,
            font: .callout.monospacedDigit()
        )
    }

    private var participantsChip: some View {
        let participants = chipTexts.participants ?? ""
        return chip(
            text: participants,
            systemImage: "person.2",
            accessibilityLabel: "meeting.detail.participants.accessibility".localized(with: participants),
            helpText: chipTexts.allParticipantNames
        )
    }

    private var sourceChip: some View {
        chip(
            text: chipTexts.source,
            systemImage: meeting.appIcon,
            accessibilityLabel: "meeting.detail.source.accessibility".localized(with: chipTexts.source),
            helpText: chipTexts.source
        )
    }

    private var copyMenu: some View {
        Menu {
            Button("meeting.detail.copy.summary".localized) {
                if let summary = copy.summary {
                    copyText(summary)
                }
            }
            .disabled(!copy.hasSummary)
            Button("meeting.detail.copy.transcript".localized) {
                copyText(copy.transcript)
            }
            .disabled(!copy.hasTranscript)
            Button("meeting.detail.copy.notes".localized) {
                copyText(copy.notes)
            }
            .disabled(!copy.hasNotes)
            Divider()
            Button("meeting.detail.copy.all".localized) {
                copyText(copy.copyAllMarkdown())
            }
            .disabled(!copy.hasAnything)
        } label: {
            Label(
                justCopied ? "meeting.detail.copy.copied".localized : "common.copy".localized,
                systemImage: justCopied ? "checkmark" : "doc.on.doc"
            )
        } primaryAction: {
            guard let summary = copy.summary else { return }
            copyText(summary)
        }
        .controlSize(.regular)
        .buttonStyle(.bordered)
    }

    private func copyText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        justCopied = true
        copyRevertTask?.cancel()
        copyRevertTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            justCopied = false
        }
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
}

struct MeetingDetailChipsLayout: Layout {
    var horizontalSpacing: CGFloat = AppDesignSystem.Layout.spacing8
    var verticalSpacing: CGFloat = AppDesignSystem.Layout.spacing8

    private struct PlacedChip {
        var index: Int
        var width: CGFloat
        var height: CGFloat
    }

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
    let meeting = previewMeeting(title: "Launch planning", attendees: ["Kara", "Ray", "Mo", "Jo"])
    return MeetingConversationViewHeader(
        meeting: meeting,
        copy: MeetingCopyContent(
            meeting: meeting,
            summary: "The team aligned on the launch scope.",
            sortedSegments: [],
            fallbackTranscript: "Kara: Launch scope is frozen.",
            notes: "Follow up on Friday."
        )
    )
    .frame(width: 560)
}

#Preview("Meeting detail header narrow") {
    let meeting = previewMeeting(
        title: "A very long meeting title that needs two lines before it truncates with an ellipsis",
        attendees: ["Kara Whitfield", "Raymond Duarte", "Mo", "Jo"]
    )
    return MeetingConversationViewHeader(
        meeting: meeting,
        copy: MeetingCopyContent(
            meeting: meeting,
            summary: "The team aligned on the launch scope.",
            sortedSegments: [],
            fallbackTranscript: "Kara: Launch scope is frozen.",
            notes: "Follow up on Friday."
        )
    )
    .frame(width: 220)
}

private func previewMeeting(title: String, attendees: [String]) -> CaptureSession {
    CaptureSession(
        app: .zoom,
        title: title,
        linkedCalendarEvent: MeetingCalendarEventSnapshot(
            eventIdentifier: "preview-event",
            title: title,
            startDate: Date(timeIntervalSince1970: 1_762_795_800),
            endDate: Date(timeIntervalSince1970: 1_762_796_520),
            attendees: attendees
        ),
        state: .completed,
        startTime: Date(timeIntervalSince1970: 1_762_795_800),
        endTime: Date(timeIntervalSince1970: 1_762_796_520)
    )
}
