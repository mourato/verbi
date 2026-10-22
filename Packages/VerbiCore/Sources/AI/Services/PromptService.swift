import Foundation
import VerbiCoreDomain

/// Service factory to retrieve the correct prompt strategy for a given meeting type.
public final class PromptService: Sendable {
    public static let shared = PromptService()

    private init() {}

    /// Returns the appropriate strategy for the meeting type.
    /// - Parameter type: The type of meeting.
    /// - Returns: A matching PromptStrategy.
    public func strategy(for type: SummaryStrategy) -> PromptStrategy {
        switch type {
        case .standup:
            StandupMeetingStrategy()
        case .designReview:
            DesignReviewStrategy()
        case .general, .autodetect, .oneOnOne, .presentation, .planning:
            // For now, map others to General until specific strategies are implemented
            GeneralMeetingStrategy()
        }
    }
}
