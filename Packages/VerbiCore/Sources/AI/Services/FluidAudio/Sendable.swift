@preconcurrency import FluidAudio
import Foundation

// MARK: - Sendable Conformances for FluidAudio

extension OfflineDiarizerManager: @unchecked @retroactive Sendable {}

extension FluidAIModelManager {
    /// FluidAudio debug logs can include transcript text. Call before loading any FluidAudio model.
    /// `FluidAudio.AppLogger` is spelled unqualified here: the `FluidAudio` module qualifier is shadowed by
    /// the library's `FluidAudio` namespace struct, and Verbi's `AppLogger` is not imported in this file.
    static func configureFluidAudioLogging() {
        AppLogger.minimumLevel = .info
        AppLogger.mirrorsToConsole = false
    }
}

// Note: AsrManager is an actor and DiarizationResult, OfflineDiarizerConfig,
// and TokenTiming are already Sendable in FluidAudio 0.17.7, so no local
// patches are needed. OfflineDiarizerManager is a non-Sendable final class.
