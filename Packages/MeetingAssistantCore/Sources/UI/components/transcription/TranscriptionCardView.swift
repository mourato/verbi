import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// An expandable history row for a transcription item.
/// Collapsed = quiet scan; expanded = short context + secondary overflow.
public struct TranscriptionCardView: View {
    private enum Layout {
        /// List peek only — deep reading belongs on TranscriptionConversationPage.
        static let contentLineLimit = 3
    }

    let transcription: TranscriptionMetadata
    let transcriptionDetail: Transcription?
    let meetingNotesPlainText: String?
    let isExpanded: Bool
    let audioURL: URL?
    let availablePrompts: [PostProcessingPrompt]
    let availableRetryTranscriptionOptions: [RetryTranscriptionOption]
    let isPostProcessing: Bool
    let postProcessingErrorMessage: String?
    let onToggleExpand: () -> Void
    let onAction: (TranscriptionAction) -> Void

    public init(
        transcription: TranscriptionMetadata,
        transcriptionDetail: Transcription? = nil,
        meetingNotesPlainText: String? = nil,
        isExpanded: Bool,
        audioURL: URL?,
        availablePrompts: [PostProcessingPrompt] = [],
        availableRetryTranscriptionOptions: [RetryTranscriptionOption] = [],
        isPostProcessing: Bool = false,
        postProcessingErrorMessage: String? = nil,
        onToggleExpand: @escaping () -> Void,
        onAction: @escaping (TranscriptionAction) -> Void
    ) {
        self.transcription = transcription
        self.transcriptionDetail = transcriptionDetail
        self.meetingNotesPlainText = meetingNotesPlainText
        self.isExpanded = isExpanded
        self.audioURL = audioURL
        self.availablePrompts = availablePrompts
        self.availableRetryTranscriptionOptions = availableRetryTranscriptionOptions
        self.isPostProcessing = isPostProcessing
        self.postProcessingErrorMessage = postProcessingErrorMessage
        self.onToggleExpand = onToggleExpand
        self.onAction = onAction
    }

    @State private var selectedTab: TranscriptionTab = .aiProcessed
    @State private var showInfoPopover = false
    @State private var showPromptPopover = false
    @State private var isAudioDisclosureExpanded = false
    @State private var expandedTabs: Set<TranscriptionTab> = []

    public enum TranscriptionAction {
        public enum ExportKind: Sendable {
            case summary
            case original
        }

        case askAboutMeeting
        case copy(text: String)
        case updateMeetingTitle(String?)
        case updateCapturePurpose(CapturePurpose)
        case reprocess(prompt: PostProcessingPrompt)
        case retryTranscription(selection: TranscriptionProviderSelection)
        case info
        case viewPrompt
        case delete
        case export(ExportKind)
    }

    public enum TranscriptionTab: CaseIterable {
        case aiProcessed
        case original
        case segmented
        case notes

        var localized: String {
            switch self {
            case .aiProcessed:
                "transcription.tab.ai_processed".localized
            case .original:
                "transcription.tab.original".localized
            case .segmented:
                "transcription.tab.segmented".localized
            case .notes:
                "transcription.tab.notes".localized
            }
        }
    }

