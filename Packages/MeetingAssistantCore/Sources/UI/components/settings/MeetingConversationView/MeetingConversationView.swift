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

        var icon: String {
            switch self {
            case .chat:
                "bubble.left.and.bubble.right.fill"
            case .segmented:
                "waveform"
            case .notes:
                "note.text"
            }
        }
    }

    let transcription: Transcription?
    let isLoadingTranscription: Bool
    let turns: [TranscriptionLibraryViewModel.QATurn]
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

    @State private var selectedInternalTab: InternalTab = .chat
    @State private var speakerRenames: [String: String] = [:]
    @State var sendOnReturn = false
    @State private var notesDraft: MeetingNotesContent = .empty
    @State private var lastSavedNotes: MeetingNotesContent = .empty
    @State private var notesAutosaveTask: Task<Void, Never>?

    public init(
        transcription: Transcription?,
        isLoadingTranscription: Bool,
        turns: [TranscriptionLibraryViewModel.QATurn],
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
        onUpdateMeetingNotes: @escaping (_ content: MeetingNotesContent, _ transcriptionID: UUID) -> Void = { _, _ in }
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
                DSGlassSegmentedControl(
                    selection: $selectedInternalTab,
                    items: availableTabs,
                    fillsWidth: true,
                    title: \.label,
                    icon: \.icon
                )
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

    func turnView(_ turn: TranscriptionLibraryViewModel.QATurn) -> some View {
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
            in: RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius)
        )
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

            if #available(macOS 27, *) {
                // The AppKit markdown engine blanks the whole Settings window when it
                // mounts in this detail column on macOS 27; use a native editor until
                // the OS/engine side settles. The floating panel keeps the engine.
                TextEditor(text: notesPlainTextBinding)
                    .font(.body)
                    .padding(AppDesignSystem.Layout.textAreaPadding)
                    .background(AppDesignSystem.Colors.textBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.smallCornerRadius))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                MeetingNotesMarkdownEditor(
                    content: $notesDraft,
                    documentId: noteDocumentId
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
    }

    private var notesPlainTextBinding: Binding<String> {
        Binding(
            get: { notesDraft.plainText },
            set: { notesDraft = MeetingNotesContent(plainText: $0, richTextRTFData: notesDraft.richTextRTFData) }
        )
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
                        text: speakerRenameBinding(for: speaker)
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
            set: { speakerRenames[speaker] = $0 }
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
