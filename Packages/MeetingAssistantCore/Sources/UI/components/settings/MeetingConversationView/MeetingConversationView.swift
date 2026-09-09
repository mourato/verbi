import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

public struct MeetingConversationView: View {
    private enum InternalTab: String, Identifiable {
        case chat
        case segmented
        case notes

        var id: String {
            rawValue
        }

        var label: String {
            switch self {
            case .chat:
                "transcription.qa.tab.chat".localized
            case .segmented:
                "transcription.qa.tab.segmented".localized
            case .notes:
                "transcription.qa.tab.notes".localized
            }
        }
    }

    let transcription: Transcription?
    let isLoadingTranscription: Bool
    let turns: [TranscriptionSettingsViewModel.QATurn]
    let questionText: String
    let meetingNotesContent: MeetingNotesContent
    let onQuestionChange: (String) -> Void
    let onAsk: () -> Void
    let onRetry: (_ turnID: UUID, _ question: String) -> Void
    let isAnswering: Bool
    let currentErrorMessage: String?
    let effectiveModelSelection: MeetingQAModelSelection
    let modelOptions: [EnhancementsProviderModelOption]
    let isLoadingModelOptions: Bool
    let onModelChange: (EnhancementsProviderModelOption) -> Void
    let onRefreshModelOptions: () -> Void
    let dictationState: MeetingQuestionDictationService.State
    let dictationErrorMessage: String?
    let onToggleDictation: () -> Void
    let onRenameSpeaker: (_ original: String, _ updated: String, _ transcriptionID: UUID) -> Void
    let onUpdateMeetingNotes: (_ content: MeetingNotesContent, _ transcriptionID: UUID) -> Void

    @State private var isShowingModelSelector = false
    @State private var selectedInternalTab: InternalTab = .chat
    @State private var speakerRenames: [String: String] = [:]
    @State private var sendOnReturn = false
    @State private var notesDraft: MeetingNotesContent = .empty
    @State private var lastSavedNotes: MeetingNotesContent = .empty
    @State private var notesAutosaveTask: Task<Void, Never>?

