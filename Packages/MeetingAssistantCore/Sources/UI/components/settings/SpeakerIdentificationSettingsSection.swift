import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct SpeakerIdentificationSettingsSection: View {
    @ObservedObject private var settings: AppSettingsStore
    @ObservedObject private var modelManager: FluidAIModelManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        settings: AppSettingsStore = .shared,
        modelManager: FluidAIModelManager = .shared,
    ) {
        self.settings = settings
        self.modelManager = modelManager
    }

    public var body: some View {
        Toggle(isOn: $settings.isDiarizationEnabled) {
            VStack(alignment: .leading) {
                Text("settings.ai.diarization".localized)
                Text("settings.ai.diarization_desc".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .onChange(of: settings.isDiarizationEnabled) { isEnabled, _ in
            guard isEnabled else { return }
            settings.minSpeakers = nil
            settings.maxSpeakers = nil
            settings.numSpeakers = nil
            guard FeatureFlags.enableDiarization else { return }
            Task {
                await modelManager.loadDiarizationModels()
            }
        }

        diarizationModelRow

        if settings.isDiarizationEnabled {
            modelStatusSection
        }
    }

    private var diarizationModelRow: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("settings.service.diarization_model_name".localized)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("settings.models.meeting_transcription.diarization_description".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(
                    modelManager.isDiarizationLoaded
                        ? "settings.service.installed".localized
                        : "settings.service.not_installed".localized,
                )
                .font(.caption2)
                .foregroundStyle(modelManager.isDiarizationLoaded ? AppDesignSystem.Colors.success : .secondary)
            }

            Spacer()

            if modelManager.isDiarizationLoaded {
                Button(role: .destructive) {
                    modelManager.deleteDiarizationModels()
                } label: {
                    Label("settings.models.local_models.remove".localized, systemImage: "trash")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task {
                        await modelManager.loadDiarizationModels()
                    }
                } label: {
                    Label("settings.models.local_models.download".localized, systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Model Status

    @ViewBuilder
    private var modelStatusSection: some View {
        let phase = modelManager.downloadPhase

        // Only show when there's activity or an error
        if phase.isInProgress || phase == .ready || modelManager.lastError != nil {
            VStack(alignment: .leading, spacing: AppDesignSystem.Layout.itemSpacing) {
                HStack(spacing: 12) {
                    phaseIcon(for: phase)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(phase.localizedDescription)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        if phase.isInProgress {
                            Text("settings.ai.please_wait".localized)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if phase.isInProgress {
                        ProgressView()
                            .controlSize(.small)
                    } else if case .failed = phase {
                        Button {
                            Task {
                                await modelManager.retryFailedModels()
                            }
                        } label: {
                            Text("settings.ai.retry".localized)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if phase == .ready {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppDesignSystem.Colors.success)
                            .accessibilityLabel("settings.ai.ready".localized)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func phaseIcon(for phase: FluidAIModelManager.DownloadPhase) -> some View {
        switch phase {
        case .idle:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
                .accessibilityLabel("settings.ai.phase_idle".localized)
        case .downloadingASR, .downloadingDiarization:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(AppDesignSystem.Colors.accent)
                .settingsPulseSymbolEffect(isActive: true, reduceMotion: reduceMotion)
                .accessibilityLabel("settings.ai.downloading".localized)
        case .loadingASR, .loadingDiarization:
            Image(systemName: "gearshape.circle.fill")
                .foregroundStyle(AppDesignSystem.Colors.warning)
                .settingsPulseSymbolEffect(isActive: true, reduceMotion: reduceMotion)
                .accessibilityLabel("settings.ai.loading".localized)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppDesignSystem.Colors.success)
                .accessibilityLabel("settings.ai.ready".localized)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppDesignSystem.Colors.error)
                .accessibilityLabel("settings.ai.failed".localized)
        }
    }
}

private struct SpeakerIdentificationPreview: View {
    private let settings: AppSettingsStore

    init() {
        let settings = AppSettingsStore.shared
        settings.isDiarizationEnabled = true
        settings.numSpeakers = nil
        settings.minSpeakers = nil
        settings.maxSpeakers = nil
        self.settings = settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SpeakerIdentificationSettingsSection(settings: settings, modelManager: .shared)
        }
        .padding()
        .frame(width: 760)
    }
}

#Preview("Speaker Identification Settings") {
    SpeakerIdentificationPreview()
}
