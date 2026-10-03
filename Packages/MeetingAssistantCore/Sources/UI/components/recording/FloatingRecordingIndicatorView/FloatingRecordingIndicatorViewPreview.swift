import MeetingAssistantCoreAudio
import MeetingAssistantCoreInfrastructure
import SwiftUI

#Preview("Recording - Ditado", traits: .sizeThatFitsLayout) {
    let monitor = AudioLevelMonitor()
    FloatingRecordingIndicatorView(
        audioMonitor: monitor,
        renderState: RecordingIndicatorRenderState(mode: .recording, kind: .dictation),
        previewLanguageOverride: .portuguese,
        onStop: {},
        onCancel: {}
    )
    .padding()
    .frame(width: 520, height: 120)
    .background(AppDesignSystem.Colors.neutral.opacity(0.8))
}

#Preview("Recording - Assistente", traits: .sizeThatFitsLayout) {
    let monitor = AudioLevelMonitor()
    FloatingRecordingIndicatorView(
        audioMonitor: monitor,
        renderState: RecordingIndicatorRenderState(mode: .recording, kind: .assistant),
        previewLanguageOverride: .portuguese,
        onStop: {},
        onCancel: {}
    )
    .padding()
    .frame(width: 520, height: 120)
    .background(AppDesignSystem.Colors.neutral.opacity(0.8))
}

#Preview("Recording - Reuniao", traits: .sizeThatFitsLayout) {
    let monitor = AudioLevelMonitor()
    FloatingRecordingIndicatorView(
        audioMonitor: monitor,
        renderState: RecordingIndicatorRenderState(mode: .recording, kind: .meeting),
        previewLanguageOverride: .portuguese,
        onStop: {},
        onCancel: {}
    )
    .padding()
    .frame(width: 520, height: 120)
    .background(AppDesignSystem.Colors.neutral.opacity(0.8))
}