    public init(
        transcription: Transcription?,
        isLoadingTranscription: Bool,
        turns: [TranscriptionSettingsViewModel.QATurn],
        questionText: String,
        meetingNotesContent: MeetingNotesContent,
        onQuestionChange: @escaping (String) -> Void,
        onAsk: @escaping () -> Void,
        onRetry: @escaping (_ turnID: UUID, _ question: String) -> Void,
        isAnswering: Bool,
        currentErrorMessage: String?,
        effectiveModelSelection: MeetingQAModelSelection,
        modelOptions: [EnhancementsProviderModelOption],
        isLoadingModelOptions: Bool,
        onModelChange: @escaping (EnhancementsProviderModelOption) -> Void,
        onRefreshModelOptions: @escaping () -> Void,
        dictationState: MeetingQuestionDictationService.State,
        dictationErrorMessage: String?,
        onToggleDictation: @escaping () -> Void,
        onRenameSpeaker: @escaping (_ original: String, _ updated: String, _ transcriptionID: UUID) -> Void = { _, _, _ in },
        onUpdateMeetingNotes: @escaping (_ content: MeetingNotesContent, _ transcriptionID: UUID) -> Void = { _, _ in },
    ) {
        self.transcription = transcription
        self.isLoadingTranscription = isLoadingTranscription
        self.turns = turns
        self.questionText = questionText
        self.meetingNotesContent = meetingNotesContent
        self.onQuestionChange = onQuestionChange
        self.onAsk = onAsk
        self.onRetry = onRetry
        self.isAnswering = isAnswering
        self.currentErrorMessage = currentErrorMessage
        self.effectiveModelSelection = effectiveModelSelection
        self.modelOptions = modelOptions
        self.isLoadingModelOptions = isLoadingModelOptions
        self.onModelChange = onModelChange
        self.onRefreshModelOptions = onRefreshModelOptions
        self.dictationState = dictationState
        self.dictationErrorMessage = dictationErrorMessage
        self.onToggleDictation = onToggleDictation
        self.onRenameSpeaker = onRenameSpeaker
        self.onUpdateMeetingNotes = onUpdateMeetingNotes
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            if selectedInternalTab == .chat {
                Divider()
                composer
            }
        }
        .sheet(isPresented: $isShowingModelSelector) {
            EnhancementsModelSelectionSheet(
                options: modelOptions,
                isSelected: { option in
                    option.provider.rawValue == effectiveModelSelection.providerRawValue
                        && option.modelID == effectiveModelSelection.modelID
                },
                onSelect: { option in
                    onModelChange(option)
                    isShowingModelSelector = false
                },
                onCancel: {
                    isShowingModelSelector = false
                },
            )
            .onAppear {
                onRefreshModelOptions()
            }
        }
        .onAppear {
            selectedInternalTab = .chat
            syncNotesFromPersistedValue()
            ensureValidInternalTabSelection()
        }
        .onChange(of: hasSegments) { _, _ in
            ensureValidInternalTabSelection()
        }
        .onChange(of: meetingNotesContent) { oldValue, newValue in
            if notesDraft == oldValue {
                notesDraft = newValue
            }
            lastSavedNotes = newValue
        }
        .onChange(of: notesDraft) { _, _ in
            scheduleNotesAutosave()
        }
        .onChange(of: transcription?.id) { oldID, _ in
            if let oldID {
                flushNotesAutosave(for: oldID)
            }
            selectedInternalTab = .chat
            syncNotesFromPersistedValue()
            ensureValidInternalTabSelection()
        }
        .onDisappear {
            if let transcriptionID = transcription?.id {
                flushNotesAutosave(for: transcriptionID)
            } else {
                notesAutosaveTask?.cancel()
                notesAutosaveTask = nil
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("transcription.qa.title".localized, systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)

            Spacer()
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if isLoadingTranscription {
            VStack(spacing: 8) {
                Spacer()
                ProgressView()
                Text("settings.transcriptions.loading".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else if transcription == nil {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("settings.transcriptions.no_selection".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                Picker("", selection: $selectedInternalTab) {
                    ForEach(availableTabs) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch selectedInternalTab {
                case .chat:
                    chatContent
                case .segmented:
                    segmentedContent
                case .notes:
                    notesContent
                }
            }
        }
    }

    func turnView(_ turn: TranscriptionSettingsViewModel.QATurn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "person.fill")
                    .foregroundStyle(AppDesignSystem.Colors.accent)
                Text(turn.question)
                    .font(.body)
            }

            if let response = turn.response {
                if response.status == .notFound {
                    Text("transcription.qa.not_found".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(AppDesignSystem.Colors.iconHighlight)
                            Text(response.answer)
                                .font(.body)
                                .textSelection(.enabled)
                        }

                        if !response.evidence.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("transcription.qa.evidence_title".localized)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                ForEach(Array(response.evidence.enumerated()), id: \.offset) { _, item in
                                    Text("[\(formatTimestamp(item.startTime))–\(formatTimestamp(item.endTime))] \(item.speaker): \(item.excerpt)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } else if let errorMessage = turn.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(AppDesignSystem.Colors.error)

                    Button("transcription.qa.retry".localized) {
                        onRetry(turn.id, turn.question)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isAnswering)
                }
            }
        }
        .padding(12)
        .background(
            AppDesignSystem.Colors.subtleFill,
            in: RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius),
        )
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let dictationErrorMessage, !dictationErrorMessage.isEmpty {
                Text(dictationErrorMessage)
                    .font(.caption)
                    .foregroundStyle(AppDesignSystem.Colors.error)
            }

            MeetingQuestionComposerTextView(
                text: Binding(
                    get: { questionText },
                    set: { onQuestionChange($0) },
                ),
                placeholder: "transcription.qa.placeholder".localized,
                sendOnReturn: sendOnReturn,
                onSubmit: {
                    guard !isAskDisabled else { return }
                    onAsk()
                },
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
        Button {
            isShowingModelSelector = true
        } label: {
            if isLoadingModelOptions {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18, height: 18)
            } else {
                Image(systemName: "brain.head.profile")
                    .font(.body)
            }
        }
        .buttonStyle(.bordered)
        .disabled(isLoadingTranscription)
        .help(modelSelectorHelpText)
        .accessibilityLabel(modelSelectorHelpText)
    }

    private var modelSelectorHelpText: String {
        let providerName = AIProvider(rawValue: effectiveModelSelection.providerRawValue)?.displayName
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

    // MARK: - Segmented Tab

    private var availableTabs: [InternalTab] {
        if hasSegments {
            return [.chat, .segmented, .notes]
        }
        return [.chat, .notes]
    }

    private var hasSegments: Bool {
        guard let transcription else { return false }
        return !transcription.segments.isEmpty
    }

    private var sortedSegmentsForDisplay: [Transcription.Segment] {
        guard let transcription else { return [] }
        return transcription.segments.sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            if lhs.endTime != rhs.endTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var uniqueSpeakers: [String] {
        var seen = Set<String>()
        var result = [String]()
        for segment in sortedSegmentsForDisplay where seen.insert(segment.speaker).inserted {
            result.append(segment.speaker)
        }
        return result
    }

    private var segmentedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                speakerRenameSection

                Divider()

                segmentListSection
            }
            .padding(16)
        }
    }

    // MARK: - Notes Tab

    private var notesContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("recording_indicator.meeting_notes.help".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            MeetingNotesMarkdownEditor(
                content: $notesDraft,
                documentId: noteDocumentId,
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
    }

    private var speakerRenameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(uniqueSpeakers, id: \.self) { speaker in
                HStack(spacing: 8) {
                    Text(speaker)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 80, alignment: .leading)

                    TextField(
                        "transcription.speaker.rename.field_placeholder".localized,
                        text: speakerRenameBinding(for: speaker),
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)

                    Button("transcription.speaker.rename.save".localized) {
                        guard let transcription else { return }
                        let newName = speakerRenames[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        guard !newName.isEmpty, newName != speaker else { return }
                        onRenameSpeaker(speaker, newName, transcription.id)
                        speakerRenames.removeValue(forKey: speaker)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSaveDisabled(for: speaker))
                }
            }
        }
    }

    private func speakerRenameBinding(for speaker: String) -> Binding<String> {
        Binding(
            get: { speakerRenames[speaker] ?? "" },
            set: { speakerRenames[speaker] = $0 },
        )
    }

    private func isSaveDisabled(for speaker: String) -> Bool {
        let value = speakerRenames[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty || value == speaker
    }

    private func ensureValidInternalTabSelection() {
        guard availableTabs.contains(selectedInternalTab) else {
            selectedInternalTab = .chat
            return
        }
    }

    private func syncNotesFromPersistedValue() {
        notesDraft = meetingNotesContent
        lastSavedNotes = meetingNotesContent
    }

    private func scheduleNotesAutosave() {
        notesAutosaveTask?.cancel()
        guard let transcription else { return }
        guard notesDraft != lastSavedNotes else { return }

        let pendingNotes = notesDraft
        let transcriptionID = transcription.id
        notesAutosaveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                persistNotesIfNeeded(pendingNotes, for: transcriptionID)
            }
        }
    }

