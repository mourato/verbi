import Foundation
import VerbiCoreDomain

public final class PromptService: Sendable {
    public static let shared = PromptService()

    private init() {}

    public func strategy(for type: SummaryStrategy) -> PromptStrategy {
        switch type {
        case .standup:
            StandupMeetingStrategy()
        case .designReview:
            DesignReviewStrategy()
        case .general, .autodetect, .oneOnOne, .presentation, .planning:
            GeneralMeetingStrategy()
        }
    }
}
