import Combine
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import SwiftUI

@MainActor
@ViewBuilder
func MetricsDashboardUpcomingEventFormRows(
    viewModel: MetricsDashboardViewModel,
    onOpenEventDetail: @escaping (MeetingCalendarEventSnapshot) -> Void,
) -> some View {
    Text("metrics.calendar.upcoming.subtitle".localized)
        .font(.caption)
        .foregroundStyle(.secondary)

    if viewModel.isLoadingCalendar {
        SettingsStateBlock(
            kind: .loading,
            title: "metrics.calendar.loading.title".localized,
            message: "metrics.calendar.loading.message".localized,
        )
    } else if !viewModel.calendarPermissionState.isAuthorized {
        SettingsStateBlock(
            kind: .warning,
            title: "metrics.calendar.permission.title".localized,
            message: upcomingEventsCalendarPermissionMessage(viewModel.calendarPermissionState),
            actionTitle: upcomingEventsCalendarPermissionActionTitle(viewModel.calendarPermissionState),
        ) {
            if viewModel.calendarPermissionState == .notDetermined {
                Task { await viewModel.requestCalendarAccess() }
            } else {
                viewModel.openCalendarSettings()
            }
        }
    } else if viewModel.upcomingEvents.isEmpty {
        MAEmptyStateView(
            iconName: "calendar.badge.exclamationmark",
            title: "metrics.calendar.empty.title".localized,
            message: "metrics.calendar.empty.message".localized,
            emphasis: .compact,
        )
    } else {
        ForEach(viewModel.upcomingEvents, id: \.eventIdentifier) { event in
            UpcomingCalendarEventRow(
                event: event,
                isRecording: viewModel.isRecording,
                isLinked: viewModel.isLinkedEvent(event),
                onOpen: {
                    onOpenEventDetail(event)
                },
                onLink: {
                    viewModel.linkCalendarEvent(event)
                },
                onClear: {
                    viewModel.clearLinkedCalendarEvent()
                },
                onIgnore: {
                    viewModel.ignoreUpcomingEvent(event)
                },
            )
        }
    }
}

private func upcomingEventsCalendarPermissionMessage(_ state: PermissionState) -> String {
    switch state {
    case .notDetermined:
        "metrics.calendar.permission.request".localized
    case .denied, .restricted:
        "metrics.calendar.permission.denied".localized
    case .granted:
        ""
    }
}

private func upcomingEventsCalendarPermissionActionTitle(_ state: PermissionState) -> String {
    state == .notDetermined
        ? "metrics.calendar.permission.action_request".localized
        : "metrics.calendar.permission.action_open_settings".localized
}