    public var body: some View {
        Group {
            if isExpanded {
                expandedContent
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isSelected)
            } else {
                TranscriptionCardCollapsedRow(
                    transcription: transcription,
                    title: collapsedTitle,
                    previewText: transcriptionCardDisplayText(transcription.previewText),
                    failureMessage: persistedPostProcessingFailureMessage,
                    supportsMeetingConversation: transcription.supportsMeetingConversation,
                    accessibilityHint: transcription.supportsMeetingConversation
                        ? "transcription.qa.accessibility_hint".localized
                        : "transcription.content.show_all".localized,
                    onPrimaryAction: {
                        if transcription.supportsMeetingConversation {
                            onAction(.askAboutMeeting)
                        } else {
                            onToggleExpand()
                        }
                    },
                    onToggleExpand: onToggleExpand
                )
            }
        }
        .contextMenu {
            actionMenu
        }
        .popover(isPresented: $showInfoPopover) {
            if let details = transcriptionDetail {
                TranscriptionInfoPopover(transcription: details)
            } else {
                Text("transcription.info.loading".localized)
                    .padding()
            }
        }
        .popover(isPresented: $showPromptPopover) {
            if let details = transcriptionDetail {
                TranscriptionPromptPopover(transcription: details)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                isAudioDisclosureExpanded = false
                showInfoPopover = false
                showPromptPopover = false
            }
        }
    }

    private var actionMenu: some View {
        TranscriptionCardActionMenu(
            supportsMeetingConversation: transcription.supportsMeetingConversation,
            hasPromptText: hasPromptText,
            hasPostProcessingContent: hasPostProcessingContent,
            availablePrompts: availablePrompts,
            availableRetryTranscriptionOptions: availableRetryTranscriptionOptions,
            isPostProcessing: isPostProcessing,
            audioURL: audioURL,
            currentText: currentText,
            capturePurposeActionLabel: toggleCapturePurposeLabel,
            capturePurposeActionIcon: toggleCapturePurposeIcon,
            onAction: onAction,
            onInfo: {
                if !isExpanded {
                    onToggleExpand()
                }
                showInfoPopover = true
                onAction(.info)
            },
            onViewPrompt: {
                if !isExpanded {
                    onToggleExpand()
                }
                showPromptPopover = true
                onAction(.viewPrompt)
            },
            onToggleCapturePurpose: {
                onAction(.updateCapturePurpose(toggledCapturePurpose))
            }
        )
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                TranscriptionCardSourceLabel(
                    transcription: transcription,
                    text: sourceDisplayName
                )

                Spacer(minLength: 8)

                if transcription.supportsMeetingConversation {
                    Button {
                        onAction(.askAboutMeeting)
                    } label: {
                        Label("transcription.qa.title".localized, systemImage: "bubble.left.and.bubble.right")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("transcription.qa.accessibility_hint".localized)
                }

                if shouldShowTabPicker {
                    Picker("", selection: $selectedTab) {
                        ForEach(availableTabs, id: \.self) { tab in
                            Text(tab.localized).tag(tab)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 160)
                }

                Menu {
                    actionMenu
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                TranscriptionCardCollapseButton(action: onToggleExpand)
            }

            if shouldDisplayMeetingTitle {
                if transcription.supportsMeetingConversation {
                    TranscriptionMeetingTitleEditor(
                        title: currentPersistedMeetingTitle,
                        placeholder: sourceDisplayName,
                        onCommit: { title in
                            onAction(.updateMeetingTitle(title))
                        }
                    )
                } else {
                    Text(collapsedMeetingTitle)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            contentView
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = inlinePostProcessingErrorMessage {
                TranscriptionCardFailureLabel(message: error)
            }

            if audioURL != nil {
                DisclosureGroup(isExpanded: $isAudioDisclosureExpanded) {
                    TranscriptionAudioPlayerView(audioURL: audioURL)
                        .padding(.top, 4)
                } label: {
                    Label("settings.section.audio".localized, systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            ensureValidSelectedTab()
        }
        .onChange(of: isSegmentedTabEnabled) { _, _ in
            ensureValidSelectedTab()
        }
        .onChange(of: hasPostProcessingContent) { _, _ in
            ensureValidSelectedTab()
        }
    }

    private var availableTabs: [TranscriptionTab] {
        var tabs: [TranscriptionTab] = [.aiProcessed, .original]

        if isSegmentedTabEnabled {
            tabs.append(.segmented)
        }
        if isNotesTabEnabled {
            tabs.append(.notes)
        }

        return tabs
    }

    private var shouldShowTabPicker: Bool {
        availableTabs.count > 1
    }

    private var hasPostProcessingContent: Bool {
        if let processedContent = transcriptionDetail?.processedContent {
            return !processedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return transcription.isPostProcessed
    }

    private var hasPromptText: Bool {
        transcription.capturePurpose == .dictation && (
            transcriptionDetail?.postProcessingRequestSystemPrompt != nil
                || transcriptionDetail?.postProcessingRequestUserPrompt != nil
                || transcriptionDetail?.postProcessingPromptId != nil
        )
    }

    private var isSegmentedTabEnabled: Bool {
        transcription.capturePurpose == .meeting
            && AppSettingsStore.shared.isDiarizationEnabled
    }

    private var isNotesTabEnabled: Bool {
        transcription.capturePurpose == .meeting
    }

    private func ensureValidSelectedTab() {
        guard !availableTabs.contains(selectedTab) else { return }
        selectedTab = availableTabs.first ?? .original
    }

    private var currentText: String {
        switch selectedTab {
        case .aiProcessed:
            if let detail = transcriptionDetail {
                return TranscriptionDisplayText.preferredSummary(
                    processedContent: detail.processedContent,
                    canonicalSummary: detail.canonicalSummary,
                    text: detail.text,
                    emptyFallback: transcription.previewText
                )
            }
            return transcription.previewText
        case .original:
            return transcriptionDetail?.rawText ?? transcription.previewText
        case .segmented:
            return sortedSegments(transcriptionDetail?.segments ?? [])
                .map { "\($0.speaker): \($0.text)" }
                .joined(separator: "\n\n")
        case .notes:
            return meetingNotesPlainText
                ?? transcriptionDetail?.contextItems.first(where: { $0.source == .meetingNotes })?.text
                ?? ""
        }
    }

    private var contentView: some View {
        TranscriptionCardContentView(
            text: transcriptionCardDisplayText(currentText),
            selectedTab: selectedTab,
            lineLimit: Layout.contentLineLimit,
            isPostProcessing: isPostProcessing,
            expandedTabs: $expandedTabs
        )
    }

    private var inlinePostProcessingErrorMessage: String? {
        guard let postProcessingErrorMessage else {
            return persistedPostProcessingFailureMessage
        }
        let trimmed = postProcessingErrorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private var persistedPostProcessingFailureMessage: String? {
        let trimmed = transcription.postProcessingFailureReason?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func sortedSegments(_ segments: [Transcription.Segment]) -> [Transcription.Segment] {
        segments.sorted { lhs, rhs in
            if lhs.startTime != rhs.startTime {
                return lhs.startTime < rhs.startTime
            }
            if lhs.endTime != rhs.endTime {
                return lhs.endTime < rhs.endTime
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var appSource: MeetingApp {
        MeetingApp(rawValue: transcription.appRawValue) ?? .unknown
    }

    private var sourceDisplayName: String {
        let trimmed = transcription.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? appSource.displayName : trimmed
    }

    private var toggledCapturePurpose: CapturePurpose {
        transcription.capturePurpose == .meeting ? .dictation : .meeting
    }

    private var toggleCapturePurposeLabel: String {
        switch transcription.capturePurpose {
        case .dictation:
            "transcription.actions.mark_as_meeting".localized
        case .meeting:
            "transcription.actions.mark_as_dictation".localized
        }
    }

    private var toggleCapturePurposeIcon: String {
        switch transcription.capturePurpose {
        case .dictation:
            "person.2.fill"
        case .meeting:
            "text.bubble.fill"
        }
    }

    private var currentPersistedMeetingTitle: String? {
        let detailTitle = transcriptionDetail?.meeting.preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let detailTitle, !detailTitle.isEmpty {
            return detailTitle
        }

        let metadataTitle = transcription.meetingTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let metadataTitle, !metadataTitle.isEmpty {
            return metadataTitle
        }

        return nil
    }

    private var shouldDisplayMeetingTitle: Bool {
        transcription.capturePurpose == .meeting
    }

    private var collapsedMeetingTitle: String {
        currentPersistedMeetingTitle ?? sourceDisplayName
    }

    private var collapsedTitle: String {
        shouldDisplayMeetingTitle ? collapsedMeetingTitle : sourceDisplayName
    }
}