    private func flushNotesAutosave(for transcriptionID: UUID) {
        notesAutosaveTask?.cancel()
        notesAutosaveTask = nil
        persistNotesIfNeeded(notesDraft, for: transcriptionID)
    }

    private func persistNotesIfNeeded(_ content: MeetingNotesContent, for transcriptionID: UUID) {
        guard content != lastSavedNotes else { return }
        onUpdateMeetingNotes(content, transcriptionID)
        lastSavedNotes = content
    }

    private var noteDocumentId: String {
        if let transcription {
            return "transcription-notes-\(transcription.id.uuidString)"
        }

        return "meeting-conversation-notes"
    }

    private var segmentListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(sortedSegmentsForDisplay) { segment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(segment.speaker)
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                        Text("[\(formatTimestamp(segment.startTime))–\(formatTimestamp(segment.endTime))]")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(segment.text)
                        .font(.body)
                        .textSelection(.enabled)
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
}

#Preview("Meeting conversation") {
    MeetingConversationView(
        transcription: .previewConversation,
        isLoadingTranscription: false,
        turns: [
            .init(
                question: "What did we decide about previews?",
                response: MeetingQAResponse(
                    status: .answered,
                    answer: "The team decided to prioritize pages with real side effects, then clean up by component group.",
                    evidence: [
                        .init(
                            speaker: "Speaker 2",
                            startTime: 10,
                            endTime: 21,
                            excerpt: "Vamos priorizar telas com side effects primeiro.",
                        ),
                    ],
                ),
                errorMessage: nil,
            ),
        ],
        questionText: "How should I finish this reorg?",
        meetingNotesContent: MeetingNotesContent(
            plainText: "Owner: Speaker 2\n- Prioritize screens with side effects",
        ),
        onQuestionChange: { _ in },
        onAsk: {},
        onRetry: { _, _ in },
        isAnswering: false,
        currentErrorMessage: nil,
        effectiveModelSelection: MeetingQAModelSelection(
            providerRawValue: AIProvider.openai.rawValue,
            modelID: "gpt-4o",
        ),
        modelOptions: [
            .init(provider: .openai, modelID: "gpt-4o"),
            .init(provider: .openai, modelID: "gpt-4.1-mini"),
            .init(provider: .anthropic, modelID: "claude-3-5-sonnet"),
        ],
        isLoadingModelOptions: false,
        onModelChange: { _ in },
        onRefreshModelOptions: {},
        dictationState: .idle,
        dictationErrorMessage: nil,
        onToggleDictation: {},
        onRenameSpeaker: { _, _, _ in },
        onUpdateMeetingNotes: { _, _ in },
    )
    .frame(width: 760, height: 680)
    .padding()
}

private extension Transcription {
    static var previewConversation: Transcription {
        Transcription(
            meeting: Meeting(
                app: .slack,
                state: .completed,
                startTime: Date().addingTimeInterval(-1_800),
                endTime: Date().addingTimeInterval(-600),
                audioFilePath: nil,
            ),
            segments: [
                .init(speaker: "Speaker 1", text: "Precisamos consolidar os previews da interface.", startTime: 0, endTime: 9),
                .init(speaker: "Speaker 2", text: "Vou priorizar as telas com side effects na fase seguinte.", startTime: 10, endTime: 21),
            ],
            text: "Precisamos consolidar os previews da interface. Vou priorizar as telas com side effects na fase seguinte.",
            rawText: "precisamos consolidar previews interface vou priorizar telas com side effects na fase seguinte",
            processedContent: "Precisamos consolidar os previews da interface e priorizar, na sequência, as telas com side effects.",
            postProcessingPromptTitle: "Planning summary",
            language: "pt",
        )
    }
}
