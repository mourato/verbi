import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import SwiftUI

// preview-check: ignore — performance pages are composed by the dashboard route previews.

struct MetricsDashboardPerformanceWorkspace: View {
    @ObservedObject var viewModel: MetricsDashboardPerformanceViewModel
    let openRecording: (UUID) -> Void

    var body: some View {
        stageSection

        if viewModel.analysis.summary.totalAttempts == 0, !viewModel.isLoading {
            MAEmptyStateView(
                iconName: "gauge.open.with.lines.needle.33percent",
                title: "metrics.performance.empty.title".localized,
                message: "metrics.performance.empty.subtitle".localized
            )
        } else {
            MetricsDashboardPerformanceSummaryStrip(analysis: viewModel.analysis)
            filtersSection
            PerformanceLeaderboardSection(
                stage: viewModel.stage,
                sort: $viewModel.leaderboardSort,
                entries: viewModel.sortedLeaderboard
            )
            PerformanceHistorySection(
                stage: viewModel.stage,
                attempts: viewModel.history,
                openRecording: openRecording
            )
        }
    }

    private var stageSection: some View {
        DSGroup("metrics.performance.stage.title".localized, icon: "square.3.layers.3d.top.filled") {
            Picker("", selection: $viewModel.stage) {
                ForEach(ModelPerformanceStage.allCases, id: \.self) { stage in
                    Text(stage.displayName).tag(stage)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var filtersSection: some View {
        DSGroup("metrics.performance.filters.title".localized, icon: "line.3.horizontal.decrease.circle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    MetricsDashboardFilterPicker(
                        title: "metrics.performance.filters.capture".localized,
                        selection: $viewModel.captureFilter,
                        options: PerformanceFilter.allCases,
                        displayName: \.displayName
                    )

                    MetricsDashboardFilterPicker(
                        title: "metrics.performance.filters.date".localized,
                        selection: $viewModel.dateFilter,
                        options: DateFilter.allCases,
                        displayName: \.displayName
                    )
                }

                HStack(spacing: 12) {
                    MetricsDashboardFilterPicker(
                        title: "metrics.performance.filters.provider".localized,
                        selection: $viewModel.providerID,
                        options: [String?.none] + viewModel.providerOptions.map { Optional($0.id) },
                        displayName: providerDisplayName
                    )

                    MetricsDashboardFilterPicker(
                        title: "metrics.performance.filters.status".localized,
                        selection: $viewModel.statusFilter,
                        options: ModelPerformanceStatusFilter.allCases,
                        displayName: \.displayName
                    )
                }
            }
        }
    }

    private func providerDisplayName(_ providerID: String?) -> String {
        guard let providerID else {
            return "metrics.performance.filters.provider.all".localized
        }

        return viewModel.providerOptions.first { $0.id == providerID }?.displayName ?? providerID
    }
}

private struct MetricsDashboardPerformanceSummaryStrip: View {
    let analysis: ModelPerformanceAnalysis

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                attemptsCard
                successCard
                modelsCard
                fastestCard
            }

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    attemptsCard
                    successCard
                }
                HStack(spacing: 12) {
                    modelsCard
                    fastestCard
                }
            }
        }
    }

    private var attemptsCard: some View {
        MetricsDashboardPerformanceStatCard(
            icon: "clock.badge.checkmark",
            value: "\(analysis.summary.totalAttempts)",
            label: "metrics.performance.summary.attempts".localized,
            detail: "\(analysis.summary.failedAttempts) " + "metrics.performance.summary.failures".localized,
            tint: .indigo
        )
    }

    private var successCard: some View {
        MetricsDashboardPerformanceStatCard(
            icon: "checkmark.seal.fill",
            value: ModelPerformanceFormatting.percent(
                analysis.summary.totalAttempts == 0
                    ? 0
                    : Double(analysis.summary.successfulAttempts) / Double(analysis.summary.totalAttempts)
            ),
            label: "metrics.performance.summary.success_rate".localized,
            detail: "\(analysis.summary.successfulAttempts)/\(analysis.summary.totalAttempts)",
            tint: .green
        )
    }

    private var modelsCard: some View {
        MetricsDashboardPerformanceStatCard(
            icon: "square.stack.3d.up.fill",
            value: "\(analysis.summary.distinctModels)",
            label: "metrics.performance.summary.models".localized,
            detail: analysis.stage.displayName,
            tint: .orange
        )
    }

    private var fastestCard: some View {
        MetricsDashboardPerformanceStatCard(
            icon: "hare.fill",
            value: ModelPerformanceFormatting.throughput(
                analysis.summary.fastestModelThroughput,
                stage: analysis.stage
            ),
            label: "metrics.performance.summary.fastest".localized,
            detail: analysis.summary.fastestModelDisplayName ?? "metrics.performance.summary.none".localized,
            tint: .mint
        )
    }
}