struct MetricsDashboardActivitySection: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
                    .tint(AppDesignSystem.Colors.accent)
                    .frame(maxWidth: .infinity, minHeight: ActivityHeatmap.scrollHeight)
                    .padding(.vertical, ActivityHeatmap.verticalPadding)
            } else if viewModel.dailyBuckets.isEmpty {
                MAEmptyStateView(
                    iconName: "chart.bar.xaxis",
                    title: "metrics.empty.title".localized,
                    message: "metrics.empty.subtitle".localized,
                    emphasis: .compact,
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    heatmapGrid
                    heatmapLegend
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var heatmapGrid: some View {
        HStack(alignment: .top, spacing: ActivityHeatmap.weekdayToGridSpacing) {
            weekdayLegendColumn

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ActivityHeatmap.monthToGridSpacing) {
                        monthHeaderRow

                        HStack(alignment: .top, spacing: ActivityHeatmap.spacing) {
                            ForEach(heatmapWeekColumns) { column in
                                VStack(spacing: ActivityHeatmap.spacing) {
                                    ForEach(Array(column.days.enumerated()), id: \.offset) { _, bucket in
                                        if let bucket {
                                            activitySquare(for: bucket)
                                        } else {
                                            heatmapPlaceholder
                                        }
                                    }
                                }
                                .id("\(ActivityHeatmap.weekColumnPrefix)-\(column.id)")
                            }
                            Color.clear
                                .frame(width: 1, height: 1)
                                .id(ActivityHeatmap.latestAnchorID)
                        }
                    }
                    .padding(.vertical, ActivityHeatmap.verticalPadding)
                }
                .frame(maxWidth: .infinity)
                .frame(height: ActivityHeatmap.scrollHeight)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onAppear {
                    scrollToLatest(in: proxy, animated: true)
                }
                .onReceive(viewModel.$dailyBuckets.dropFirst()) { _ in
                    scrollToLatest(in: proxy, animated: false)
                }
            }
        }
    }

    private var heatmapWeekColumns: [ActivityHeatmapWeekColumn] {
        ActivityHeatmap.makeWeekColumns(from: viewModel.dailyBuckets)
    }

    private var orderedWeekdayNumbers: [Int] {
        let firstWeekday = Calendar.current.firstWeekday
        guard (1...7).contains(firstWeekday) else {
            return Array(1...7)
        }

        return (0..<7).map { offset in
            ((firstWeekday - 1 + offset) % 7) + 1
        }
    }

    private func weekdayLegendText(for weekdayNumber: Int) -> String {
        let visibleWeekdays: Set = [2, 4, 6]
        guard visibleWeekdays.contains(weekdayNumber) else {
            return ""
        }

        let symbols = Self.weekdaySymbols
        guard weekdayNumber >= 1, weekdayNumber <= symbols.count else {
            return ""
        }

        return symbols[weekdayNumber - 1]
    }

    private var weekdayLegendColumn: some View {
        VStack(alignment: .trailing, spacing: ActivityHeatmap.spacing) {
            Spacer()
                .frame(height: ActivityHeatmap.monthHeaderHeight + ActivityHeatmap.monthToGridSpacing)

            ForEach(orderedWeekdayNumbers, id: \.self) { weekdayNumber in
                Text(weekdayLegendText(for: weekdayNumber))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .frame(height: ActivityHeatmap.squareSize)
            }
        }
        .frame(width: ActivityHeatmap.weekdayLabelWidth, alignment: .trailing)
    }

    private var monthHeaderRow: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: max(heatmapGridWidth, 1), height: ActivityHeatmap.monthHeaderHeight)

            ForEach(monthMarkers) { marker in
                Text(marker.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: marker.xOffset)
            }
        }
        .frame(height: ActivityHeatmap.monthHeaderHeight, alignment: .bottomLeading)
    }

    private var monthMarkers: [ActivityHeatmapMonthMarker] {
        ActivityHeatmap.makeMonthMarkers(from: heatmapWeekColumns)
    }

    private var heatmapGridWidth: CGFloat {
        ActivityHeatmap.gridWidth(columnCount: heatmapWeekColumns.count)
    }

    private var maxDailyWords: Int {
        viewModel.dailyBuckets.map(\.words).max() ?? 0
    }

    private func activitySquare(for bucket: MetricsDailyBucket) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(ActivityHeatmap.baseColor)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(heatmapColor(for: bucket.words))
        }
        .frame(width: ActivityHeatmap.squareSize, height: ActivityHeatmap.squareSize)
        .overlay(
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .stroke(
                    bucket.words > 0 && bucket.words == maxDailyWords
                        ? AppDesignSystem.Colors.accent
                        : Color.secondary.opacity(0.2),
                    lineWidth: bucket.words > 0 && bucket.words == maxDailyWords ? 1 : 0.5,
                ),
        )
        .help(heatmapTooltip(for: bucket))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(heatmapTooltip(for: bucket)))
    }

    private var heatmapLegend: some View {
        HStack(spacing: ActivityHeatmap.legendSpacing) {
            legendItem(
                color: AppDesignSystem.Colors.accent.opacity(0),
                label: "metrics.activity.legend.none".localized,
            )
            legendItem(
                color: AppDesignSystem.Colors.accent,
                label: "metrics.activity.legend.most".localized,
            )
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: ActivityHeatmap.legendSwatchCornerRadius, style: .continuous)
                .fill(color)
                .frame(width: ActivityHeatmap.legendSwatchSize, height: ActivityHeatmap.legendSwatchSize)
                .overlay(
                    RoundedRectangle(cornerRadius: ActivityHeatmap.legendSwatchCornerRadius, style: .continuous)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1),
                )
            Text(label)
        }
    }

    private func heatmapColor(for words: Int) -> Color {
        guard maxDailyWords > 0 else {
            return AppDesignSystem.Colors.accent.opacity(0)
        }

        let normalized = max(0, min(1, Double(words) / Double(maxDailyWords)))
        return AppDesignSystem.Colors.accent.opacity(normalized)
    }

    private func heatmapTooltip(for bucket: MetricsDailyBucket) -> String {
        let dayText = Self.activityDateFormatter.string(from: bucket.date)
        let wordsText = MetricsDashboardFormatters.formattedNumber(bucket.words)
        return "metrics.activity.tooltip.words_on_date".localized(with: wordsText, dayText)
    }

    private func scrollToLatest(in proxy: ScrollViewProxy, animated: Bool) {
        DispatchQueue.main.async {
            if animated, !reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(ActivityHeatmap.latestAnchorID, anchor: .trailing)
                }
            } else {
                proxy.scrollTo(ActivityHeatmap.latestAnchorID, anchor: .trailing)
            }
        }
    }

    private var heatmapPlaceholder: some View {
        RoundedRectangle(cornerRadius: AppDesignSystem.Layout.tinyCornerRadius, style: .continuous)
            .fill(Color.clear)
            .frame(width: ActivityHeatmap.squareSize, height: ActivityHeatmap.squareSize)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private static let weekdaySymbols: [String] = DateFormatter().shortWeekdaySymbols

    private static let activityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter
    }()
}

