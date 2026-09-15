import Foundation
import MeetingAssistantCoreAudio

extension RecordingManager {
    func shouldRemoveSilenceBeforeTranscription(for session: TranscriptionSessionSnapshot) -> Bool {
        audioPreparationService.shouldRemoveSilenceBeforeTranscription(capturePurpose: session.meeting.capturePurpose)
    }

    func prepareAudioForTranscription(
        audioURL: URL,
        allowSilenceRemoval: Bool
    ) async -> PreparedTranscriptionAudio {
        await audioPreparationService.prepareAudioForTranscription(
            audioURL: audioURL,
            allowSilenceRemoval: allowSilenceRemoval
        )
    }

    func cleanupPreparedTranscriptionAudio(_ preparedAudio: PreparedTranscriptionAudio) {
        audioPreparationService.cleanupPreparedTranscriptionAudio(preparedAudio)
    }
}
