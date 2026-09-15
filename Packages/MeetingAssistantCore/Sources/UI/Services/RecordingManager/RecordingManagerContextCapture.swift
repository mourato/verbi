import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

extension RecordingManager {
    func capturePostProcessingContext(
        for meeting: Meeting,
        includeWindowOCR: Bool? = nil
    ) async -> (context: String?, items: [TranscriptionContextItem]) {
        let settings = AppSettingsStore.shared
        let activeTabURL = activeBrowserURL(for: meeting.appBundleIdentifier)?.absoluteString
        let contextSourcePolicy = effectiveContextSourcePolicy(
            for: meeting,
            settings: settings,
            activeTabURL: activeTabURL
        )
        let calendarContext = meeting.supportsMeetingConversation
            ? meeting.linkedCalendarEvent.map(calendarContextBlock(for:))
            : nil

        return await contextCaptureService.capturePostProcessingContext(
            for: meeting,
            settings: settings,
            activeTabURL: activeTabURL,
            calendarContext: calendarContext,
            isDictationMode: isDictationMode(for: meeting),
            contextSourcePolicy: contextSourcePolicy,
            includeWindowOCR: includeWindowOCR
        )
    }

    func cancelPostStartCaptureTasks() {
        postStartContextCaptureTask?.cancel()
        postStartContextCaptureTask = nil
        postStartWindowOCRCaptureTask?.cancel()
        postStartWindowOCRCaptureTask = nil
    }

    func startContextCaptureAfterRecordingStart(meetingID: UUID) {
        cancelPostStartCaptureTasks()
        postStartContextCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let contextCaptureStartAt = Date()
            guard !Task.isCancelled else { return }
            guard let meeting = currentMeeting, meeting.id == meetingID else { return }

            let captureResult = await capturePostProcessingContextWithTimeout(
                for: meeting,
                includeWindowOCR: false
            )
            guard !Task.isCancelled else { return }
            guard currentMeeting?.id == meetingID else { return }

            postProcessingContext = mergedContext(
                existing: postProcessingContext,
                incoming: captureResult.context
            )
            postProcessingContextItems = mergedContextItems(
                existing: postProcessingContextItems,
                incoming: captureResult.items
            )

            if captureResult.didTimeout {
                AppLogger.warning(
                    "Context capture timed out after recording start",
                    category: .recordingManager
                )
            }

            PerformanceMonitor.shared.reportMetric(
                name: "recording_start_context_capture_ms",
                value: Date().timeIntervalSince(contextCaptureStartAt) * 1000,
                unit: "ms"
            )
        }

        startWindowOCRCaptureAfterRecordingStartIfNeeded(meetingID: meetingID)
    }

    private func capturePostProcessingContextWithTimeout(
        for meeting: Meeting,
        includeWindowOCR: Bool? = nil
    ) async -> PostProcessingContextCaptureResult {
        let settings = AppSettingsStore.shared
        let activeTabURL = activeBrowserURL(for: meeting.appBundleIdentifier)?.absoluteString
        let activeURL = activeTabURL.flatMap(URL.init(string:))
        let contextSourcePolicy = meeting.capturePurpose == .dictation
            ? settings.effectiveDictationStyle(
                bundleIdentifier: meeting.appBundleIdentifier,
                activeURL: activeURL
            ).contextSourcePolicy
            : nil
        let calendarContext = meeting.supportsMeetingConversation
            ? meeting.linkedCalendarEvent.map(calendarContextBlock(for:))
            : nil

        return await contextCaptureService.capturePostProcessingContextWithTimeout(
            for: meeting,
            settings: settings,
            activeTabURL: activeTabURL,
            calendarContext: calendarContext,
            isDictationMode: isDictationMode(for: meeting),
            contextSourcePolicy: contextSourcePolicy,
            includeWindowOCR: includeWindowOCR,
            timeoutNanoseconds: Constants.startContextCaptureTimeout
        )
    }

    private func startWindowOCRCaptureAfterRecordingStartIfNeeded(meetingID: UUID) {
        postStartWindowOCRCaptureTask?.cancel()

        let settings = AppSettingsStore.shared
        guard let meeting = currentMeeting else {
            postStartWindowOCRCaptureTask = nil
            return
        }

        let activeTabURL = activeBrowserURL(for: meeting.appBundleIdentifier)?.absoluteString
        let contextSourcePolicy = effectiveContextSourcePolicy(
            for: meeting,
            settings: settings,
            activeTabURL: activeTabURL
        )
        let includeWindowOCR = contextSourcePolicy?.includeWindowOCR ?? settings.contextAwarenessIncludeWindowOCR
        guard includeWindowOCR else {
            postStartWindowOCRCaptureTask = nil
            return
        }

        postStartWindowOCRCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard isRecording, let meeting = currentMeeting, meeting.id == meetingID else { return }

            let captureResult = await capturePostProcessingContextWithTimeout(
                for: meeting,
                includeWindowOCR: true
            )

            guard !Task.isCancelled else { return }
            guard isRecording, currentMeeting?.id == meetingID else { return }
            guard let ocrItem = captureResult.items.first(where: { $0.source == .windowOCR }) else { return }

            var updatedItems = postProcessingContextItems
            let alreadyPresent = updatedItems.contains {
                $0.source == .windowOCR && $0.text == ocrItem.text
            }

            guard !alreadyPresent else { return }

            updatedItems.append(ocrItem)
            postProcessingContextItems = updatedItems

            let ocrContext = """
            <WINDOW_OCR_CONTEXT>
            \(ocrItem.text)
            </WINDOW_OCR_CONTEXT>
            """
            postProcessingContext = mergedContext(
                existing: postProcessingContext,
                incoming: ocrContext
            )

            AppLogger.debug(
                "Deferred OCR context capture appended",
                category: .recordingManager,
                extra: ["meetingID": meetingID.uuidString]
            )
        }
    }

    private func effectiveContextSourcePolicy(
        for meeting: Meeting,
        settings: AppSettingsStore,
        activeTabURL: String?
    ) -> DictationContextSourcePolicy? {
        guard meeting.capturePurpose == .dictation else { return nil }

        return settings.effectiveDictationStyle(
            bundleIdentifier: meeting.appBundleIdentifier,
            activeURL: activeTabURL.flatMap(URL.init(string:))
        ).contextSourcePolicy
    }

    private func mergedContext(existing: String?, incoming: String?) -> String? {
        let existingBody = contextBody(existing)
        let incomingBody = contextBody(incoming)
        let bodies = [existingBody, incomingBody].filter { !$0.isEmpty }
        guard !bodies.isEmpty else { return nil }
        return "CONTEXT_METADATA\n" + bodies.joined(separator: "\n")
    }

    private func contextBody(_ context: String?) -> String {
        guard let context else { return "" }
        var lines = context.components(separatedBy: .newlines)
        while let first = lines.first, first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.removeFirst()
        }
        if let first = lines.first,
           first.trimmingCharacters(in: .whitespacesAndNewlines)
           .compare("CONTEXT_METADATA", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        {
            lines.removeFirst()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func mergedContextItems(
        existing: [TranscriptionContextItem],
        incoming: [TranscriptionContextItem]
    ) -> [TranscriptionContextItem] {
        var merged = existing
        for item in incoming where !merged.contains(where: { $0.source == item.source && $0.text == item.text }) {
            merged.append(item)
        }

        if let selectedIndex = merged.firstIndex(where: { $0.source == .selectedTextAtStart }), selectedIndex > 0 {
            let selectedItem = merged.remove(at: selectedIndex)
            merged.insert(selectedItem, at: 0)
        }
        return merged
    }
}
