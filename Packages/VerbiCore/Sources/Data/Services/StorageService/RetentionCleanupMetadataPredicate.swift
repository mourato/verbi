import CoreData
import Foundation
import VerbiCoreCommon
import VerbiCoreDomain

// RetentionCleanup metadata predicate - Construção do predicado de consulta
// Extraído de RetentionCleanup.swift para manter o arquivo abaixo do limite de
// tamanho, sem alterar a consulta montada.

extension FileSystemStorageService {
    static func buildMetadataPredicate(for query: TranscriptionMetadataQuery) -> NSPredicate? {
        var predicates: [NSPredicate] = []

        if !query.includeNonVisibleLifecycleStates {
            let visibleStates = [TranscriptionLifecycleState.completed.rawValue, TranscriptionLifecycleState.failed.rawValue]
            predicates.append(NSPredicate(format: "lifecycleStateRawValue IN %@", visibleStates))
        }

        switch query.capturePurposeFilter {
        case .all:
            break
        case .dictations:
            predicates.append(
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "meeting.capturePurposeRawValue == %@", CapturePurpose.dictation.rawValue),
                    NSPredicate(
                        format: "meeting.capturePurposeRawValue == nil AND meeting.appRawValue == %@",
                        CaptureOrigin.unknown.rawValue
                    )
                ])
            )
        case .meetings:
            predicates.append(
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "meeting.capturePurposeRawValue == %@", CapturePurpose.meeting.rawValue),
                    NSPredicate(
                        format: "meeting.capturePurposeRawValue == nil AND meeting.appRawValue != %@",
                        CaptureOrigin.unknown.rawValue
                    )
                ])
            )
        }

        if query.dateFilter != .allEntries {
            let range = query.dateFilter.dateRange
            predicates.append(
                NSPredicate(
                    format: "createdAt >= %@ AND createdAt < %@",
                    range.start as NSDate,
                    range.end as NSDate
                )
            )
        }

        if let appRawValue = query.appRawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
           !appRawValue.isEmpty
        {
            predicates.append(NSPredicate(format: "meeting.appRawValue == %@", appRawValue))
        }

        let trimmedSearch = query.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            let searchPredicates = [
                NSPredicate(format: "text CONTAINS[cd] %@", trimmedSearch),
                NSPredicate(format: "meeting.title CONTAINS[cd] %@", trimmedSearch),
                NSPredicate(format: "meeting.appDisplayName CONTAINS[cd] %@", trimmedSearch),
                NSPredicate(format: "meeting.appRawValue CONTAINS[cd] %@", trimmedSearch)
            ]
            predicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: searchPredicates))
        }

        guard !predicates.isEmpty else { return nil }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }
}
