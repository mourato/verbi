import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import SwiftUI

// preview-check: ignore — composer is previewed by MeetingConversationView.
extension MeetingConversationView {
    var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dictationErrorMessage, !dictationErrorMessage.isEmpty {
                Text(dictationErrorMessage)
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.error)
            }

            MeetingQuestionComposerTextView(
                text: Binding(
                    get: { questionText },
                    set: { onQuestionChange($0) }
                ),
                placeholder: "transcription.qa.placeholder".localized,
                sendOnReturn: sendOnReturn,
                onSubmit: {
                    guard !isAskDisabled else { return }
                    onAsk()
                }
            )

            HStack(spacing: 8) {
                modelSelectorButton

                dictationButton

                Spacer(minLength: 0)

                Toggle("transcription.qa.send_on_return".localized, isOn: $sendOnReturn)
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    .font(.caption)
                    .help("transcription.qa.send_on_return_help".localized)
                    .accessibilityLabel("transcription.qa.send_on_return".localized)

                Button("transcription.qa.ask".localized) {
                    onAsk()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAskDisabled)
            }
        }
        .padding(16)
    }

    private var modelSelectorButton: some View {
        HStack(spacing: 8) {
            ModelPickerField(
                options: AIModelPickerOptions.make(options: modelOptions) { option in
                    option.provider.rawValue == effectiveModelSelection.providerRawValue
                        && option.modelID == effectiveModelSelection.modelID
                },
                onOpen: onRefreshModelOptions,
                fallbackTitle: modelSelectorHelpText
            ) { option in
                onModelChange(option.value)
            }
            .disabled(isLoadingTranscription)

            if isLoadingModelOptions {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("settings.ai.model_refresh".localized)
            } else if modelOptions.isEmpty {
                Text("settings.enhancements.model_selector.empty".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelSelectorHelpText: String {
        let providerName = LLMProvider(rawValue: effectiveModelSelection.providerRawValue)?.displayName
            ?? effectiveModelSelection.providerRawValue
        let modelName = effectiveModelSelection.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelName.isEmpty {
            return "settings.enhancements.provider_models.summary.no_model".localized(with: providerName)
        }
        return "settings.enhancements.provider_models.summary".localized(with: providerName, modelName)
    }

    private var dictationButton: some View {
        Button {
            onToggleDictation()
        } label: {
            if dictationState == .processing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: dictationButtonIcon)
                    .font(.body)
            }
        }
        .buttonStyle(.bordered)
        .tint(dictationState == .recording ? AppDesignSystem.Colors.error : nil)
        .disabled(isLoadingTranscription || dictationState == .processing)
        .help(dictationHelpText)
        .accessibilityLabel(dictationHelpText)
    }

    private var dictationButtonIcon: String {
        switch dictationState {
        case .idle:
            "mic.fill"
        case .recording:
            "stop.fill"
        case .processing:
            "hourglass"
        }
    }

    private var dictationHelpText: String {
        switch dictationState {
        case .idle:
            "transcription.qa.dictation.start".localized
        case .recording:
            "transcription.qa.dictation.stop".localized
        case .processing:
            "transcription.qa.dictation.processing".localized
        }
    }

    private var isAskDisabled: Bool {
        questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || isAnswering
            || isLoadingTranscription
            || dictationState == .processing
    }
}
