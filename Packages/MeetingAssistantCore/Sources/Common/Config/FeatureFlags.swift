import Foundation

/// Feature flags for MeetingAssistant application.
/// Toggle these values to enable/disable experimental or optional features.
public enum FeatureFlags {
    /// Enables shared intelligence-kernel orchestration.
    public static let enableIntelligenceKernel: Bool = true

    /// Enables meeting mode execution through the shared intelligence kernel.
    public static let enableMeetingIntelligenceMode: Bool = true

    /// Enables dictation mode execution through the shared intelligence kernel.
    public static let enableDictationIntelligenceMode: Bool = true

    /// Enables assistant mode execution through the shared intelligence kernel.
    /// Reserved for a future phase.
    public static let enableAssistantIntelligenceMode: Bool = false

    /// Enable speaker diarization during transcription.
    /// Requires additional model downloads.
    public static let enableDiarization: Bool = true

    /// Enable cached readiness gating instead of synchronous health checks in the critical path.
    public static let enableCachedTranscriptionReadinessGate: Bool = true

    /// Enable AI post-processing for transcriptions.
    public static let enablePostProcessing: Bool = true

    /// Enable live waveform visualization during recording.
    public static let enableWaveformVisualization: Bool = false
}
