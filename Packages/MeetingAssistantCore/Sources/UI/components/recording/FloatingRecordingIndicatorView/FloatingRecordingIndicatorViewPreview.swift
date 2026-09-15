import MeetingAssistantCoreAudio
import MeetingAssistantCoreInfrastructure
import SwiftUI

#Preview("Classic - Ditado", traits: .sizeThatFitsLayout) {
    let monitor = AudioLevelMonitor()
    FloatingRecordingIndicatorView(
        audioMonitor: monitor,
        style: .classic,
        renderState: RecordingIndicatorRenderState(mode: .recording, kind: .dictation),
        previewLanguageOverride: .portuguese,
        onStop: {},
        onCancel: {}
    )
    .padding()
    .frame(width: 520, height: 120)
    .background(AppDesignSystem.Colors.neutral.opacity(0.8))
}

#Preview("Classic - Assistente", traits: .sizeThatFitsLayout) {
    let monitor = AudioLevelMonitor()
    FloatingRecordingIndicatorView(
        audioMonitor: monitor,
        style: .classic,
        renderState: RecordingIndicatorRenderState(mode: .recording, kind: .assistant),
        previewLanguageOverride: .portuguese,
        onStop: {},
        onCancel: {}
    )
    .padding()
    .frame(width: 520, height: 120)
    .background(AppDesignSystem.Colors.neutral.opacity(0.8))
}

#Preview("Classic - Reuniao", traits: .sizeThatFitsLayout) {
    let monitor = AudioLevelMonitor()
    FloatingRecordingIndicatorView(
        audioMonitor: monitor,
        style: .classic,
        renderState: RecordingIndicatorRenderState(mode: .recording, kind: .meeting),
        previewLanguageOverride: .portuguese,
        onStop: {},
        onCancel: {}
    )
    .padding()
    .frame(width: 520, height: 120)
    .background(AppDesignSystem.Colors.neutral.opacity(0.8))
}

#Preview("Super - Ditado", traits: .sizeThatFitsLayout) {
    let monitor = AudioLevelMonitor()
    FloatingRecordingIndicatorView(
        audioMonitor: monitor,
        style: .super,
        renderState: RecordingIndicatorRenderState(mode: .recording, kind: .dictation),
        previewLanguageOverride: .portuguese,
        onStop: {},
        onCancel: {}
    )
    .padding()
    .frame(width: 560, height: 180)
    .background(AppDesignSystem.Colors.neutral.opacity(0.8))
}

#Preview("Super - Assistente", traits: .sizeThatFitsLayout) {
    let monitor = AudioLevelMonitor()
    FloatingRecordingIndicatorView(
        audioMonitor: monitor,
        style: .super,
        renderState: RecordingIndicatorRenderState(mode: .recording, kind: .assistant),
        previewLanguageOverride: .portuguese,
        onStop: {},
        onCancel: {}
    )
    .padding()
    .frame(width: 560, height: 180)
    .background(AppDesignSystem.Colors.neutral.opacity(0.8))
}

#Preview("Super - Reuniao", traits: .sizeThatFitsLayout) {
    let monitor = AudioLevelMonitor()
    FloatingRecordingIndicatorView(
        audioMonitor: monitor,
        style: .super,
        renderState: RecordingIndicatorRenderState(mode: .recording, kind: .meeting),
        previewLanguageOverride: .portuguese,
        onStop: {},
        onCancel: {}
    )
    .padding()
    .frame(width: 640, height: 180)
    .background(AppDesignSystem.Colors.neutral.opacity(0.8))
}
