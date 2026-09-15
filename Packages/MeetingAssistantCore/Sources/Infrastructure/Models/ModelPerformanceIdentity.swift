import Foundation
import MeetingAssistantCoreDomain

public extension TranscriptionProvider {
    func modelPerformanceIdentity(modelID: String) -> ModelPerformanceModelIdentity {
        let normalizedModelID = normalizedModelID(modelID)
        return ModelPerformanceModelIdentity(
            providerID: rawValue,
            providerDisplayName: displayName,
            modelID: normalizedModelID,
            modelDisplayName: displayName(forModelID: normalizedModelID),
            runtimeKind: usesRemoteInference ? .remote : .local
        )
    }
}

public extension AIProvider {
    func modelPerformanceIdentity(
        modelID: String,
        providerDisplayName: String? = nil
    ) -> ModelPerformanceModelIdentity {
        let trimmedModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return ModelPerformanceModelIdentity(
            providerID: rawValue,
            providerDisplayName: providerDisplayName ?? displayName,
            modelID: trimmedModelID,
            modelDisplayName: trimmedModelID.isEmpty ? "Unknown" : trimmedModelID,
            runtimeKind: .remote
        )
    }
}

public extension AppSettingsStore {
    func resolvedEnhancementsPerformanceIdentity(
        for mode: IntelligenceKernelMode
    ) -> ModelPerformanceModelIdentity {
        let selection = enhancementsSelection(for: mode)
        let configuration = resolvedEnhancementsAIConfiguration(for: mode)
        let providerDisplay = enhancementsRegistration(for: selection.registrationID)?.displayName ?? configuration.provider.displayName
        return configuration.provider.modelPerformanceIdentity(
            modelID: configuration.selectedModel,
            providerDisplayName: providerDisplay
        )
    }
}

public enum ModelPerformanceIdentityResolver {
    public static func unknown(modelID: String = "unknown") -> ModelPerformanceModelIdentity {
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "unknown" : trimmed
        return ModelPerformanceModelIdentity(
            providerID: "unknown",
            providerDisplayName: "Unknown",
            modelID: resolved,
            modelDisplayName: resolved == "unknown" ? "Unknown" : resolved,
            runtimeKind: .unknown
        )
    }
}
