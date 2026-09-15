@preconcurrency import FluidAudio
import Foundation
import MeetingAssistantCoreInfrastructure

protocol LocalASRModelRuntime {
    var model: LocalTranscriptionModel { get }
    func isInstalled() -> Bool
    func downloadAndLoad() async throws -> AsrModels
}

enum LocalASRModelRuntimeRegistry {
    static func runtime(for model: LocalTranscriptionModel) -> any LocalASRModelRuntime {
        switch model {
        case .parakeetTdt06BV3:
            ParakeetLocalASRModelRuntime()
        }
    }
}

private struct ParakeetLocalASRModelRuntime: LocalASRModelRuntime {
    let model: LocalTranscriptionModel = .parakeetTdt06BV3

    func isInstalled() -> Bool {
        AsrModels.modelsExist(
            at: AsrModels.defaultCacheDirectory(for: .v3),
            version: .v3
        )
    }

    func downloadAndLoad() async throws -> AsrModels {
        try await AsrModels.downloadAndLoad(version: .v3)
    }
}
