import Combine
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

// MARK: - Main Tab

/// Main tab for managing transcriptions in Settings.
public struct TranscriptionsSettingsTab: View {
    @StateObject private var viewModel = TranscriptionSettingsViewModel()
    @StateObject private var dictationService = MeetingQuestionDictationService()
    @Binding private var navigationHistory: TranscriptionsNavigationHistory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentRoute: TranscriptionsPageRoute {
        navigationHistory.currentRoute
    }

    public init(
        navigationHistory: Binding<TranscriptionsNavigationHistory> = .constant(TranscriptionsNavigationHistory()),
    ) {
        _navigationHistory = navigationHistory
    }

    public var body: some View {
        VStack(spacing: 0) {
            contentSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await viewModel.loadIfNeeded()
            syncSelectionForCurrentRoute()
        }
        .onReceive(NotificationCenter.default.publisher(for: .meetingAssistantTranscriptionSaved)) { _ in
            Task {
                await viewModel.loadTranscriptions()
            }
        }
        .onDisappear {
            Task {
                await dictationService.cancel()
            }
        }
        .onChange(of: viewModel.transcriptions) { _, transcriptions in
            sanitizeNavigationHistory(using: transcriptions)
        }
        .confirmationDialog(
            "settings.transcriptions.delete_title".localized,
            isPresented: $viewModel.showDeleteConfirmation,
            titleVisibility: .visible,
        ) {
            Button("common.delete".localized, role: .destructive) {
                Task {
                    await viewModel.executeDeleteTranscription()
                }
            }
            Button("common.cancel".localized, role: .cancel) {
                viewModel.cancelDeleteTranscription()
            }
        } message: {
            Text("settings.transcriptions.delete_message".localized(with: viewModel.pendingDeleteTranscription?.appName ?? ""))
        }
        .alert("common.error".localized, isPresented: Binding(
            get: { viewModel.operationErrorMessage != nil },
            set: {
                if !$0 {
                    viewModel.operationErrorMessage = nil
                }
            },
        )) {
            Button("common.ok".localized, role: .cancel) {}
        } message: {
            if let errorMessage = viewModel.operationErrorMessage {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        switch currentRoute {
        case .list:
            listPage
        case let .conversation(transcriptionID):
            conversationPage(transcriptionID: transcriptionID)
        }
    }

    // MARK: - List Page

    private var listPage: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                SettingsSectionHeader(
                    title: "settings.section.history".localized,
                    description: "settings.transcriptions.items_found".localized(with: viewModel.filteredTranscriptions.count),
                )

                SettingsSearchField(
                    text: $viewModel.searchText,
                    placeholder: "settings.transcriptions.search_placeholder".localized,
                    style: .history,
                )

                HStack(spacing: 12) {
                    sourceFilterPicker
                        .frame(maxWidth: .infinity, alignment: .leading)

                    dateFilterPicker

                    appFilterPicker
                }

                if let errorMessage = viewModel.loadErrorMessage {
                    SettingsStateBlock(
                        kind: .warning,
                        title: "settings.transcriptions.error_load".localized,
                        message: errorMessage,
                        actionTitle: "settings.service.verify".localized,
                    ) {
                        Task {
                            await viewModel.loadTranscriptions()
                        }
                    }
                }
            }
            .padding(24)

            Divider()

            if viewModel.isLoading {
                SettingsStateBlock(
                    kind: .loading,
                    title: "settings.transcriptions.loading".localized,
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(24)
            } else if viewModel.filteredTranscriptions.isEmpty {
                emptyState
            } else {
                transcriptionsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var sourceFilterPicker: some View {
        Picker(
            "",
            selection: $viewModel.sourceFilter,
        ) {
            ForEach(RecordingSourceFilter.allCases, id: \.self) { filter in
                Text(filter.displayName).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.regular)
        .labelsHidden()
    }

    private var appFilterPicker: some View {
        Picker("", selection: $viewModel.appFilterId) {
            ForEach(viewModel.appFilterOptions) { option in
                Text(option.displayName).tag(option.id)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.regular)
        .labelsHidden()
        .fixedSize()
    }

    private var dateFilterPicker: some View {
        Picker("", selection: $viewModel.dateFilter) {
            ForEach(DateFilter.allCases, id: \.self) { filter in
                Text(filter.displayName).tag(filter)
            }
        }
        .pickerStyle(.menu)
        .controlSize(.regular)
        .labelsHidden()
        .fixedSize()
    }

    private var emptyState: some View {
        ScrollView {
            MAEmptyStateView(
                iconName: "clock.arrow.circlepath",
                title: "settings.transcriptions.empty_title".localized,
                message: "settings.transcriptions.empty_desc".localized,
            )
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, 48)
            .padding(.horizontal, 24)
        }
        .settingsScrollEdgeEffect()
        .subtleScrollbars()
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var transcriptionsList: some View {
        List {
            ForEach(viewModel.sortedGroupDates, id: \.self) { date in
                Section {
                    ForEach(viewModel.groupedTranscriptions[date] ?? []) { transcription in
                        HStack(alignment: .top, spacing: 12) {
                            Text(formatTime(transcription.createdAt))
                                .font(.callout)
                                .fontWeight(.medium)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .padding(.top, 14)
                                .frame(minWidth: 46, alignment: .trailing)

                            TranscriptionCardView(
                                transcription: transcription,
                                transcriptionDetail: viewModel.selectedId == transcription.id ? viewModel.selectedTranscription : nil,
                                meetingNotesPlainText: viewModel.selectedId == transcription.id
                                    ? viewModel.meetingNotesContent(for: viewModel.selectedTranscription).plainText
                                    : nil,
                                isExpanded: viewModel.selectedId == transcription.id,
                                audioURL: transcription.audioFilePath != nil ? URL(fileURLWithPath: transcription.audioFilePath!) : nil,
                                availablePrompts: viewModel.availablePrompts(for: transcription),
                                availableRetryTranscriptionOptions: viewModel.availableRetryTranscriptionOptions(for: transcription),
                                isPostProcessing: viewModel.isPostProcessing(transcriptionID: transcription.id),
                                postProcessingErrorMessage: viewModel.postProcessingError(for: transcription.id),
                                onToggleExpand: {
                                    let toggleSelection = {
                                        if viewModel.selectedId == transcription.id {
                                            viewModel.selectedId = nil
                                        } else {
                                            viewModel.selectedId = transcription.id
                                        }
                                    }

                                    withAnimation(AppleMotion.disclosureAnimation(reduceMotion: reduceMotion)) {
                                        toggleSelection()
                                    }
                                },
                                onAction: { action in
                                    handleTranscriptionAction(action, for: transcription)
                                },
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    Text(formatHeaderDate(date))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .settingsScrollEdgeEffect()
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .subtleScrollbars()
    }

    // MARK: - Conversation Page

    private func conversationPage(transcriptionID: UUID) -> some View {
        let activeTranscription = viewModel.selectedTranscription?.id == transcriptionID ? viewModel.selectedTranscription : nil

        return TranscriptionConversationPage(
            transcriptionID: transcriptionID,
            activeTranscription: activeTranscription,
            viewModel: viewModel,
            dictationService: dictationService,
            onToggleDictation: handleDictationToggle,
            onBack: {
                _ = navigationHistory.goBack()
                viewModel.selectedId = nil
                syncSelectionForCurrentRoute()
            },
        )
    }

    // MARK: - Navigation

    private func openConversation(for metadata: TranscriptionMetadata) {
        guard viewModel.canOpenMeetingConversation(for: metadata) else { return }
        navigationHistory.push(.conversation(metadata.id))
        viewModel.selectedId = metadata.id
        dictationService.clearError()
    }

    private func syncSelectionForCurrentRoute() {
        switch currentRoute {
        case .list:
            Task {
                await dictationService.cancel()
            }
        case let .conversation(transcriptionID):
            if viewModel.selectedId != transcriptionID {
                viewModel.selectedId = transcriptionID
            }
        }
    }

    private func sanitizeNavigationHistory(using transcriptions: [TranscriptionMetadata]) {
        let validIDs = Set(transcriptions.map(\.id))
        var sanitizedHistory = navigationHistory
        sanitizedHistory.sanitize(validConversationIDs: validIDs)

        guard sanitizedHistory != navigationHistory else {
            syncSelectionForCurrentRoute()
            return
        }

        DispatchQueue.main.async {
            navigationHistory = sanitizedHistory
            syncSelectionForCurrentRoute()
        }
    }

    // MARK: - Actions

    private func handleTranscriptionAction(_ action: TranscriptionCardView.TranscriptionAction, for metadata: TranscriptionMetadata) {
        switch action {
        case .askAboutMeeting:
            openConversation(for: metadata)
        case let .copy(text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case let .updateMeetingTitle(title):
            Task {
                await viewModel.updateMeetingTitle(for: metadata, to: title)
            }
        case let .updateCapturePurpose(capturePurpose):
            Task {
                await viewModel.updateCapturePurpose(for: metadata, to: capturePurpose)
            }
        case let .reprocess(prompt):
            Task {
                await viewModel.applyPostProcessing(prompt: prompt, transcriptionID: metadata.id)
            }
        case .info:
            break
        case .viewPrompt:
            break
        case let .retryTranscription(selection):
            Task {
                await viewModel.retryTranscription(for: metadata, selectionOverride: selection)
            }
        case .delete:
            viewModel.confirmDeleteTranscription(metadata)
        case let .export(kind):
            Task {
                let exportKind: TranscriptionSettingsViewModel.ManualTranscriptionExportKind = switch kind {
                case .summary:
                    .summary
                case .original:
                    .original
                }
                await viewModel.exportTranscription(for: metadata, kind: exportKind)
            }
        }
    }

    private func handleDictationToggle() {
        guard viewModel.selectedTranscription?.supportsMeetingConversation == true else {
            return
        }

        Task {
            if let transcribedText = await dictationService.toggleDictation() {
                appendDictationText(transcribedText)
            }
        }
    }

    private func appendDictationText(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        let current = viewModel.qaQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            viewModel.qaQuestion = normalized
            return
        }

        viewModel.qaQuestion = "\(current) \(normalized)"
    }

    // MARK: - Formatting

    private func formatHeaderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current

        if Calendar.current.isDateInToday(date) {
            return "settings.transcriptions.today".localized
        } else if Calendar.current.isDateInYesterday(date) {
            return "settings.transcriptions.yesterday".localized
        }

        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: date)
    }
}

// MARK: - Transcription Row View

struct TranscriptionRowView: View {
    let metadata: TranscriptionMetadata

    private var appColor: Color {
        MeetingApp(rawValue: metadata.appRawValue)?.color ?? .gray
    }

    private var appIcon: String {
        MeetingApp(rawValue: metadata.appRawValue)?.icon ?? "questionmark.circle"
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale.current
        return formatter.string(from: metadata.createdAt)
    }

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = Locale.current
        return formatter.string(from: metadata.createdAt)
    }

    private var previewText: String {
        let trimmed = metadata.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "transcription.empty_fallback".localized
        }
        return metadata.previewText
    }

    private var isFallbackText: Bool {
        metadata.previewText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(appColor.opacity(0.1))
                    .frame(width: 40, height: 40)

                AppIconView(
                    bundleIdentifier: metadata.appBundleIdentifier,
                    fallbackSystemName: appIcon,
                    size: 22,
                    cornerRadius: 5,
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.body)
                    .fontWeight(.semibold)

                Text(previewText)
                    .font(isFallbackText ? .caption.italic() : .caption)
                    .foregroundStyle(isFallbackText ? .tertiary : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(formattedTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                if metadata.isPostProcessed {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(AppDesignSystem.Colors.iconHighlight)
                }
            }
        }
        .padding(.vertical, 8)
    }
}

#Preview {
    TranscriptionsSettingsTab()
        .frame(width: 900, height: 620)
}
