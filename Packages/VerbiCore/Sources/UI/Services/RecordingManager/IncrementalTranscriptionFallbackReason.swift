import Foundation

enum IncrementalTranscriptionFallbackReason: String {
    case emptyTranscript = "empty_transcript"
    case windowTranscriptionFailed = "window_transcription_failed"
    case finalDiarizationFailed = "final_diarization_failed"
    case assemblerFailed = "assembler_failed"
}
