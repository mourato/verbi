import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Visual component showing transcription service status and progress.
/// Provides real-time feedback on model loading, service connection, and transcription progress.
public struct TranscriptionStatusView: View {
    @ObservedObject var viewModel: TranscriptionViewModel
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(viewModel: TranscriptionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 8) {
            mainStatusRow

            if isExpanded {
                expandedDetails
            }
        }
        .padding(12)
        .background(statusBackground, in: RoundedRectangle(cornerRadius: AppDesignSystem.Layout.cardCornerRadius))
    }

    // MARK: - Main Status Row

    private var mainStatusRow: some View {
        Button(action: toggleExpanded) {
            HStack(spacing: 10) {
                statusIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.statusMessage)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(statusTextColor)

                    if viewModel.isProcessing {
                        progressBar
                    }
                }

                Spacer()

                chevronButton
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("transcription.view.toggle_details".localized)
    }

    // MARK: - Status Icon

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(statusIconBackground)
                .frame(width: 28, height: 28)

            statusIconImage
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(statusIconColor)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusIconImage: some View {
        switch (viewModel.serviceState, viewModel.modelState, viewModel.phase) {
        case (.disconnected, _, _), (.error, _, _):
            Image(systemName: "xmark.circle.fill")
        case (.connecting, _, _):
            ProgressView()
                .controlSize(.small)
        case (.connected, .downloading, _):
            ProgressView()
                .controlSize(.small)
        case (.connected, .loading, _):
            ProgressView()
                .controlSize(.small)
        case (.connected, .error, _):
            Image(systemName: "exclamationmark.triangle.fill")
        case (.connected, .unloaded, _):
            Image(systemName: "circle.dashed")
        case (_, _, .processing), (_, _, .preparing):
            ProgressView()
                .controlSize(.small)
        case (_, _, .completed):
            Image(systemName: "checkmark.circle.fill")
        case (_, _, .failed):
            Image(systemName: "xmark.circle.fill")
        default:
            Image(systemName: "checkmark.circle.fill")
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(AppDesignSystem.Colors.neutral.opacity(0.2))
                        .frame(height: 4)

                    // Progress fill
                    Capsule()
                        .fill(progressGradient)
                        .frame(
                            width: max(
                                0, geometry.size.width * (viewModel.progressPercentage / 100.0)
                            ),
                            height: 4
                        )
                }
            }
            .frame(height: 4)

            if let remaining = viewModel.estimatedTimeRemaining, remaining > 0 {
                Text("transcription.time_remaining".localized(with: formatTime(remaining)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Expanded Details

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            detailRow(label: "transcription.service".localized, value: serviceStateLabel)
            detailRow(label: "transcription.model".localized, value: modelStateLabel)
            detailRow(label: "transcription.device".localized, value: viewModel.device.uppercased())

            if let error = viewModel.lastError {
                errorRow(error: error)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var serviceStateLabel: String {
        switch viewModel.serviceState {
        case .connected: "transcription.state.connected".localized
        case .connecting: "transcription.state.connecting".localized
        case .disconnected: "transcription.state.disconnected".localized
        case .error: "transcription.state.error".localized
        case .unknown: "transcription.state.unknown".localized
        }
    }

    private var modelStateLabel: String {
        switch viewModel.modelState {
        case .loaded: "transcription.model_state.loaded".localized
        case .downloading: "transcription.model_state.downloading".localized
        case .loading: "transcription.model_state.loading".localized
        case .unloaded: "transcription.model_state.unloaded".localized
        case .error: "transcription.model_state.error".localized
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    private func errorRow(error: TranscriptionStatusError) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppDesignSystem.Colors.error)
                .accessibilityHidden(true)

            VStack(alignment: .leading) {
                Text(error.localizedDescription)
                    .foregroundStyle(AppDesignSystem.Colors.error)
                Text("transcription.error.click_retry".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppDesignSystem.Layout.compactInset)
        .background(AppDesignSystem.Colors.error.opacity(0.1), in: RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
    }

    private var chevronButton: some View {
        Image(systemName: "chevron.down")
            .font(.caption)
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .accessibilityHidden(true)
    }

    private func toggleExpanded() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            isExpanded.toggle()
        }
    }

    // MARK: - Styling Computed Properties

    private var statusBackground: some ShapeStyle {
        switch (viewModel.serviceState, viewModel.hasBlockingError) {
        case (_, true):
            AnyShapeStyle(AppDesignSystem.Colors.error.opacity(0.1))
        case (.connected, _) where viewModel.isProcessing:
            AnyShapeStyle(AppDesignSystem.Colors.accent.opacity(0.1))
        case (.connected, _) where viewModel.phase == .completed:
            AnyShapeStyle(AppDesignSystem.Colors.success.opacity(0.1))
        default:
            AnyShapeStyle(.ultraThinMaterial)
        }
    }

    private var statusTextColor: Color {
        if viewModel.hasBlockingError {
            return AppDesignSystem.Colors.error
        } else if viewModel.isProcessing {
            return AppDesignSystem.Colors.accent
        } else if viewModel.phase == .completed {
            return AppDesignSystem.Colors.success
        }
        return .primary
    }

    private var statusIconBackground: Color {
        if viewModel.hasBlockingError {
            return AppDesignSystem.Colors.error.opacity(0.15)
        } else if viewModel.isProcessing {
            return AppDesignSystem.Colors.accent.opacity(0.15)
        } else if viewModel.phase == .completed {
            return AppDesignSystem.Colors.success.opacity(0.15)
        } else if viewModel.isReady {
            return AppDesignSystem.Colors.success.opacity(0.15)
        }
        return AppDesignSystem.Colors.neutral.opacity(0.15)
    }

    private var statusIconColor: Color {
        if viewModel.hasBlockingError {
            return AppDesignSystem.Colors.error
        } else if viewModel.isProcessing {
            return AppDesignSystem.Colors.accent
        } else if viewModel.phase == .completed || viewModel.isReady {
            return AppDesignSystem.Colors.success
        }
        return AppDesignSystem.Colors.neutral
    }

    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: [AppDesignSystem.Colors.accent, AppDesignSystem.Colors.secondaryAccent],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: TimeInterval) -> String {
        TimeFormatter.format(seconds)
    }
}

// MARK: - Compact Status View

/// Smaller status indicator for menu bar or compact displays.
public struct CompactTranscriptionStatusView: View {
    @ObservedObject var viewModel: TranscriptionViewModel

    public init(viewModel: TranscriptionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: 6) {
            statusDot

            Text(compactStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .overlay {
                if viewModel.isProcessing || viewModel.modelState == .loading {
                    Circle()
                        .stroke(dotColor.opacity(0.5), lineWidth: 1)
                        .scaleEffect(1.5)
                        .opacity(viewModel.isProcessing ? 1 : 0)
                }
            }
    }

    private var dotColor: Color {
        if viewModel.hasBlockingError {
            return .red
        } else if viewModel.isProcessing {
            return AppDesignSystem.Colors.accent
        } else if viewModel.isReady {
            return .green
        }
        return .yellow
    }

    private var compactStatusText: String {
        switch (viewModel.serviceState, viewModel.modelState, viewModel.phase) {
        case (.disconnected, _, _), (.error, _, _):
            return "transcription.compact.offline".localized
        case (.connecting, _, _):
            return "transcription.compact.connecting".localized
        case (.connected, .downloading, _):
            return "transcription.compact.downloading_model".localized
        case (.connected, .loading, _):
            return "transcription.compact.loading_model".localized
        case (.connected, .loaded, .idle):
            return "transcription.compact.ready".localized
        case (.connected, .loaded, .processing):
            if viewModel.progressPercentage > 0 {
                return "transcription.compact.transcribing_percent"
                    .localized(with: Int(viewModel.progressPercentage))
            }
            return "transcription.compact.transcribing".localized
        case (.connected, .loaded, .completed):
            return "transcription.compact.completed".localized
        default:
            return "transcription.compact.waiting".localized
        }
    }
}

#Preview("Full Status View") {
    let status = TranscriptionStatus()
    let viewModel = TranscriptionViewModel(status: status)

    VStack(spacing: 20) {
        TranscriptionStatusView(viewModel: viewModel)

        // Simulate different states
        Button("Ready") {
            Task { @MainActor in
                status.updateServiceState(.connected)
                status.updateModelState(.loaded, device: "mps")
                status.resetToIdle()
                // Force update on MainActor if needed, but bindings should handle it
            }
        }

        Button("Processing") {
            Task { @MainActor in
                status.beginTranscription(audioDuration: 120)
                status.updateProgress(phase: .processing, percentage: 45)
            }
        }

        Button("Error") {
            Task { @MainActor in
                status.recordError(.serviceUnavailable)
            }
        }
    }
    .padding()
    .frame(width: 300)
}

#Preview("Compact Status") {
    CompactTranscriptionStatusView(viewModel: TranscriptionViewModel(status: TranscriptionStatus()))
        .padding()
}
