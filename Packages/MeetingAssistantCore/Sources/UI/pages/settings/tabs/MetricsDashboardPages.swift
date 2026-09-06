import Charts
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

struct MetricsDashboardIndexPage: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel
    let openMoreInsights: () -> Void
    let openPerformance: () -> Void
    let openEventDetail: (MeetingCalendarEventSnapshot) -> Void

    var body: some View {
        SettingsFormPage {
            MetricsDashboardActivityHero(
                titleKey: "settings.section.metrics",
                viewModel: viewModel,
            )

            MetricsDashboardLoadErrorSection(
                errorMessage: viewModel.errorMessage,
                onRetry: { await viewModel.load() },
            )
        } content: {
            MetricsDashboardActivityPrimaryContent(viewModel: viewModel)

            Section {
                MetricsDashboardMoreInsightsLinkSection(openMoreInsights: openMoreInsights)
                MetricsDashboardPerformanceLinkSection(openPerformance: openPerformance)
            } header: {
                SettingsFormSectionHeader(title: "settings.activity.explore.title".localized, icon: "chart.line.uptrend.xyaxis")
            }

            if viewModel.isMeetingTranscriptionEnabled {
                Section {
                    MetricsDashboardUpcomingEventFormRows(
                        viewModel: viewModel,
                        onOpenEventDetail: openEventDetail,
                    )
                } header: {
                    SettingsFormSectionHeader(title: "metrics.calendar.upcoming.title".localized, icon: "calendar.badge.clock")
                }
            }
        }
    }
}

struct ActivityDashboardRootPage: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel
    let openMoreInsights: () -> Void
    let openPerformance: () -> Void
    let openEventDetail: (MeetingCalendarEventSnapshot) -> Void

    var body: some View {
        SettingsFormPage {
            MetricsDashboardActivityHero(
                titleKey: "settings.section.activity",
                viewModel: viewModel,
            )

            MetricsDashboardLoadErrorSection(
                errorMessage: viewModel.errorMessage,
                onRetry: { await viewModel.load() },
            )
        } content: {
            MetricsDashboardActivityPrimaryContent(viewModel: viewModel)

            Section {
                SettingsListDrillDownButtonRow(
                    title: "metrics.performance.link.title".localized,
                    subtitle: "settings.activity.model_performance.subtitle".localized,
                    accessibilityHint: "metrics.performance.link.accessibility_hint".localized,
                ) {
                    openPerformance()
                }

                SettingsListDrillDownButtonRow(
                    title: "metrics.more_insights.title".localized,
                    subtitle: "settings.activity.more_insights.subtitle".localized,
                    accessibilityHint: "metrics.more_insights.accessibility_hint".localized,
                ) {
                    openMoreInsights()
                }
            } header: {
                SettingsFormSectionHeader(title: "settings.activity.explore.title".localized, icon: "chart.line.uptrend.xyaxis")
            }

            if viewModel.isMeetingTranscriptionEnabled {
                Section {
                    MetricsDashboardUpcomingEventFormRows(
                        viewModel: viewModel,
                        onOpenEventDetail: openEventDetail,
                    )
                } header: {
                    SettingsFormSectionHeader(title: "metrics.calendar.upcoming.title".localized, icon: "calendar.badge.clock")
                }
            }
        }
    }
}

struct MetricsDashboardMoreInsightsPage: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel

    var body: some View {
        SettingsScrollableContent {
            MetricsDashboardLoadErrorSection(
                errorMessage: viewModel.errorMessage,
                onRetry: { await viewModel.load() },
            )

            MetricsDashboardFiltersSection(viewModel: viewModel)

            if viewModel.summary.sessionsRecorded == 0, !viewModel.isLoading {
                MAEmptyStateView(
                    iconName: "chart.bar.xaxis",
                    title: "metrics.empty.title".localized,
                    message: "metrics.empty.subtitle".localized,
                )
            } else {
                DSGroup("metrics.summary.title".localized, icon: "chart.bar.doc.horizontal") {
                    MetricsDashboardSummarySection(viewModel: viewModel)
                }
                MetricsDashboardAppStartFrequencySection(viewModel: viewModel)
                MetricsDashboardHourlyPeaksSection(viewModel: viewModel)
                MetricsDashboardWeekdayPeaksSection(viewModel: viewModel)
            }
        }
    }
}

