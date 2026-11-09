import Foundation
import os.log
import VerbiCoreCommon
import VerbiCoreDomain
import VerbiCoreInfrastructure

@MainActor
protocol LocalModelPrewarmManaging: AnyObject {
    var modelState: VerbiCoreDomain.ModelState { get }
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
    func resolvedTranscriptionSelection(for mode: CaptureMode) -> TranscriptionProviderSelection
    func localModelSupportsDiarization(modelID: String) -> Bool
}

extension AppSettingsStore: LocalModelPrewarmSettingsProviding {}

/// Preventive launch-time load of local Core ML models so macOS compiles the ANE cache off the critical path.
/// Runs only when the cheap fingerprint (macOS build, ASR model, diarization) changed since the last successful prewarm.
@MainActor
public final class LocalModelCompilePrewarmer {
    /// Bump manually to force one prewarm pass after a change that invalidates the compiled cache.
    static let fingerprintSchemaVersion = 1
    /// The ANE compiles serially, so a compile that overlaps a capture also stalls that capture's
    /// ANE work (window OCR, local ASR). Wait for this long without any capture before compiling.
    static let quietWindow: Duration = .seconds(60)
    static let quietPollInterval: Duration = .seconds(5)
    static let fingerprintDefaultsKey = "localModelCompilePrewarmFingerprint"

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "LocalModelCompilePrewarmer")
    private let models: any LocalModelPrewarmManaging
    private let settings: any LocalModelPrewarmSettingsProviding
    private let defaults: UserDefaults
    private let isCaptureActive: () -> Bool
    private let isLowPowerModeEnabled: () -> Bool
    private let operatingSystemVersion: () -> String
    private let sleep: (Duration) async -> Void

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
        operatingSystemVersion: @escaping () -> String = { ProcessInfo.processInfo.operatingSystemVersionString },
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.models = models
        self.settings = settings
        self.defaults = defaults
        self.isCaptureActive = isCaptureActive
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.operatingSystemVersion = operatingSystemVersion
        self.sleep = sleep
    }

    /// Fire-and-forget: defers past launch so it never touches the launch critical path.
    public func scheduleLaunchPrewarm() {
        Task(priority: .utility) { [self] in
            await waitForQuietWindow()
            await runIfNeeded()
        }
    }

    /// Returns once no capture has been active for a full `quietWindow`; any capture restarts the window.
    func waitForQuietWindow() async {
        var quietElapsed: Duration = .zero
        while quietElapsed < Self.quietWindow {
            await sleep(Self.quietPollInterval)
            quietElapsed = isCaptureActive() ? .zero : quietElapsed + Self.quietPollInterval
        }
    }

    func runIfNeeded() async {
        guard !isCaptureActive(), !isLowPowerModeEnabled(), let target = prewarmTarget() else { return }

        let fingerprint = makeFingerprint(modelID: target.modelID, includesDiarization: target.includesDiarization)
        guard defaults.string(forKey: Self.fingerprintDefaultsKey) != fingerprint else { return }

        let wasASRResident = models.isASRResidentInMemory
        let wasDiarizationResident = models.isDiarizationResidentInMemory

        await models.loadModels(for: target.modelID)
        if target.includesDiarization {
            guard !isCaptureActive() else { return }
            await models.loadDiarizationModels()
        }

        let didLoad = models.modelState == .loaded
            && (!target.includesDiarization || models.isDiarizationResidentInMemory)

        // Only release what this pass loaded; never unload during a capture.
        if !isCaptureActive() {
            if !wasASRResident {
                models.unloadASRFromMemoryIfPossible()
            }
            if target.includesDiarization, !wasDiarizationResident {
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

    /// Prefer local meeting models, falling back to local dictation when meetings use cloud.
    /// Only prepare installed assets; optional diarization must not prevent ASR preparation.
    private func prewarmTarget() -> PrewarmTarget? {
        let modes: [CaptureMode] = settings.isMeetingTranscriptionEnabled ? [.meeting, .dictation] : [.dictation]
        for mode in modes {
            let selection = settings.resolvedTranscriptionSelection(for: mode)
            guard selection.provider == .local,
                  models.isASRModelInstalled(localModelID: selection.selectedModel)
            else { continue }

            let includesDiarization = mode == .meeting
                && FeatureFlags.enableDiarization
                && settings.isDiarizationEnabled
                && settings.localModelSupportsDiarization(modelID: selection.selectedModel)
                && models.hasDiarizationModelsOnDisk()
            return PrewarmTarget(modelID: selection.selectedModel, includesDiarization: includesDiarization)
        }
        return nil
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
