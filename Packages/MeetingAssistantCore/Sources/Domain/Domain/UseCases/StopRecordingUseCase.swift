// StopRecordingUseCase - Caso de uso para parar gravação

import Foundation

/// Caso de uso para parar gravação de reunião
public final class StopRecordingUseCase {
    private let recordingRepository: RecordingRepository
    private let meetingRepository: MeetingRepository

    /// Inicializa o caso de uso com dependências
    public init(
        recordingRepository: RecordingRepository,
        meetingRepository: MeetingRepository
    ) {
        self.recordingRepository = recordingRepository
        self.meetingRepository = meetingRepository
    }

    /// Executa o caso de uso para parar gravação
    /// - Parameter meeting: Reunião para a qual parar gravação
    /// - Returns: URL do arquivo de áudio gravado
    /// - Throws: RecordingError se não conseguir parar gravação
    public func execute(for meeting: MeetingEntity) async throws -> URL {
        // Parar gravação
        guard let audioFileURL = try await recordingRepository.stopRecording() else {
            throw RecordingError.recordingFailed(NSError(domain: "StopRecordingUseCase", code: -1, userInfo: [NSLocalizedDescriptionKey: "No recording file URL returned"]))
        }

        // Atualizar reunião com horário de fim
        var updatedMeeting = meeting
        updatedMeeting.endTime = Date()
        try await meetingRepository.updateMeeting(updatedMeeting)

        return audioFileURL
    }
}
