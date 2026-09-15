import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Detail view for a selected transcription.
public struct TranscriptionDetailView: View {
    let transcription: Transcription
    let isProcessing: Bool
    let isSourceEditable: Bool
    let onApplyPrompt: (PostProcessingPrompt) -> Void
    let onUpdateSource: (Bool) -> Void
    let isQnAEnabled: Bool
    let qaQuestion: String
    let onQuestionChange: (String) -> Void
    let onAskQuestion: () -> Void
    let onRetryQuestion: () -> Void
    let qaResponse: MeetingQAResponse?
    let qaErrorMessage: String?
    let isAnsweringQuestion: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        transcription: Transcription,
        isProcessing: Bool = false,
        isSourceEditable: Bool = false,
        onApplyPrompt: @escaping (PostProcessingPrompt) -> Void = { _ in },
        onUpdateSource: @escaping (Bool) -> Void = { _ in },
        isQnAEnabled: Bool = false,
        qaQuestion: String = "",
        onQuestionChange: @escaping (String) -> Void = { _ in },
        onAskQuestion: @escaping () -> Void = {},
        onRetryQuestion: @escaping () -> Void = {},
        qaResponse: MeetingQAResponse? = nil,
        qaErrorMessage: String? = nil,
        isAnsweringQuestion: Bool = false
    ) {
        self.transcription = transcription
        self.isProcessing = isProcessing
        self.isSourceEditable = isSourceEditable
        self.onApplyPrompt = onApplyPrompt
        self.onUpdateSource = onUpdateSource
        self.isQnAEnabled = isQnAEnabled
        self.qaQuestion = qaQuestion
        self.onQuestionChange = onQuestionChange
        self.onAskQuestion = onAskQuestion
        self.onRetryQuestion = onRetryQuestion
        self.qaResponse = qaResponse
        self.qaErrorMessage = qaErrorMessage
        self.isAnsweringQuestion = isAnsweringQuestion
    }

    public var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    Divider()

                    if let processed = transcription.processedContent {
                        processedTranscriptSection(processed)
                        Divider()
                        originalTranscriptSection
                    } else {
                        transcriptSection
                    }

                    if isQnAEnabled {
                        Divider()
                        groundedQnASection
                    }
                }
                .padding()
            }
            .blur(radius: isProcessing ? 2 : 0)
            .disabled(isProcessing)

            if isProcessing {
                processingOverlay
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(transcription.formattedDate)
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                HStack(spacing: 12) {
                    aiActionsMenu

                    Menu {
                        Button("common.delete".localized, role: .destructive) {
                            // TODO: Implement delete
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .menuStyle(.borderlessButton)
                }
            }

            HStack(spacing: 8) {
                statusBadge(text: "transcription.completed".localized, color: .green, icon: "checkmark.circle.fill")
                appBadge(text: transcription.meeting.appName, color: .blue)
                if isSourceEditable {
                    sourcePicker
                }
                if transcription.isPostProcessed {
                    statusBadge(
                        text: transcription.postProcessingPromptTitle ?? "transcription.processed".localized,
                        color: .orange,
                        icon: "sparkles"
                    )
                }
            }

            Text("transcription.recorded_on".localized(with: transcription.formattedDate))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var aiActionsMenu: some View {
        Menu {
            Section("transcription.ai_post_processing".localized) {
                ForEach(PostProcessingPrompt.allPredefined) { prompt in
                    Button {
                        onApplyPrompt(prompt)
                    } label: {
                        Label(prompt.title, systemImage: prompt.icon)
                    }
                }
            }
        } label: {
            Label("transcription.ai_actions".localized, systemImage: "sparkles")
                .settingsPulseSymbolEffect(value: isProcessing, reduceMotion: reduceMotion)
        }
        .buttonStyle(.bordered)
        .tint(.orange)
    }

    private var processingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("transcription.processing_overlay_hint".localized)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .padding(30)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 10)
    }

    private func statusBadge(text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }

    private func appBadge(text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            AppIconView(
                bundleIdentifier: transcription.meeting.appBundleIdentifier,
                fallbackSystemName: transcription.meeting.appIcon,
                size: 14,
                cornerRadius: 3
            )
            Text(text)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }

    private var sourcePicker: some View {
        Picker("", selection: Binding(
            get: { sourceSelection },
            set: { newValue in
                onUpdateSource(newValue == .meeting)
            }
        )) {
            ForEach(SourceSelection.allCases, id: \.self) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Transcript Section

    private var transcriptSection: some View {
        contentBox(
            title: "transcription.title".localized,
            text: transcription.text,
            isOriginal: false
        )
    }

    private func processedTranscriptSection(_ text: String) -> some View {
        contentBox(
            title: transcription.postProcessingPromptTitle ?? "transcription.processed".localized,
            text: text,
            isOriginal: false,
            showSparkles: true
        )
    }

    private var originalTranscriptSection: some View {
        contentBox(
            title: "transcription.original_title".localized,
            text: transcription.rawText,
            isOriginal: true
        )
    }

    private func contentBox(title: String, text: String, isOriginal: Bool, showSparkles: Bool = false) -> some View {
        let displayText = transcriptionDisplayText(text)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    if showSparkles {
                        Image(systemName: "sparkles")
                            .foregroundStyle(AppDesignSystem.Colors.aiGradient)
                    }
                    Text(title)
                        .font(.headline)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                } label: {
                    Label("common.copy".localized, systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
            }

            Text(displayText)
                .font(.body)
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    isOriginal ? AppDesignSystem.Colors.subtleFill2 : AppDesignSystem.Colors.settingsCardBackground,
                    in: RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                )
        }
    }

    private func transcriptionDisplayText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "transcription.empty_fallback".localized
        }
        return text
    }

    private var groundedQnASection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("transcription.qa.title".localized)
                .font(.headline)

            HStack(spacing: 8) {
                TextField(
                    "transcription.qa.placeholder".localized,
                    text: Binding(
                        get: { qaQuestion },
                        set: { onQuestionChange($0) }
                    )
                )
                .textFieldStyle(.roundedBorder)

                Button("transcription.qa.ask".localized) {
                    onAskQuestion()
                }
                .buttonStyle(.borderedProminent)
                .disabled(qaQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnsweringQuestion)
            }

            if isAnsweringQuestion {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("transcription.qa.loading".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let qaErrorMessage, !qaErrorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(qaErrorMessage)
                        .font(.caption)
                        .foregroundStyle(AppDesignSystem.Colors.error)

                    Button("transcription.qa.retry".localized) {
                        onRetryQuestion()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAnsweringQuestion)
                }
            }

            if let qaResponse {
                if qaResponse.status == .notFound {
                    Text("transcription.qa.not_found".localized)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(qaResponse.answer)
                            .font(.body)
                            .textSelection(.enabled)

                        if !qaResponse.evidence.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("transcription.qa.evidence_title".localized)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)

                                ForEach(Array(qaResponse.evidence.enumerated()), id: \.offset) { _, item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("[\(formatTimestamp(item.startTime))–\(formatTimestamp(item.endTime))] \(item.speaker)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(item.excerpt)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        AppDesignSystem.Colors.subtleFill,
                                        in: RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func formatTimestamp(_ value: Double) -> String {
        let totalSeconds = max(0, Int(value.rounded()))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var sourceSelection: SourceSelection {
        switch transcription.capturePurpose {
        case .dictation:
            .dictation
        case .meeting:
            .meeting
        }
    }
}

private enum SourceSelection: String, CaseIterable {
    case dictation
    case meeting

    var title: String {
        switch self {
        case .dictation:
            "transcription.source.dictation".localized
        case .meeting:
            "transcription.source.meeting".localized
        }
    }
}

private extension Transcription {
    static var previewDetailForSettings: Self {
        .init(
            meeting: Meeting(
                app: .slack,
                state: .completed,
                startTime: Date().addingTimeInterval(-1800),
                endTime: Date().addingTimeInterval(-600),
                audioFilePath: nil
            ),
            segments: [
                .init(speaker: "Speaker 1", text: "Precisamos consolidar os previews da interface.", startTime: 0, endTime: 9),
                .init(speaker: "Speaker 2", text: "Vou priorizar as telas com side effects na fase seguinte.", startTime: 10, endTime: 21)
            ],
            text: "Precisamos consolidar os previews da interface. Vou priorizar as telas com side effects na fase seguinte.",
            rawText: "precisamos consolidar previews interface vou priorizar telas com side effects na fase seguinte",
            processedContent: "Precisamos consolidar os previews da interface e priorizar, na sequência, as telas com side effects.",
            postProcessingPromptTitle: "Planning summary",
            language: "pt"
        )
    }
}

#Preview("Processed") {
    TranscriptionDetailView(
        transcription: .previewDetailForSettings,
        isProcessing: false,
        isQnAEnabled: true,
        qaQuestion: "What was decided about previews?",
        qaResponse: MeetingQAResponse(
            status: .answered,
            answer: "The team decided to prioritize screens with startup side effects in the next phase.",
            evidence: [
                MeetingQAEvidence(
                    speaker: "Speaker 2",
                    startTime: 10,
                    endTime: 21,
                    excerpt: "Vou priorizar as telas com side effects na fase seguinte."
                )
            ]
        )
    )
    .frame(width: 860, height: 620)
}

#Preview("Processing Overlay") {
    TranscriptionDetailView(transcription: .previewDetailForSettings, isProcessing: true)
        .frame(width: 860, height: 620)
}