private struct MetricsDashboardPerformanceStatCard: View {
    let icon: String
    let value: String
    let label: String
    let detail: String
    let tint: Color

    var body: some View {
        DSCard(style: .settings) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tint)

                Text(value)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PerformanceLeaderboardSection: View {
    let stage: ModelPerformanceStage
    @Binding var sort: LeaderboardSort
    let entries: [ModelPerformanceLeaderboardEntry]

    var body: some View {
        DSGroup("metrics.performance.leaderboard.title".localized, icon: "list.number") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("metrics.performance.leaderboard.subtitle".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    MetricsDashboardFilterMenu(
                        selection: $sort,
                        options: LeaderboardSort.allCases,
                        displayName: \.displayName
                    )
                }

                if entries.isEmpty {
                    Text("metrics.performance.leaderboard.empty".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        header

                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            Divider()
                            PerformanceLeaderboardRow(
                                rank: index + 1,
                                stage: stage,
                                entry: entry
                            )
                        }
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("metrics.performance.leaderboard.header.model".localized)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            Text("metrics.performance.leaderboard.header.speed".localized)
                .frame(minWidth: 90, idealWidth: 120, alignment: .trailing)
            Text("metrics.performance.leaderboard.header.latency".localized)
                .frame(minWidth: 75, idealWidth: 96, alignment: .trailing)
            Text("metrics.performance.leaderboard.header.attempts".localized)
                .frame(minWidth: 60, idealWidth: 80, alignment: .trailing)
            Text("metrics.performance.leaderboard.header.success".localized)
                .frame(minWidth: 75, idealWidth: 96, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct PerformanceLeaderboardRow: View {
    let rank: Int
    let stage: ModelPerformanceStage
    let entry: ModelPerformanceLeaderboardEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("#\(rank)")
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(entry.identity.modelDisplayName)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)

                        if entry.isBestBalance {
                            Text("metrics.performance.badge.best_balance".localized)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.green.opacity(0.14), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }

                    Text(
                        "\(entry.identity.providerDisplayName) • \(entry.identity.runtimeKind.displayName)"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ModelPerformanceFormatting.throughput(entry.normalizedThroughput, stage: stage))
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                Text(ModelPerformanceFormatting.secondaryThroughput(entry.secondaryThroughput, stage: stage))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 90, idealWidth: 120, alignment: .trailing)

            Text(ModelPerformanceFormatting.duration(entry.medianWallClockSeconds))
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .frame(minWidth: 75, idealWidth: 96, alignment: .trailing)

            Text("\(entry.attemptCount)")
                .font(.system(.body, design: .monospaced, weight: .semibold))
                .frame(minWidth: 60, idealWidth: 80, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 2) {
                Text(ModelPerformanceFormatting.percent(entry.successRate))
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                Text("\(entry.failedAttempts) " + "metrics.performance.summary.failures".localized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 75, idealWidth: 96, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct PerformanceHistorySection: View {
    let stage: ModelPerformanceStage
    let attempts: [ModelPerformanceAttempt]
    let openRecording: (UUID) -> Void

    var body: some View {
        DSGroup("metrics.performance.history.title".localized, icon: "clock.arrow.trianglehead.counterclockwise.rotate.90") {
            VStack(alignment: .leading, spacing: 12) {
                Text("metrics.performance.history.subtitle".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if attempts.isEmpty {
                    Text("metrics.performance.history.empty".localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(attempts) { attempt in
                            MetricsDashboardPerformanceHistoryRow(
                                stage: stage,
                                attempt: attempt,
                                openRecording: openRecording
                            )

                            if attempt.id != attempts.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MetricsDashboardPerformanceHistoryRow: View {
    let stage: ModelPerformanceStage
    let attempt: ModelPerformanceAttempt
    let openRecording: (UUID) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ModelPerformanceFormatting.dateTime(attempt.startedAt))
                    .font(.system(.body, design: .monospaced, weight: .medium))

                Text(attempt.attemptKind.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 160, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(attempt.modelIdentity.modelDisplayName)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)

                Text("\(attempt.modelIdentity.providerDisplayName) • \(attempt.modelIdentity.runtimeKind.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let failureReason = attempt.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !failureReason.isEmpty
                {
                    Text(failureReason)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 4) {
                Text(ModelPerformanceFormatting.duration(attempt.wallClockSeconds))
                    .font(.system(.body, design: .monospaced, weight: .semibold))

                Text(ModelPerformanceFormatting.attemptInput(attempt, stage: stage))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(attempt.status.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(attempt.status == .succeeded ? .green : .red)
            }
            .frame(width: 160, alignment: .trailing)

            Button("metrics.performance.history.open_recording".localized) {
                openRecording(attempt.transcriptionID)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct MetricsDashboardFilterPicker<SelectionValue: Hashable>: View {
    let title: String
    @Binding var selection: SelectionValue
    let options: [SelectionValue]
    let displayName: (SelectionValue) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            MetricsDashboardFilterMenu(
                selection: $selection,
                options: options,
                maxWidth: .infinity,
                alignment: .leading,
                displayName: displayName
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ModelPerformanceFormatting {
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value * 100.0)
    }

    static func duration(_ seconds: Double) -> String {
        MetricsDashboardFormatters.duration(seconds)
    }

    static func throughput(_ value: Double, stage: ModelPerformanceStage) -> String {
        guard value > 0 else { return "metrics.performance.summary.none".localized }
        switch stage {
        case .transcription:
            return String(format: "%.2fx", value)
        case .postProcessing:
            return bytesPerSecond(value)
        }
    }

    static func secondaryThroughput(_ value: Double, stage: ModelPerformanceStage) -> String {
        guard value > 0 else { return "metrics.performance.summary.none".localized }
        switch stage {
        case .transcription:
            return String(format: "%.2f %@", value, "metrics.performance.units.audio_minutes_per_minute".localized)
        case .postProcessing:
            return String(format: "%.0f %@", value, "metrics.performance.units.characters_per_second".localized)
        }
    }

    static func attemptInput(_ attempt: ModelPerformanceAttempt, stage: ModelPerformanceStage) -> String {
        switch stage {
        case .transcription:
            guard attempt.audioSeconds > 0 else { return "metrics.performance.summary.none".localized }
            return duration(attempt.audioSeconds)
        case .postProcessing:
            guard attempt.inputUTF8Bytes > 0 else { return "metrics.performance.summary.none".localized }
            return bytesCount(attempt.inputUTF8Bytes)
        }
    }

    static func dateTime(_ date: Date) -> String {
        MetricsDashboardFormatters.formattedDate(date)
    }

    private static func bytesPerSecond(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_000_000 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_000_000)
        }
        if bytesPerSecond >= 1000 {
            return String(format: "%.1f KB/s", bytesPerSecond / 1000)
        }
        return String(format: "%.0f B/s", bytesPerSecond)
    }

    private static func bytesCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct MetricsDashboardPerformancePage: View {
    @StateObject private var viewModel: MetricsDashboardPerformanceViewModel
    let openRecording: (UUID) -> Void

    init(
        storage: StorageService = FileSystemStorageService.shared,
        openRecording: @escaping (UUID) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: MetricsDashboardPerformanceViewModel(storage: storage))
        self.openRecording = openRecording
    }

    var body: some View {
        SettingsScrollableContent {
            SettingsSectionHeader(
                title: "metrics.performance.title".localized,
                description: "metrics.performance.subtitle".localized
            )

            if let errorMessage = viewModel.errorMessage {
                SettingsStateBlock(kind: .warning, title: "common.error".localized, message: errorMessage) {
                    Task {
                        await viewModel.load()
                    }
                }
            }

            if viewModel.isLoading, viewModel.analysis.summary.totalAttempts == 0 {
                ProgressView()
                    .tint(AppDesignSystem.Colors.accent)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                MetricsDashboardPerformanceWorkspace(
                    viewModel: viewModel,
                    openRecording: openRecording
                )
            }
        }
        .task {
            await viewModel.load()
        }
    }
}

struct MetricsDashboardPerformanceRecordingPage: View {
    let recordingID: UUID

    @State private var transcription: Transcription?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let storage: StorageService

    init(
        recordingID: UUID,
        storage: StorageService = FileSystemStorageService.shared
    ) {
        self.recordingID = recordingID
        self.storage = storage
    }

    var body: some View {
        SettingsScrollableContent {
            SettingsSectionHeader(
                title: transcription?.meeting.preferredTitle ?? "metrics.performance.recording.title".localized,
                description: "metrics.performance.recording.subtitle".localized
            )

            if let errorMessage {
                SettingsStateBlock(kind: .warning, title: "common.error".localized, message: errorMessage) {
                    Task {
                        await loadRecording()
                    }
                }
            }

            if isLoading {
                ProgressView()
                    .tint(AppDesignSystem.Colors.accent)
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else if let transcription {
                recordingSnapshotSection(transcription)
                transcriptPreviewSection(transcription)
            } else {
                MAEmptyStateView(
                    iconName: "doc.text.magnifyingglass",
                    title: "metrics.performance.recording.empty.title".localized,
                    message: "metrics.performance.recording.empty.subtitle".localized
                )
            }
        }
        .task(id: recordingID) {
            await loadRecording()
        }
    }

    private func recordingSnapshotSection(_ transcription: Transcription) -> some View {
        DSGroup("metrics.performance.recording.snapshot".localized, icon: "doc.text") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    recordingMetric(
                        title: "metrics.performance.recording.capture".localized,
                        value: transcription.capturePurpose.displayName
                    )
                    recordingMetric(
                        title: "metrics.performance.recording.source".localized,
                        value: transcription.meeting.appName
                    )
                }

                GridRow {
                    recordingMetric(
                        title: "metrics.performance.recording.transcription_model".localized,
                        value: transcription.modelName
                    )
                    recordingMetric(
                        title: "metrics.performance.recording.transcription_time".localized,
                        value: MetricsDashboardFormatters.duration(transcription.transcriptionDuration)
                    )
                }

                GridRow {
                    recordingMetric(
                        title: "metrics.performance.recording.post_processing_model".localized,
                        value: transcription.postProcessingModel ?? "metrics.performance.summary.none".localized
                    )
                    recordingMetric(
                        title: "metrics.performance.recording.post_processing_time".localized,
                        value: MetricsDashboardFormatters.duration(transcription.postProcessingDuration)
                    )
                }

                GridRow {
                    recordingMetric(
                        title: "metrics.performance.recording.recorded_at".localized,
                        value: MetricsDashboardFormatters.formattedDate(transcription.createdAt)
                    )
                    recordingMetric(
                        title: "metrics.performance.recording.input_source".localized,
                        value: transcription.inputSource ?? "metrics.performance.summary.none".localized
                    )
                }
            }

            let rawFailureReason = transcription.transcriptionFailureReason
                ?? transcription.postProcessingFailureReason
            let failureReason = rawFailureReason?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !failureReason.isEmpty {
                Divider()
                Text(failureReason)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func transcriptPreviewSection(_ transcription: Transcription) -> some View {
        DSGroup("metrics.performance.recording.preview".localized, icon: "text.alignleft") {
            Text(transcription.processedContent ?? transcription.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recordingMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func loadRecording() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            transcription = try await storage.loadTranscription(by: recordingID)
        } catch {
            transcription = nil
            errorMessage = "metrics.error.load".localized
        }
    }
}
