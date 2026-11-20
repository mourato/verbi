import SwiftUI
import VerbiCoreCommon
import VerbiCoreDomain

struct MeetingSummaryView: View {
    private enum SummaryBlock: Hashable {
        case title(String)
        case item(String)
        case paragraph(String)
    }

    private let canonicalSummary: CanonicalSummary?
    private let fallbackText: String
    private let showsFallbackBadge: Bool

    init(
        canonicalSummary: CanonicalSummary?,
        fallbackText: String,
        showsFallbackBadge: Bool
    ) {
        self.canonicalSummary = canonicalSummary
        self.fallbackText = fallbackText
        self.showsFallbackBadge = showsFallbackBadge
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let canonicalSummary {
                canonicalBody(canonicalSummary)
            } else {
                blocksBody(fallbackText)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func canonicalBody(_ summary: CanonicalSummary) -> some View {
        let paragraph = summary.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !paragraph.isEmpty || showsFallbackBadge {
            blocksBody(paragraph)
        }

        if !summary.actionItems.isEmpty {
            summarySection(titleKey: "meeting.summary.section.next_steps") {
                ForEach(Array(summary.actionItems.enumerated()), id: \.offset) { _, item in
                    actionItemRow(item)
                }
            }
        }

        if !summary.decisions.isEmpty {
            summarySection(titleKey: "summary.section.decisions") {
                ForEach(Array(summary.decisions.enumerated()), id: \.offset) { _, decision in
                    bulletRow(inlineFormatted(decision))
                }
            }
        }

        if !summary.keyPoints.isEmpty {
            summarySection(titleKey: "summary.section.key_points") {
                ForEach(Array(summary.keyPoints.enumerated()), id: \.offset) { _, point in
                    bulletRow(inlineFormatted(point))
                }
            }
        }

        if !summary.openQuestions.isEmpty {
            summarySection(titleKey: "summary.section.open_questions") {
                ForEach(Array(summary.openQuestions.enumerated()), id: \.offset) { _, question in
                    bulletRow(inlineFormatted(question))
                }
            }
        }
    }

    private func summarySection(
        titleKey: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: AppDesignSystem.Layout.spacing8) {
            Text(titleKey.localized)
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: AppDesignSystem.Layout.spacing6) {
                content()
            }
        }
        .padding(.top, AppDesignSystem.Layout.spacing20)
    }

    private func actionItemRow(_ item: CanonicalSummary.ActionItem) -> some View {
        bulletContainer {
            actionItemText(item)
        }
    }

    private func actionItemText(_ item: CanonicalSummary.ActionItem) -> Text {
        let owner = (item.owner ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let body =
            if owner.isEmpty {
                Text(inlineFormatted(item.title))
                    .font(.body)
                    .foregroundStyle(.primary)
            } else {
                Text(inlineFormatted(owner))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    + Text(inlineFormatted(": \(item.title)"))
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        guard let dueDate = item.dueDate else {
            return body
        }
        return body
            + Text(" · \(dueDate.formatted(date: .abbreviated, time: .omitted))")
            .font(.body)
            .foregroundStyle(.secondary)
    }

    private func blocksBody(_ text: String) -> some View {
        let blocks = parseBlocks(text)
        return VStack(alignment: .leading, spacing: 0) {
            if blocks.isEmpty {
                if showsFallbackBadge {
                    HStack {
                        Spacer(minLength: 0)
                        fallbackBadge
                    }
                }
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                    if index == 0, showsFallbackBadge {
                        HStack(alignment: .firstTextBaseline) {
                            blockView(block)
                            Spacer(minLength: AppDesignSystem.Layout.spacing8)
                            fallbackBadge
                        }
                    } else {
                        blockView(block)
                            .padding(.top, index > 0 ? topSpacing(for: block, after: blocks[index - 1]) : 0)
                    }
                }
            }
        }
    }

    private func topSpacing(for block: SummaryBlock, after previous: SummaryBlock?) -> CGFloat {
        switch block {
        case .title:
            return AppDesignSystem.Layout.spacing20
        case .item:
            if case .item = previous {
                return AppDesignSystem.Layout.spacing6
            }
            return AppDesignSystem.Layout.spacing8
        case .paragraph:
            return AppDesignSystem.Layout.spacing8
        }
    }

    @ViewBuilder
    private func blockView(_ block: SummaryBlock) -> some View {
        switch block {
        case let .title(value):
            Text(inlineFormatted(value))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        case let .item(value):
            bulletRow(inlineFormatted(value))
        case let .paragraph(value):
            Text(inlineFormatted(value))
                .font(.body)
        }
    }

    private func parseBlocks(_ text: String) -> [SummaryBlock] {
        var blocks: [SummaryBlock] = []
        for rawLine in text.components(separatedBy: .newlines) {
            if let block = classifyLine(rawLine) {
                blocks.append(block)
            }
        }
        return blocks
    }

    private func classifyLine(_ rawLine: String) -> SummaryBlock? {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return nil }
        if line.hasPrefix("## ") {
            return strippedTitle(from: line, prefixLength: 3)
        }
        if line.hasPrefix("# ") {
            return strippedTitle(from: line, prefixLength: 2)
        }
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            return strippedItem(from: line)
        }
        return .paragraph(line)
    }

    private func strippedTitle(from line: String, prefixLength: Int) -> SummaryBlock? {
        let value = String(line.dropFirst(prefixLength)).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        return .title(value)
    }

    private func strippedItem(from line: String) -> SummaryBlock? {
        let value = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        return .item(value)
    }

    private func inlineFormatted(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }

    private func bulletContainer(@ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppDesignSystem.Layout.spacing8) {
            Text("•")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            content()
        }
    }

    private func bulletRow(_ content: AttributedString) -> some View {
        bulletContainer {
            Text(content)
                .font(.body)
        }
    }

    private var fallbackBadge: some View {
        Text("transcription.summary.fallback_badge".localized)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, AppDesignSystem.Layout.spacing8)
            .padding(.vertical, AppDesignSystem.Layout.spacing2)
            .background(
                AppDesignSystem.Colors.settingsCardBackground.opacity(0.8),
                in: Capsule()
            )
    }
}

#Preview("Meeting summary — structured") {
    MeetingSummaryView(
        canonicalSummary: CanonicalSummary(
            title: "Launch planning",
            summary: "The team aligned on the launch scope and split the remaining work for the week.",
            keyPoints: ["Scope is frozen except critical fixes", "Marketing needs the final copy by Friday"],
            decisions: ["Ship the new onboarding flow first"],
            actionItems: [
                .init(title: "Confirm the release date", owner: "Kara", dueDate: Date(timeIntervalSince1970: 1_762_934_400)),
                .init(title: "Update the rollout checklist", owner: "Ray"),
                .init(title: "Archive last quarter notes", owner: nil)
            ],
            openQuestions: ["Do we need a staged rollout?"]
        ),
        fallbackText: "",
        showsFallbackBadge: false
    )
    .frame(width: 420)
    .padding()
}

#Preview("Meeting summary — markdown fallback") {
    MeetingSummaryView(
        canonicalSummary: nil,
        fallbackText: "## Key Points\n- Shipped the **new** onboarding flow\n- Marketing needs copy with *final* dates\n\nPlain paragraph with **bold** text.",
        showsFallbackBadge: true
    )
    .frame(width: 420)
    .padding()
}
