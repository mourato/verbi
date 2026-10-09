import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import os.log

@MainActor
protocol LocalModelPrewarmManaging: AnyObject {
    var modelState: FluidAIModelManager.ModelState { get }
    var isASRResidentInMemory: Bool { get }
    var isDiarizationResidentInMemory: Bool { get }
    func isASRModelInstalled(localModelID: String) -> Bool
    func hasDiarizationModelsOnDisk() -> Bool
    func loadModels(for localModelID: String) async
    func loadDiarizationModels() async
    @discardableResult func unloadASRFromMemoryIfPossible() -> Bool
    @discardableResult func unloadDiarizationFromMemoryIfPossible() -> Bool
}

extension FluidAIModelManager: LocalModelPrewarmManaging {}

@MainActor
protocol LocalModelPrewarmSettingsProviding: AnyObject {
    var isMeetingTranscriptionEnabled: Bool { get }
    var isDiarizationEnabled: Bool { get }
    func resolvedTranscriptionSelection(for mode: TranscriptionExecutionMode) -> TranscriptionProviderSelection
    func localModelSupportsDiarization(modelID: String) -> Bool
}

extension AppSettingsStore: LocalModelPrewarmSettingsProviding {}

/// Preventive launch-time load of local Core ML models so macOS compiles the ANE cache off the critical path.
/// Runs only when the cheap fingerprint (macOS build, ASR model, diarization) changed since the last successful prewarm.
@MainActor
public final class LocalModelCompilePrewarmer {
    /// Bump manually to force one prewarm pass after a change that invalidates the compiled cache.
    static let fingerprintSchemaVersion = 1
    static let launchDelay: Duration = .seconds(15)
    static let fingerprintDefaultsKey = "localModelCompilePrewarmFingerprint"

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "LocalModelCompilePrewarmer")
    private let models: any LocalModelPrewarmManaging
    private let settings: any LocalModelPrewarmSettingsProviding
    private let defaults: UserDefaults
    private let isCaptureActive: () -> Bool
    private let isLowPowerModeEnabled: () -> Bool
    private let operatingSystemVersion: () -> String

    public convenience init(isCaptureActive: @escaping () -> Bool) {
        self.init(
            models: FluidAIModelManager.shared,
            settings: AppSettingsStore.shared,
            isCaptureActive: isCaptureActive
        )
    }

    init(
        models: any LocalModelPrewarmManaging,
        settings: any LocalModelPrewarmSettingsProviding,
        defaults: UserDefaults = .standard,
        isCaptureActive: @escaping () -> Bool,
        isLowPowerModeEnabled: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled },
        operatingSystemVersion: @escaping () -> String = { ProcessInfo.processInfo.operatingSystemVersionString }
    ) {
        self.models = models
        self.settings = settings
        self.defaults = defaults
        self.isCaptureActive = isCaptureActive
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.operatingSystemVersion = operatingSystemVersion
    }

    /// Fire-and-forget: defers past launch so it never touches the launch critical path.
    public func scheduleLaunchPrewarm() {
        Task(priority: .utility) { [self] in
            try? await Task.sleep(for: Self.launchDelay)
            await runIfNeeded()
        }
    }

    func runIfNeeded() async {
        guard !isCaptureActive(), !isLowPowerModeEnabled() else { return }
        guard let target = prewarmTarget() else { return }

        let fingerprint = makeFingerprint(modelID: target.modelID, includesDiarization: target.includesDiarization)
        guard defaults.string(forKey: Self.fingerprintDefaultsKey) != fingerprint else { return }

        let wasASRResident = models.isASRResidentInMemory
        let wasDiarizationResident = models.isDiarizationResidentInMemory

        await models.loadModels(for: target.modelID)
        if target.includesDiarization {
            await models.loadDiarizationModels()
        }

        let didLoad = models.modelState == .loaded
            && (!target.includesDiarization || models.isDiarizationResidentInMemory)

        // Only release what this pass loaded; never unload during a capture.
        if !isCaptureActive() {
            if !wasASRResident {
                models.unloadASRFromMemoryIfPossible()
            }
            if !wasDiarizationResident {
                models.unloadDiarizationFromMemoryIfPossible()
            }
        }

        guard didLoad else {
            logger.error("Local model compile prewarm failed; fingerprint not persisted.")
            return
        }
        defaults.set(fingerprint, forKey: Self.fingerprintDefaultsKey)
        logger.info("Local model compile prewarm completed.")
    }

    private struct PrewarmTarget {
        let modelID: String
        let includesDiarization: Bool
    }

    /// Meeting selection when meeting capture is enabled, otherwise dictation. Skips non-local or not-installed models.
    private func prewarmTarget() -> PrewarmTarget? {
        let mode: TranscriptionExecutionMode = settings.isMeetingTranscriptionEnabled ? .meeting : .dictation
        let selection = settings.resolvedTranscriptionSelection(for: mode)
        guard selection.provider == .local else { return nil }

        let modelID = selection.selectedModel
        let includesDiarization = mode == .meeting
            && FeatureFlags.enableDiarization
            && settings.isDiarizationEnabled
            && settings.localModelSupportsDiarization(modelID: modelID)

        guard models.isASRModelInstalled(localModelID: modelID) else { return nil }
        guard !includesDiarization || models.hasDiarizationModelsOnDisk() else { return nil }
        return PrewarmTarget(modelID: modelID, includesDiarization: includesDiarization)
    }

    private func makeFingerprint(modelID: String, includesDiarization: Bool) -> String {
        [
            "schema=\(Self.fingerprintSchemaVersion)",
            "os=\(operatingSystemVersion())",
            "asr=\(modelID)",
            "diarization=\(includesDiarization)"
        ].joined(separator: "|")
    }
}
