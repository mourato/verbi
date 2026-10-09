@preconcurrency import FluidAudio
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure

extension FluidAIModelManager {
    func hasASRModelsOnDisk() -> Bool {
        LocalTranscriptionModel.allCases.contains { model in
            isASRModelInstalled(localModelID: model.rawValue)
        }
    }

    public func isASRModelInstalled(localModelID: String) -> Bool {
        guard let model = LocalTranscriptionModel(rawValue: localModelID) else { return false }
        let runtime = LocalASRModelRuntimeRegistry.runtime(for: model)
        return runtime.isInstalled()
    }

    func resolveLocalModel(from rawValue: String) -> LocalTranscriptionModel {
        LocalTranscriptionModel(rawValue: rawValue) ?? .parakeetTdt06BV3
    }

    nonisolated static func loadASRModels(for model: LocalTranscriptionModel) async throws -> AsrModels {
        let runtime = LocalASRModelRuntimeRegistry.runtime(for: model)
        return try await runtime.downloadAndLoad()
    }

    func asrModelDirectory(for model: LocalTranscriptionModel) -> URL {
        switch model {
        case .parakeetTdt06BV3:
            AsrModels.defaultCacheDirectory(for: .v3)
        }
    }

    func removeASRModelFromDisk(_ model: LocalTranscriptionModel) throws {
        let fileManager = FileManager.default
        let targetDirectory = asrModelDirectory(for: model)

        if fileManager.fileExists(atPath: targetDirectory.path) {
            try fileManager.removeItem(at: targetDirectory)
        }
    }

    func hasDiarizationModelsOnDisk() -> Bool {
        let repoDirectory = diarizationModelsDirectory()
        return ModelNames.OfflineDiarizer.requiredModels.allSatisfy { fileName in
            FileManager.default.fileExists(atPath: repoDirectory.appendingPathComponent(fileName).path)
        }
    }

    /// Official offline diarizer repo folder under the FluidAudio models root.
    func diarizationModelsDirectory() -> URL {
        OfflineDiarizerModels.defaultModelsDirectory()
            .appendingPathComponent(Repo.diarizer.folderName, isDirectory: true)
    }
}
