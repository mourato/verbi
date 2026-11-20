import Foundation

public enum FeatureFlags {
    public static let enableIntelligenceKernel: Bool = true

    public static let enableMeetingIntelligenceMode: Bool = true

    public static let enableDictationIntelligenceMode: Bool = true

    public static let enableAssistantIntelligenceMode: Bool = false

    public static let enableDiarization: Bool = true

    public static let enableCachedTranscriptionReadinessGate: Bool = true

    public static let enablePostProcessing: Bool = true

    public static let enableWaveformVisualization: Bool = false
}
