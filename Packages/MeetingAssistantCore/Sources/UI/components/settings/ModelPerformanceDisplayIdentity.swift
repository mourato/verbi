import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure

/// Display-time identity for a stored performance record: current product name and brand,
/// resolved from the stored provider and model IDs so older snapshots show today's names.
struct ModelPerformanceDisplayIdentity: Equatable {
    let title: String
    let providerName: String
    let brand: ModelBrand?
    let host: ModelBrand?
    let fallbackSymbolName: String

    init(_ identity: ModelPerformanceModelIdentity, stage: ModelPerformanceStage) {
        switch stage {
        case .transcription:
            if let provider = TranscriptionProvider(rawValue: identity.providerID) {
                let resolved = ModelBrand.identity(for: provider, modelID: identity.modelID)
                let productName = provider.displayName(forModelID: identity.modelID)
                title = productName == identity.modelID ? identity.modelDisplayName : productName
                providerName = provider.displayName
                brand = resolved.brand
                host = resolved.host
                fallbackSymbolName = provider == .local ? "internaldrive" : "waveform"
                return
            }
        case .postProcessing:
            if let provider = AIProvider(rawValue: identity.providerID) {
                let resolved = ModelBrand.identity(for: provider, modelID: identity.modelID)
                // AI model IDs are their product names; the stored provider name keeps custom registration names.
                title = identity.modelDisplayName
                providerName = identity.providerDisplayName
                brand = resolved.brand
                host = resolved.host
                fallbackSymbolName = provider.icon
                return
            }
        }

        title = identity.modelDisplayName
        providerName = identity.providerDisplayName
        brand = ModelBrand.family(forModelID: identity.modelID)
        host = nil
        fallbackSymbolName = "cpu"
    }
}
