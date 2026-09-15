// StartRecordingUseCase - Caso de uso para iniciar gravação

import Foundation

/// Caso de uso para iniciar gravação de reunião
public final class StartRecordingUseCase {
    private let recordingRepository: RecordingRepository
    private let audioFileRepository: AudioFileRepository
    private let meetingRepository: MeetingRepository

    /// Inicializa o caso de uso com dependências
    public init(
        recordingRepository: RecordingRepository,
        audioFileRepository: AudioFileRepository,
        meetingRepository: MeetingRepository
    ) {
        self.recordingRepository = recordingRepository
        self.audioFileRepository = audioFileRepository
        self.meetingRepository = meetingRepository
    }

    /// Executa o caso de uso para iniciar gravação
    /// - Parameter meeting: Reunião para a qual iniciar gravação
    /// - Returns: URL do arquivo de áudio onde será gravado
    /// - Throws: RecordingError se não conseguir iniciar gravação
    public func execute(for meeting: MeetingEntity) async throws -> URL {
        // Verificar permissões
        guard await recordingRepository.hasPermission() else {
            throw RecordingError.permissionDenied
        }

        // Gerar URL para arquivo de áudio
        let audioFileURL = audioFileRepository.generateAudioFileURL(for: meeting.id)

        // Iniciar gravação
        do {
            try await recordingRepository.startRecording(to: audioFileURL, retryCount: 3)
        } catch {
            throw RecordingError.recordingFailed(error)
        }

        // Atualizar reunião com caminho do arquivo de áudio
        var updatedMeeting = meeting
        updatedMeeting.audioFilePath = audioFileURL.path
        try await meetingRepository.updateMeeting(updatedMeeting)

        return audioFileURL
    }
}

/// Erros específicos do caso de uso de gravação
public enum RecordingError: Error {
    case permissionDenied
    case recordingFailed(Error)
    case invalidMeeting
    case fileCreationFailed
}