struct MetricsDashboardActivityFilterMenu: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel

    var body: some View {
        SettingsContextMenuButton(accessibilityLabel: "metrics.activity.filter.title".localized) {
            Toggle(isOn: $viewModel.showDictations) {
                Text("metrics.activity.filter.dictations".localized)
            }
            Toggle(isOn: $viewModel.showMeetings) {
                Text("metrics.activity.filter.meetings".localized)
            }
        }
    }
}

private struct UpcomingCalendarEventRow: View {
    let event: MeetingCalendarEventSnapshot
    let isRecording: Bool
    let isLinked: Bool
    let onOpen: () -> Void
    let onLink: () -> Void
    let onClear: () -> Void
    let onIgnore: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(event.trimmedTitle.isEmpty ? "metrics.calendar.event.untitled".localized : event.trimmedTitle)
                    .font(.subheadline.weight(.semibold))

                Text(timeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("metrics.calendar.event.open_detail.accessibility".localized, action: onOpen)
                    .buttonStyle(.link)
                    .font(.caption)
            }

            Spacer(minLength: 0)

            if isLinked {
                VStack(alignment: .trailing, spacing: 8) {
                    Label("metrics.calendar.event.linked".localized, systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppDesignSystem.Colors.success)

                    if isRecording {
                        Button("metrics.calendar.event.clear".localized) {
                            onClear()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Button("metrics.calendar.event.ignore".localized, role: .destructive) {
                        onIgnore()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if isRecording {
                VStack(alignment: .trailing, spacing: 8) {
                    Button("metrics.calendar.event.use_for_recording".localized) {
                        onLink()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("metrics.calendar.event.ignore".localized, role: .destructive) {
                        onIgnore()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                Button("metrics.calendar.event.ignore".localized, role: .destructive) {
                    onIgnore()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timeLabel: String {
        MetricsDashboardFormatters.calendarEventIntervalLabel(
            startDate: event.startDate,
            endDate: event.endDate,
        )
    }
}

/// Flat metric cell for Activity summary grids.
///
/// Lives inside one owning surface (`Form`/`Section` or a single `DSGroup`).
/// Do not wrap this in `DSCard` — nested plates compete with Settings materials.
struct MetricStatCard: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius, style: .continuous)
                        .fill(tint.opacity(0.12)),
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.title3.weight(.semibold))
                    .contentTransition(.numericText())

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Dashboard Activity") {
    Form {
        Section {
            Text("Last 365 days")
                .font(.caption)
                .foregroundStyle(.secondary)
            MetricsDashboardActivitySection(viewModel: MetricsDashboardViewModel())
        } header: {
            SettingsFormSectionHeader(title: "Transcription Activity", icon: "calendar.badge.clock")
        }
    }
    .formStyle(.grouped)
    .padding()
    .frame(width: 720)
}
