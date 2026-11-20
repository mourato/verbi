import SwiftUI
import VerbiCoreAI

public struct OnboardingDownloadModelsView: View {
    @ObservedObject var modelManager: FluidAIModelManager
    let onContinue: () -> Void
    let onSkip: (() -> Void)?

    @State private var isDownloading = false
    @State private var hasStartedDownload = false

    public init(
        modelManager: FluidAIModelManager,
        onContinue: @escaping () -> Void,
        onSkip: (() -> Void)? = nil
    ) {
        self.modelManager = modelManager
        self.onContinue = onContinue
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                headerIcon
                    .font(.system(size: 48))
                    .foregroundStyle(headerColor)

                Text("onboarding.download.title".localized)
                    .font(.title2)
                    .fontWeight(.bold)

                Text("onboarding.download.subtitle".localized)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 20)

            VStack(spacing: 16) {
                downloadProgressSection
            }
            .padding(.horizontal, 20)

            Spacer()

            HStack(spacing: 16) {
                if onSkip != nil, !isDownloading {
                    Button(action: { onSkip?() }) {
                        Text("onboarding.skip".localized)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                }

                Button(action: handlePrimaryAction) {
                    primaryButtonLabel
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(primaryButtonBackground)
                .keyboardShortcut(.defaultAction)
                .disabled(isDownloading && !downloadComplete)
            }
            .frame(maxWidth: 400)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: 550)
        .onAppear {
            checkInitialState()
        }
    }

    private var headerIcon: Image {
        switch modelManager.downloadPhase {
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
        case .ready:
            Image(systemName: "checkmark.circle.fill")
        default:
            Image(systemName: "arrow.down.circle.fill")
        }
    }

    private var headerColor: Color {
        switch modelManager.downloadPhase {
        case .failed: .red
        case .ready: .green
        default: .accentColor
        }
    }

    private var downloadComplete: Bool {
        if modelManager.downloadPhase == .ready {
            return true
        }

        return modelManager.isASRInstalled && modelManager.isDiarizationLoaded
    }

    private var primaryButtonBackground: Color {
        if downloadComplete {
            Color.accentColor
        } else if isDownloading {
            Color.secondary
        } else {
            Color.accentColor
        }
    }

    @ViewBuilder
    private var primaryButtonLabel: some View {
        if downloadComplete {
            Text("onboarding.continue".localized)
        } else if isDownloading {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("onboarding.download.downloading".localized)
            }
        } else {
            Text("onboarding.download.start".localized)
        }
    }

    private var downloadProgressSection: some View {
        VStack(spacing: 16) {
            Text(statusText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if isDownloading {
                VStack(spacing: 8) {
                    ProgressView(value: progressValue, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(height: 6)

                    Text(modelManager.downloadPhase.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = modelManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            modelStatusCards
        }
    }

    private var statusText: String {
        if downloadComplete {
            return "onboarding.download.status.complete".localized
        }

        return switch modelManager.downloadPhase {
        case .idle:
            "onboarding.download.status.idle".localized
        case .downloadingASR, .loadingASR, .downloadingDiarization, .loadingDiarization:
            "onboarding.download.status.in_progress".localized
        case .ready:
            "onboarding.download.status.complete".localized
        case .failed:
            "onboarding.download.status.failed".localized
        }
    }

    private var progressValue: Double {
        switch modelManager.downloadPhase {
        case .downloadingASR: 0.25
        case .loadingASR: 0.5
        case .downloadingDiarization: 0.75
        case .loadingDiarization: 0.9
        case .ready: 1.0
        default: 0.0
        }
    }

    private var modelStatusCards: some View {
        VStack(spacing: 12) {
            modelStatusRow(
                title: "onboarding.download.model.transcription".localized,
                isComplete: modelManager.isASRInstalled,
                isDownloading: modelManager.downloadPhase == .downloadingASR || modelManager.downloadPhase == .loadingASR
            )

            modelStatusRow(
                title: "onboarding.download.model.diarization".localized,
                isComplete: modelManager.isDiarizationLoaded,
                isDownloading: modelManager.downloadPhase == .downloadingDiarization || modelManager.downloadPhase == .loadingDiarization
            )
        }
        .padding(.top, 8)
    }

    private func modelStatusRow(title: String, isComplete: Bool, isDownloading: Bool) -> some View {
        HStack(spacing: 12) {
            if isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else if isDownloading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.subheadline)
                .foregroundStyle(isComplete ? .primary : .secondary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.05))
        )
    }

    private func checkInitialState() {
        if downloadComplete {
            hasStartedDownload = true
            isDownloading = false
        }
    }

    private func handlePrimaryAction() {
        if downloadComplete {
            onContinue()
        } else if !isDownloading {
            startDownload()
        }
    }

    private func startDownload() {
        isDownloading = true
        hasStartedDownload = true

        Task {
            await modelManager.loadModels()

            await modelManager.loadDiarizationModels()

            await MainActor.run {
                isDownloading = false
            }
        }
    }
}

#Preview {
    OnboardingDownloadModelsView(
        modelManager: FluidAIModelManager.shared,
        onContinue: {},
        onSkip: {}
    )
    .frame(width: 600, height: 550)
}
