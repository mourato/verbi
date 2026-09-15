// ImportAudioUseCase - Caso de uso para importar arquivo de áudio

import Foundation

/// Caso de uso para importar arquivo de áudio externo
public final class ImportAudioUseCase {
    private let audioFileRepository: AudioFileRepository
    private let meetingRepository: MeetingRepository

    /// Inicializa o caso de uso com dependências
    public init(
        audioFileRepository: AudioFileRepository,
        meetingRepository: MeetingRepository
    ) {
        self.audioFileRepository = audioFileRepository
        self.meetingRepository = meetingRepository
    }

    /// Executa o caso de uso para importar áudio
    /// - Parameters:
    ///   - sourceURL: URL do arquivo de áudio a importar
    ///   - meetingTitle: Título opcional para a reunião (padrão: nome do arquivo)
    ///   - capturePurpose: Classificação explícita do conteúdo importado
    /// - Returns: Tupla com entidade de reunião criada e URL do arquivo copiado
    /// - Throws: ImportError se falhar na importação
    public func execute(
        sourceURL: URL,
        meetingTitle: String? = nil,
        capturePurpose: CapturePurpose = .dictation
    ) async throws -> (meeting: MeetingEntity, audioFileURL: URL) {
        // Verificar se arquivo fonte existe
        guard audioFileRepository.audioFileExists(at: sourceURL) else {
            throw ImportError.sourceFileNotFound
        }

        // Criar reunião para arquivo importado
        let meeting = MeetingEntity(
            app: .importedFile,
            capturePurpose: capturePurpose,
            title: meetingTitle ?? sourceURL.deletingPathExtension().lastPathComponent,
            startTime: Date() // Usar data atual como start time para arquivos importados
        )

        // Salvar reunião primeiro para obter ID
        try await meetingRepository.saveMeeting(meeting)

        // Gerar URL de destino para arquivo de áudio
        let destinationURL = audioFileRepository.generateAudioFileURL(for: meeting.id)

        // Copiar arquivo de áudio
        do {
            try await audioFileRepository.saveAudioFile(from: sourceURL, to: destinationURL)
        } catch {
            // Se cópia falhar, remover reunião criada
            try? await meetingRepository.deleteMeeting(by: meeting.id)
            throw ImportError.fileCopyFailed(error)
        }

        // Atualizar reunião com caminho do arquivo
        var updatedMeeting = meeting
        updatedMeeting.audioFilePath = destinationURL.path
        try await meetingRepository.updateMeeting(updatedMeeting)

        return (meeting: updatedMeeting, audioFileURL: destinationURL)
    }
}

/// Erros específicos do caso de uso de importação
public enum ImportError: Error {
    case sourceFileNotFound
    case invalidFileFormat
    case fileCopyFailed(Error)
    case meetingCreationFailed
}
