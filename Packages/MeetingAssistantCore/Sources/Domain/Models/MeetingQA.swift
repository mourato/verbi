import Foundation

public enum MeetingQAStatus: String, Codable, Sendable {
    case answered
    case notFound = "not_found"
}

public struct MeetingQAEvidence: Codable, Hashable, Sendable {
    public let speaker: String
    public let startTime: Double
    public let endTime: Double
    public let excerpt: String

    public init(
        speaker: String,
        startTime: Double,
        endTime: Double,
        excerpt: String
    ) {
        self.speaker = speaker
        self.startTime = startTime
        self.endTime = endTime
        self.excerpt = excerpt
    }
}

public struct MeetingQAResponse: Codable, Hashable, Sendable {
    public let status: MeetingQAStatus
    public let answer: String
    public let evidence: [MeetingQAEvidence]

    public init(
        status: MeetingQAStatus,
        answer: String,
        evidence: [MeetingQAEvidence] = []
    ) {
        self.status = status
        self.answer = answer
        self.evidence = evidence
    }

    public static var notFound: MeetingQAResponse {
        MeetingQAResponse(status: .notFound, answer: "", evidence: [])
    }
}

public enum MeetingQAError: LocalizedError, Sendable {
    case disabled
    case emptyQuestion
    case noAPIConfigured
    case invalidURL
    case timeout
    case networkUnavailable
    case invalidResponse
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .disabled:
            "Meeting Q&A is disabled."
        case .emptyQuestion:
            "Question must not be empty."
        case .noAPIConfigured:
            "AI provider is not configured."
        case .invalidURL:
            "AI provider URL is invalid."
        case .timeout:
            "Request timed out."
        case .networkUnavailable:
            "Network is unavailable."
        case .invalidResponse:
            "Provider returned an invalid response."
        case let .requestFailed(message):
            "Request failed: \(message)"
        }
    }
}
