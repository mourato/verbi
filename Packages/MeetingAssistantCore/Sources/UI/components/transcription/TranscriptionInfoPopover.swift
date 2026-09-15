import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Popover view displaying detailed metadata about a transcription.
struct TranscriptionInfoPopover: View {
    let transcription: Transcription

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("transcription.info.title".localized)
                .font(.headline)
                .padding(.bottom, 4)

            sourceSection

            if let linkedEvent = transcription.meeting.linkedCalendarEvent {
                VStack(alignment: .leading, spacing: 8) {
                    Text("transcription.info.calendar_event".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    InfoRow(
                        icon: "calendar",
                        label: linkedEvent.trimmedTitle.isEmpty ? "metrics.calendar.event.untitled".localized : linkedEvent.trimmedTitle,
                        value: calendarIntervalLabel(for: linkedEvent)
                    )

                    if let location = linkedEvent.location?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
                        InfoRow(
                            icon: "mappin.and.ellipse",
                            label: location,
                            value: "\(linkedEvent.attendees.count)"
                        )
                    }
                }

                Divider()
            }

            // Recording Section
            VStack(alignment: .leading, spacing: 8) {
                Text("transcription.info.recording".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                InfoRow(
                    icon: "mic.fill",
                    label: transcription.inputSource ?? "transcription.info.unknown_input".localized,
                    value: formatDuration(transcription.meeting.duration)
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("transcription.info.transcription".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                InfoRow(
                    icon: "waveform",
                    label: transcription.modelName,
                    value: formatDuration(transcription.transcriptionDuration)
                )
            }

            Divider()

            // Post-Processing Section (if available)
            if let processedModel = transcription.postProcessingModel {
                VStack(alignment: .leading, spacing: 8) {
                    Text("transcription.info.post_processing".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    InfoRow(icon: "sparkles", label: processedModel, value: formatDuration(transcription.postProcessingDuration))
                }
            } else {
                Text("transcription.info.no_post_processing".localized)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(width: 300)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("settings.transcriptions.source".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                AppIconView(
                    bundleIdentifier: transcription.meeting.appBundleIdentifier,
                    fallbackSystemName: transcription.meeting.appIcon,
                    size: 18,
                    cornerRadius: 4
                )
                Text(sourceDisplayName)
                    .font(.subheadline)
                Spacer()
                if sourceValueIsPlaceholder {
                    Text(sourceValue)
                        .font(.subheadline)
                        .italic()
                        .foregroundStyle(.tertiary)
                } else {
                    Text(sourceValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var sourceDisplayName: String {
        transcription.meeting.appName
    }

    private var sourceValue: String {
        guard isBrowserSource else {
            return "transcription.info.url_not_captured".localized
        }

        return browserSite ?? "transcription.info.url_not_captured".localized
    }

    private var sourceValueIsPlaceholder: Bool {
        sourceValue == "transcription.info.url_not_captured".localized
    }

    private var isBrowserSource: Bool {
        guard let bundleID = transcription.meeting.appBundleIdentifier?.lowercased() else {
            return false
        }

        let configuredBrowsers = Set(
            AppSettingsStore.shared
                .effectiveWebTargetBrowserBundleIdentifiers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )

        return configuredBrowsers.contains(bundleID)
            || bundleID == "com.google.chrome"
            || bundleID == "com.apple.safari"
            || bundleID == "com.microsoft.edgemac"
            || bundleID == "company.thebrowser.browser"
            || bundleID == "com.brave.browser"
            || bundleID == "com.operasoftware.opera"
            || bundleID == "com.vivaldi.vivaldi"
            || bundleID == "com.operasoftware.operanext"
            || bundleID == "org.mozilla.firefox"
    }

    private var browserSite: String? {
        for source in prioritizedBrowserSources {
            for item in transcription.contextItems where item.source == source {
                if let host = extractHost(from: item.text) {
                    return host
                }
            }
        }

        return nil
    }

    private var prioritizedBrowserSources: [TranscriptionContextItem.Source] {
        [.activeTabURL, .windowTitle, .focusedText, .accessibilityText]
    }

    private func extractHost(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            let range = NSRange(trimmed.startIndex ..< trimmed.endIndex, in: trimmed)
            if let match = detector.matches(in: trimmed, options: [], range: range).first,
               let matchedRange = Range(match.range, in: trimmed)
            {
                let candidate = String(trimmed[matchedRange])
                if let host = host(from: candidate) {
                    return host
                }
            }
        }

        if let host = host(from: trimmed) {
            return host
        }

        let candidates = trimmed.components(separatedBy: .whitespacesAndNewlines)
        for candidate in candidates {
            let cleaned = candidate.trimmingCharacters(in: .punctuationCharacters)

            if let host = host(from: cleaned) {
                return host
            }
        }

        return nil
    }

    private func host(from value: String) -> String? {
        let lowercased = value.lowercased()
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if lowercased.hasPrefix("http://") || lowercased.hasPrefix("https://"),
           let url = URL(string: normalizedValue),
           let host = url.host
        {
            return normalizeHost(host)
        }

        if let url = URL(string: "https://\(normalizedValue)"),
           let host = url.host,
           host.contains(".")
        {
            return normalizeHost(host)
        }

        return nil
    }

    private func normalizeHost(_ host: String) -> String {
        let lowered = host.lowercased()
        if lowered.hasPrefix("www.") {
            return String(lowered.dropFirst(4))
        }
        return lowered
    }

    private func formatDuration(_ duration: Double) -> String {
        if duration <= 0 {
            return "-"
        }
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }

        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = .pad

        return formatter.string(from: duration) ?? String(format: "%.0fs", duration)
    }

    private func calendarIntervalLabel(for event: MeetingCalendarEventSnapshot) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: event.startDate, to: event.endDate)
    }
}

private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.primary)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)

            Spacer()

            Text(value)
                .font(.subheadline) // Monospaced for numbers?
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    TranscriptionInfoPopover(
        transcription: Transcription(
            meeting: Meeting(app: .zoom),
            contextItems: [
                .init(source: .activeApp, text: "Zoom"),
                .init(source: .clipboard, text: "Agenda: roadmap review and next steps.")
            ],
            text: "Preview text",
            rawText: "Raw text",
            modelName: "Whisper-v3",
            inputSource: "MacBook Pro Mic",
            transcriptionDuration: 35.5,
            postProcessingDuration: 2.1,
            postProcessingModel: "GPT-4"
        )
    )
}
