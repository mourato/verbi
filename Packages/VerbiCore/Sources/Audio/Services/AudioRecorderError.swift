import Foundation

public enum AudioRecorderError: LocalizedError {
    case invalidInputFormat
    case invalidRecordingFormat
    case failedToCreateFile(Error)
    case failedToCreateConverter
    case failedToStartEngine(Error)
    case audioConversionError(Error)
    case fileWriteFailed(Error)
    case recordingValidationFailed
    case permissionDenied

    public var errorDescription: String? {
        switch self {
        case .invalidInputFormat:
            "Formato de entrada de áudio inválido do dispositivo"
        case .invalidRecordingFormat:
            "Falha ao criar formato de gravação"
        case let .failedToCreateFile(error):
            "Falha ao criar arquivo de áudio: \(error.localizedDescription)"
        case .failedToCreateConverter:
            "Falha ao criar conversor de formato de áudio"
        case let .failedToStartEngine(error):
            "Falha ao iniciar motor de áudio: \(error.localizedDescription)"
        case let .audioConversionError(error):
            "Falha na conversão de formato de áudio: \(error.localizedDescription)"
        case let .fileWriteFailed(error):
            "Falha ao gravar dados de áudio no arquivo: \(error.localizedDescription)"
        case .recordingValidationFailed:
            "A gravação falhou ao iniciar - nenhum áudio válido recebido do dispositivo"
        case .permissionDenied:
            "Permissão de microfone negada. Habilite nas Ajustes do Sistema para gravar."
        }
    }
}