struct MetricsDashboardEventDetailPage: View {
    let event: MeetingCalendarEventSnapshot
    @ObservedObject var viewModel: MetricsDashboardViewModel

    @State private var notesDraft: MeetingNotesContent = .empty
    @State private var isAttendeesPopoverPresented = false
    @State private var notesAutosaveTask: Task<Void, Never>?
    @State private var hasLoadedInitialNotes = false

    var body: some View {
        SettingsScrollableContent {
            SettingsSectionHeader(
                title: eventTitle,
                description: "metrics.calendar.detail.subtitle".localized,
            )

            DSGroup("metrics.calendar.detail.metadata.title".localized, icon: "calendar") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        MetricsDashboardFormatters.calendarEventIntervalLabel(
                            startDate: event.startDate,
                            endDate: event.endDate,
                        ),
                        systemImage: "calendar.badge.clock",
                    )
                    .font(.subheadline)

                    if let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
                        Label(location, systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                    }

                    Button {
                        isAttendeesPopoverPresented.toggle()
                    } label: {
                        Label(
                            "metrics.calendar.detail.attendees.count".localized(with: event.attendees.count),
                            systemImage: "person.2",
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popover(isPresented: $isAttendeesPopoverPresented, arrowEdge: .bottom) {
                        attendeesPopoverContent
                    }
                }
            }

            DSGroup("metrics.calendar.detail.notes.title".localized, icon: "note.text") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("metrics.calendar.detail.notes.subtitle".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    MeetingNotesMarkdownEditor(
                        content: $notesDraft,
                        documentId: "calendar-event-notes-\(event.eventIdentifier)",
                    )
                    .frame(minHeight: 280)
                }
            }
        }
        .onAppear {
            loadPersistedNotesIfNeeded()
        }
        .onChange(of: event.eventIdentifier) { _, _ in
            hasLoadedInitialNotes = false
            loadPersistedNotesIfNeeded()
        }
        .onChange(of: notesDraft) { _, _ in
            scheduleNotesAutosave()
        }
        .onDisappear {
            flushNotesAutosave()
        }
    }

    private var eventTitle: String {
        event.trimmedTitle.isEmpty ? "metrics.calendar.event.untitled".localized : event.trimmedTitle
    }

    private var attendeesPopoverContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("metrics.calendar.detail.attendees.title".localized)
                .font(.headline)

            if event.attendees.isEmpty {
                Text("metrics.calendar.detail.attendees.empty".localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(event.attendees.enumerated()), id: \.offset) { _, attendee in
                            Text(attendee)
                                .font(.subheadline)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .settingsScrollEdgeEffect()
                .subtleScrollbars()
                .frame(maxHeight: 220)
            }
        }
        .padding(AppDesignSystem.Layout.cardPadding)
        .frame(width: 320, alignment: .leading)
    }

    private func loadPersistedNotesIfNeeded() {
        guard !hasLoadedInitialNotes else { return }
        hasLoadedInitialNotes = true
        notesDraft = viewModel.calendarEventNotesContent(for: event)
    }

    private func scheduleNotesAutosave() {
        notesAutosaveTask?.cancel()
        let pendingNotes = notesDraft
        notesAutosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                viewModel.updateCalendarEventNotes(pendingNotes, for: event)
            }
        }
    }

    private func flushNotesAutosave() {
        notesAutosaveTask?.cancel()
        notesAutosaveTask = nil
        viewModel.updateCalendarEventNotes(notesDraft, for: event)
    }
}

