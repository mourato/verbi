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
    /// Enable XPC Service for transcription processing.
    /// When true: Uses MeetingAssistantAIClient (XPC) for heavy AI processing.
    /// When false: Uses LocalTranscriptionClient directly in the main app process.
    ///
    /// Benefits of XPC:
    /// - Process isolation (crashes don't affect main app)
    /// - Memory isolation (models don't bloat main app memory)
    /// - Sandboxed execution for security
    ///
    /// Drawbacks of XPC:
    /// - IPC overhead (serialization/deserialization)
    /// - More complex debugging
    /// - Additional build configuration
    public static let useXPCService: Bool = false

    public static let enableWaveformVisualization: Bool = false
}
