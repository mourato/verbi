import Foundation
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain

enum TranscriptionHistoryFilterEngine {
    struct FilterConfiguration {
        let capturePurposeFilter: CapturePurposeFilter
        let dateFilter: DateFilter
        let searchText: String
        let appFilterId: String
        let allAppsId: String
        let rawAppPrefix: String
        let bundleAppPrefix: String
        let nameAppPrefix: String
    }

    static func filteredTranscriptions(
        from transcriptions: [TranscriptionMetadata],
        configuration: FilterConfiguration
    ) -> [TranscriptionMetadata] {
        let selectedAppScope = selectedAppFilterScope(
            appFilterId: configuration.appFilterId,
            allAppsId: configuration.allAppsId,
            rawAppPrefix: configuration.rawAppPrefix,
            bundleAppPrefix: configuration.bundleAppPrefix,
            nameAppPrefix: configuration.nameAppPrefix
        )

        return transcriptions.filter { transcription in
            let matchesCapturePurpose = matchesCapturePurposeFilter(transcription, capturePurposeFilter: configuration.capturePurposeFilter)
            let matchesDate = configuration.dateFilter.contains(transcription.createdAt)
            let matchesApp = matchesAppFilter(transcription, scope: selectedAppScope)
            let matchesText = matchesSearchFilter(transcription, searchText: configuration.searchText)
            return matchesCapturePurpose && matchesDate && matchesApp && matchesText
        }
    }

    static func appFilterOptions(
        from transcriptions: [TranscriptionMetadata],
        allAppsId: String,
        rawAppPrefix: String,
        bundleAppPrefix: String,
        nameAppPrefix: String
    ) -> [TranscriptionLibraryViewModel.AppFilterOption] {
        let optionsById = transcriptions.reduce(into: [String: TranscriptionLibraryViewModel.AppFilterOption]()) {
            result,
            transcription in
            guard let option = appFilterOption(
                for: transcription,
                rawAppPrefix: rawAppPrefix,
                bundleAppPrefix: bundleAppPrefix,
                nameAppPrefix: nameAppPrefix
            ) else {
                return
            }
            result[option.id] = option
        }

        let allAppsOption = TranscriptionLibraryViewModel.AppFilterOption(
            id: allAppsId,
            scope: .all,
            displayName: "settings.transcriptions.filter_app_all".localized
        )

        let sortedAppOptions = optionsById.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        return [allAppsOption] + sortedAppOptions
    }

    static func matchesCapturePurposeFilter(
        _ transcription: TranscriptionMetadata,
        capturePurposeFilter: CapturePurposeFilter
    ) -> Bool {
        switch capturePurposeFilter {
        case .all:
            true
        case .dictations:
            transcription.capturePurpose == .dictation
        case .meetings:
            transcription.capturePurpose == .meeting
        }
    }

    private static func matchesAppFilter(
        _ transcription: TranscriptionMetadata,
        scope: TranscriptionLibraryViewModel.AppFilterOption.Scope
    ) -> Bool {
        switch scope {
        case .all:
            return true
        case let .appRawValue(appRawValue):
            return transcription.appRawValue == appRawValue
        case let .appBundleIdentifier(bundleIdentifier):
            let transcriptionBundleIdentifier = transcription.appBundleIdentifier?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return transcriptionBundleIdentifier == bundleIdentifier
        case let .appDisplayName(displayName):
            return normalizedFilterValue(appDisplayName(for: transcription)) == displayName
        }
    }

    private static func selectedAppFilterScope(
        appFilterId: String,
        allAppsId: String,
        rawAppPrefix: String,
        bundleAppPrefix: String,
        nameAppPrefix: String
    ) -> TranscriptionLibraryViewModel.AppFilterOption.Scope {
        guard appFilterId != allAppsId else { return .all }

        if appFilterId.hasPrefix(rawAppPrefix) {
            let rawValue = String(appFilterId.dropFirst(rawAppPrefix.count))
            return rawValue.isEmpty ? .all : .appRawValue(rawValue)
        }

        if appFilterId.hasPrefix(bundleAppPrefix) {
            let bundleIdentifier = String(appFilterId.dropFirst(bundleAppPrefix.count))
            return bundleIdentifier.isEmpty ? .all : .appBundleIdentifier(bundleIdentifier)
        }

        if appFilterId.hasPrefix(nameAppPrefix) {
            let displayName = String(appFilterId.dropFirst(nameAppPrefix.count))
            return displayName.isEmpty ? .all : .appDisplayName(displayName)
        }

        return .all
    }

    private static func matchesSearchFilter(_ transcription: TranscriptionMetadata, searchText: String) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }

        let normalizedQuery = normalizedFilterValue(query)
        let meetingTitle = if transcription.capturePurpose.supportsMeetingConversation {
            transcription.meetingTitle ?? ""
        } else {
            ""
        }

        let searchableFields = [
            transcription.previewText,
            transcription.appName,
            meetingTitle
        ]

        return searchableFields.contains { normalizedFilterValue($0).contains(normalizedQuery) }
    }

    private static func appFilterOption(
        for transcription: TranscriptionMetadata,
        rawAppPrefix: String,
        bundleAppPrefix: String,
        nameAppPrefix: String
    ) -> TranscriptionLibraryViewModel.AppFilterOption? {
        let rawValue = transcription.appRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = appDisplayName(for: transcription)

        if !rawValue.isEmpty, rawValue != CaptureOrigin.unknown.rawValue {
            return TranscriptionLibraryViewModel.AppFilterOption(
                id: rawAppPrefix + rawValue,
                scope: .appRawValue(rawValue),
                displayName: displayName
            )
        }

        let bundleIdentifier = transcription.appBundleIdentifier?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return TranscriptionLibraryViewModel.AppFilterOption(
                id: bundleAppPrefix + bundleIdentifier,
                scope: .appBundleIdentifier(bundleIdentifier),
                displayName: displayName
            )
        }

        let normalizedDisplayName = normalizedFilterValue(displayName)
        guard !normalizedDisplayName.isEmpty else { return nil }
        return TranscriptionLibraryViewModel.AppFilterOption(
            id: nameAppPrefix + normalizedDisplayName,
            scope: .appDisplayName(normalizedDisplayName),
            displayName: displayName
        )
    }

    private static func appDisplayName(for transcription: TranscriptionMetadata) -> String {
        let trimmedName = transcription.appName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }

        if let knownApp = CaptureOrigin(rawValue: transcription.appRawValue) {
            return knownApp.displayName
        }

        let trimmedRawValue = transcription.appRawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedRawValue.isEmpty ? CaptureOrigin.unknown.displayName : trimmedRawValue
    }

    private static func normalizedFilterValue(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
    }
}