private struct MetricsDashboardActivityHero: View {
    let titleKey: String
    @ObservedObject var viewModel: MetricsDashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SettingsFormSectionHeader(title: titleKey.localized, icon: "chart.line.uptrend.xyaxis")
            if MetricsDashboardFirstFold.showsHeroMetricsSubtitle(
                isLoading: viewModel.isLoading,
                sessionsRecorded: viewModel.summary.sessionsRecorded,
            ) {
                Text(
                    "metrics.hero.subtitle".localized(
                        with: MetricsDashboardFormatters.formattedNumber(viewModel.summary.wordsDictated),
                        viewModel.summary.sessionsRecorded,
                    ),
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if !viewModel.isLoading, viewModel.summary.sessionsRecorded == 0 {
                Text("metrics.empty.subtitle".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
@ViewBuilder
private func MetricsDashboardActivityPrimaryContent(viewModel: MetricsDashboardViewModel) -> some View {
    Section {
        switch MetricsDashboardFirstFold.content(
            isLoading: viewModel.isLoading,
            sessionsRecorded: viewModel.summary.sessionsRecorded,
        ) {
        case .loading:
            ProgressView()
                .tint(AppDesignSystem.Colors.accent)
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(.vertical, 8)
                .accessibilityLabel(Text("settings.transcriptions.loading".localized))
        case .empty:
            MAEmptyStateView(
                iconName: "chart.bar.xaxis",
                title: "metrics.empty.title".localized,
                message: "metrics.empty.subtitle".localized,
                emphasis: .compact,
            )
        case .summary:
            MetricsDashboardSummarySection(viewModel: viewModel)
        }
    }

    if MetricsDashboardFirstFold.showsTrendSection(
        isLoading: viewModel.isLoading,
        sessionsRecorded: viewModel.summary.sessionsRecorded,
    ) {
        Section {
            Text("metrics.activity.subtitle".localized)
                .font(.caption)
                .foregroundStyle(.secondary)
            MetricsDashboardActivitySection(viewModel: viewModel)
        } header: {
            SettingsFormSectionHeader(title: "metrics.activity.title".localized, icon: "calendar.badge.clock") {
                MetricsDashboardActivityFilterMenu(viewModel: viewModel)
            }
        }
    }
}

private struct MetricsDashboardLoadErrorSection: View {
    let errorMessage: String?
    let onRetry: @MainActor @Sendable () async -> Void

    var body: some View {
        if let errorMessage {
            SettingsStateBlock(
                kind: .warning,
                title: "common.error".localized,
                message: errorMessage,
                actionTitle: "settings.service.verify".localized,
            ) {
                Task {
                    await onRetry()
                }
            }
        }
    }
}

private struct MetricsDashboardMoreInsightsLinkSection: View {
    let openMoreInsights: () -> Void

    var body: some View {
        SettingsDrillDownButtonRow(
            title: "metrics.more_insights.title".localized,
            accessibilityHint: "metrics.more_insights.accessibility_hint".localized,
        ) {
            openMoreInsights()
        }
    }
}

private struct MetricsDashboardPerformanceLinkSection: View {
    let openPerformance: () -> Void

    var body: some View {
        SettingsDrillDownButtonRow(
            title: "metrics.performance.link.title".localized,
            accessibilityHint: "metrics.performance.link.accessibility_hint".localized,
        ) {
            openPerformance()
        }
    }
}

private struct MetricsDashboardFiltersSection: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel

    var body: some View {
        DSGroup("metrics.filters.title".localized, icon: "calendar") {
            HStack {
                Text("metrics.filters.period".localized)
                    .font(.body)

                Spacer()

                MetricsDashboardFilterMenu(
                    selection: $viewModel.dateFilter,
                    options: DateFilter.allCases,
                    displayName: \.displayName,
                )
            }
        }
    }
}

private struct MetricsDashboardSummarySection: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    sessionCard
                    wordsCard
                    wpmCard
                    keystrokesCard
                }
            }
            .frame(maxWidth: .infinity)

            Grid(horizontalSpacing: 16, verticalSpacing: 16) {
                GridRow {
                    sessionCard
                    wordsCard
                }
                GridRow {
                    wpmCard
                    keystrokesCard
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var sessionCard: some View {
        MetricStatCard(
            icon: "mic.fill",
            title: "metrics.summary.sessions_recorded".localized,
            value: MetricsDashboardFormatters.formattedNumber(viewModel.summary.sessionsRecorded),
            detail: "metrics.summary.sessions_recorded_detail".localized,
            tint: .purple,
        )
    }

    private var wordsCard: some View {
        MetricStatCard(
            icon: "text.alignleft",
            title: "metrics.summary.words_dictated".localized,
            value: MetricsDashboardFormatters.formattedNumber(viewModel.summary.wordsDictated),
            detail: "metrics.summary.words_dictated_detail".localized,
            tint: AppDesignSystem.Colors.accent,
        )
    }

    private var wpmCard: some View {
        MetricStatCard(
            icon: "bolt.fill",
            title: "metrics.summary.wpm".localized,
            value: viewModel.summary.wordsPerMinute.formatted(.number.precision(.fractionLength(0))),
            detail: "metrics.summary.wpm_detail".localized,
            tint: .blue,
        )
    }

    private var keystrokesCard: some View {
        MetricStatCard(
            icon: "keyboard",
            title: "metrics.summary.keystrokes".localized,
            value: MetricsDashboardFormatters.formattedNumber(viewModel.summary.keystrokesSaved),
            detail: "metrics.summary.keystrokes_detail".localized,
            tint: .orange,
        )
    }
}

private struct MetricsDashboardHourlyPeaksSection: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel

    var body: some View {
        DSGroup("metrics.peaks.hourly.title".localized, icon: "clock.arrow.circlepath") {
            Chart(viewModel.hourlyBuckets) { bucket in
                BarMark(
                    x: .value("hour", bucket.hour),
                    y: .value("count", bucket.count),
                )
                .foregroundStyle(AppDesignSystem.Colors.accent.gradient)
            }
            .chartXScale(domain: 0...23)
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: AppDesignSystem.Layout.chartHeight)
        }
    }
}

private struct MetricsDashboardAppStartFrequencySection: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel

