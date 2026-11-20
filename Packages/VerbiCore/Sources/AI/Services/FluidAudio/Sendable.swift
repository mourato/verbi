@preconcurrency import FluidAudio
import Foundation

extension OfflineDiarizerManager: @unchecked @retroactive Sendable {}

extension FluidAIModelManager {
    static func configureFluidAudioLogging() {
        AppLogger.minimumLevel = .info
        AppLogger.mirrorsToConsole = false
    }
}
