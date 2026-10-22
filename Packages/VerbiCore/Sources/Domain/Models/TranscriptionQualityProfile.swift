import Foundation

/// Quality and uncertainty signals derived from transcript preprocessing.
public struct TranscriptionQualityProfile: Codable, Hashable, Sendable {
    public static let currentNormalizationVersion = 1

    public let normalizedTextForIntelligence: String
    public let overallConfidence: Double
    public let containsUncertainty: Bool
    public let markers: [UncertaintyMarker]
    public let normalizationVersion: Int

    public init(
        normalizedTextForIntelligence: String,
        overallConfidence: Double,
        containsUncertainty: Bool,
        markers: [UncertaintyMarker],
        normalizationVersion: Int = Self.currentNormalizationVersion
    ) {
        self.normalizedTextForIntelligence = normalizedTextForIntelligence
        self.overallConfidence = min(1, max(0, overallConfidence))
        self.containsUncertainty = containsUncertainty
        self.markers = markers
        self.normalizationVersion = normalizationVersion
    }
}

public extension TranscriptionQualityProfile {
    struct UncertaintyMarker: Codable, Hashable, Sendable {
        public let snippet: String
        public let startTime: Double
        public let endTime: Double
        public let reason: UncertaintyReason

        public init(
            snippet: String,
            startTime: Double = 0,
            endTime: Double = 0,
            reason: UncertaintyReason
        ) {
            self.snippet = snippet
            self.startTime = startTime
            self.endTime = endTime
            self.reason = reason
        }
    }

    enum UncertaintyReason: String, Codable, Hashable, Sendable {
        case missingConfidence
        case lowASRConfidence
        case veryLowASRConfidence
        case lexicalUncertainty
    }
}