    private var totalSessions: Int {
        viewModel.appUsageBuckets.reduce(0) { partialResult, bucket in
            partialResult + bucket.sessions
        }
    }

    var body: some View {
        DSGroup("metrics.apps.frequency.title".localized, icon: "app.badge") {
            VStack(alignment: .leading, spacing: 12) {
                Text("metrics.apps.frequency.subtitle".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.appUsageBuckets.isEmpty {
                    MAEmptyStateView(
                        iconName: "chart.pie",
                        title: "metrics.empty.title".localized,
                        message: "metrics.empty.subtitle".localized,
                        emphasis: .compact,
                    )
                } else {
                    ZStack {
                        Chart(viewModel.appUsageBuckets) { bucket in
                            SectorMark(
                                angle: .value("count", bucket.sessions),
                                innerRadius: .ratio(0.62),
                                angularInset: 2,
                            )
                            .foregroundStyle(color(for: bucket))
                        }
                        .chartLegend(.hidden)

                        VStack(spacing: 4) {
                            Text(MetricsDashboardFormatters.formattedNumber(totalSessions))
                                .font(.title3.weight(.semibold))
                            Text("metrics.apps.frequency.total".localized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: max(AppDesignSystem.Layout.chartHeight, 220))

                    VStack(spacing: 8) {
                        ForEach(viewModel.appUsageBuckets) { bucket in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(color(for: bucket))
                                    .frame(width: 10, height: 10)

                                Text(bucket.appName)
                                    .font(.caption)
                                    .lineLimit(1)

                                Spacer(minLength: 12)

                                Text(MetricsDashboardFormatters.formattedNumber(bucket.sessions))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)

                                Text(percentText(for: bucket.sessions))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 42, alignment: .trailing)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private func percentText(for sessions: Int) -> String {
        guard totalSessions > 0 else { return "0%" }
        let ratio = Double(sessions) / Double(totalSessions)
        return ratio.formatted(.percent.precision(.fractionLength(0)))
    }

    private func color(for bucket: MetricsAppUsageBucket) -> Color {
        if bucket.isOther {
            return AppDesignSystem.Colors.subtleFill
        }

        let app = MeetingApp(rawValue: bucket.appRawValue) ?? .unknown
        return app.color
    }
}

private struct MetricsDashboardWeekdayPeaksSection: View {
    @ObservedObject var viewModel: MetricsDashboardViewModel

    var body: some View {
        DSGroup("metrics.peaks.weekday.title".localized, icon: "chart.bar.xaxis") {
            Chart(viewModel.weekdayBuckets) { bucket in
                BarMark(
                    x: .value("weekday", weekdayLabel(for: bucket.weekday)),
                    y: .value("words", bucket.words),
                )
                .foregroundStyle(AppDesignSystem.Colors.accent.gradient)
                .clipShape(.rect(cornerRadius: AppDesignSystem.Layout.tinyCornerRadius))
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: AppDesignSystem.Layout.chartHeight)
        }
    }

    private func weekdayLabel(for weekday: Int) -> String {
        let symbols = Self.weekdaySymbols
        guard weekday >= 1, weekday <= symbols.count else { return "\(weekday)" }
        return symbols[weekday - 1]
    }

    private static let weekdaySymbols: [String] = DateFormatter().shortWeekdaySymbols
}

#Preview("Dashboard More Insights") {
    MetricsDashboardMoreInsightsPage(viewModel: MetricsDashboardViewModel())
        .frame(width: 720, height: 780)
}
