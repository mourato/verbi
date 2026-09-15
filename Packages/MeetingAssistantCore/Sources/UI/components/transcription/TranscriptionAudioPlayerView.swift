import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import SwiftUI

/// Audio player component for transcriptions with waveform and playback controls.
public struct TranscriptionAudioPlayerView: View {
    private enum Layout {
        static let fixedWidth: CGFloat = 256
    }

    @StateObject private var viewModel = AudioPlayerViewModel()
    @State private var isScrubbing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let audioURL: URL?

    public init(audioURL: URL?) {
        self.audioURL = audioURL
    }

    public var body: some View {
        HStack(spacing: 12) {
            // Play/Pause Button
            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.pressable)
            .labelStyle(.iconOnly)
            .accessibilityLabel(
                (viewModel.isPlaying
                    ? "transcription.audio.pause.accessibility"
                    : "transcription.audio.play.accessibility").localized
            )
            .disabled(audioURL == nil)

            // Waveform and Progress Interaction
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background Waveform
                    AudioWaveformView(
                        samples: viewModel.samples,
                        progress: viewModel.currentTime / max(viewModel.duration, 1),
                        color: isScrubbing ? .primary : .secondary
                    )
                    .scaleEffect(reduceMotion || !isScrubbing ? 1 : 1.03)
                    .opacity(isScrubbing ? 1 : 0.82)
                    .animation(
                        AppleMotion.animation(reduceMotion: reduceMotion, kind: .press),
                        value: isScrubbing
                    )
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isScrubbing = true
                                viewModel.seek(to: clampedProgress(for: value.location.x, width: geometry.size.width))
                            }
                            .onEnded { value in
                                viewModel.seek(to: clampedProgress(for: value.location.x, width: geometry.size.width))
                                isScrubbing = false
                            }
                    )
                }
            }
            .frame(height: AppDesignSystem.Layout.compactButtonHeight)

            // Duration
            Text(formatTime(viewModel.duration - viewModel.currentTime))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: AppDesignSystem.Layout.cardCornerRadius))
        .frame(width: Layout.fixedWidth)
        .onAppear {
            if let url = audioURL {
                viewModel.loadAudio(url: url)
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return "\(minutes):\(seconds.formatted(.number.precision(.integerLength(2))))"
    }

    private func clampedProgress(for locationX: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(max(0, min(1, locationX / width)))
    }
}

#Preview {
    TranscriptionAudioPlayerView(audioURL: nil)
        .padding()
        .frame(width: 400)
}
