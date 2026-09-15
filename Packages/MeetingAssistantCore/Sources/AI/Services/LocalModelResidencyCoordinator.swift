import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreInfrastructure
import os.log

@MainActor
protocol LocalModelResidencyManaging: AnyObject {
    /// Stable identifier for diagnostics and residency coverage auditing.
    var residencyManagerID: String { get }
    /// Local model IDs whose runtime memory lifecycle is managed by this residency manager.
    var managedLocalModelIDs: Set<String> { get }
    var lastASRActivityAt: Date? { get }
    var lastDiarizationActivityAt: Date? { get }
    var isASRInUse: Bool { get }
    var isDiarizationInUse: Bool { get }
    var isASRResidentInMemory: Bool { get }
    var isDiarizationResidentInMemory: Bool { get }
    @discardableResult func unloadASRFromMemoryIfPossible() -> Bool
    @discardableResult func unloadDiarizationFromMemoryIfPossible() -> Bool
}

extension FluidAIModelManager: LocalModelResidencyManaging {}

extension FluidAIModelManager {
    var residencyManagerID: String {
        "fluidaudio"
    }

    var managedLocalModelIDs: Set<String> {
        [LocalTranscriptionModel.parakeetTdt06BV3.rawValue]
    }
}

@MainActor
enum LocalModelRuntimeRegistry {
    /// Single source of truth for residency-managed local model runtimes.
    static var residencyManagers: [any LocalModelResidencyManaging] {
        [FluidAIModelManager.shared]
    }
}

@MainActor
protocol ModelResidencyTimeoutSettingsProviding: AnyObject {
    var modelResidencyTimeout: AppSettingsStore.ModelResidencyTimeoutOption { get }
}

extension AppSettingsStore: ModelResidencyTimeoutSettingsProviding {}

@MainActor
public final class LocalModelResidencyCoordinator {
    public static let shared = LocalModelResidencyCoordinator()

    /// Post-dictation grace before unloading ASR so back-to-back dictates reuse the warm model (plan 128).
    public static let dictationIdleUnloadGraceSeconds: TimeInterval = 120

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "LocalModelResidencyCoordinator")
    private let modelManagers: [any LocalModelResidencyManaging]
    private let settingsStore: any ModelResidencyTimeoutSettingsProviding
    private let checkIntervalNanoseconds: UInt64

    private var monitorTask: Task<Void, Never>?
    private var dictationIdleUnloadTask: Task<Void, Never>?

    init(
        modelManager: any LocalModelResidencyManaging,
        settingsStore: any ModelResidencyTimeoutSettingsProviding = AppSettingsStore.shared,
        checkIntervalSeconds: TimeInterval = 30
    ) {
        modelManagers = [modelManager]
        self.settingsStore = settingsStore
        let clampedInterval = max(1, checkIntervalSeconds)
        checkIntervalNanoseconds = UInt64(clampedInterval * 1_000_000_000)
    }

    init(
        modelManagers: [any LocalModelResidencyManaging] = LocalModelRuntimeRegistry.residencyManagers,
        settingsStore: any ModelResidencyTimeoutSettingsProviding = AppSettingsStore.shared,
        checkIntervalSeconds: TimeInterval = 30
    ) {
        self.modelManagers = modelManagers
        self.settingsStore = settingsStore
        let clampedInterval = max(1, checkIntervalSeconds)
        checkIntervalNanoseconds = UInt64(clampedInterval * 1_000_000_000)
    }

    deinit {
        monitorTask?.cancel()
        dictationIdleUnloadTask?.cancel()
    }

    public func startMonitoring() {
        guard monitorTask == nil else { return }

        logLocalModelResidencyCoverage()
        logger.info("Starting local model residency monitoring.")
        monitorTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                evaluateAndUnloadIfNeeded(now: Date())
                try? await Task.sleep(nanoseconds: checkIntervalNanoseconds)
            }
        }
    }

    public func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        cancelDictationIdleUnload()
    }

    /// Schedules ASR unload after dictation ends when idle past `grace`. Honors global `never` timeout
    /// and skips when `grace` exceeds the configured global inactivity interval.
    public func scheduleDictationIdleUnload(
        grace: TimeInterval = dictationIdleUnloadGraceSeconds,
        isMeetingCaptureActive: @escaping @MainActor () async -> Bool = { false }
    ) {
        cancelDictationIdleUnload()

        guard let globalTimeout = settingsStore.modelResidencyTimeout.inactivityInterval else {
            return
        }
        guard grace <= globalTimeout else {
            return
        }

        dictationIdleUnloadTask = Task { [weak self] in
            let graceNanoseconds = UInt64(max(0, grace) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: graceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.performDictationIdleUnloadIfEligible(
                grace: grace,
                isMeetingCaptureActive: isMeetingCaptureActive
            )
        }
    }

    func cancelDictationIdleUnload() {
        dictationIdleUnloadTask?.cancel()
        dictationIdleUnloadTask = nil
    }

    func noteASRActivity() {
        cancelDictationIdleUnload()
    }

    func performDictationIdleUnloadIfEligible(
        now: Date = Date(),
        grace: TimeInterval = dictationIdleUnloadGraceSeconds,
        isMeetingCaptureActive: @MainActor () async -> Bool = { false }
    ) async {
        guard settingsStore.modelResidencyTimeout.inactivityInterval != nil else { return }
        guard await !isMeetingCaptureActive() else { return }

        for modelManager in modelManagers {
            guard modelManager.isASRResidentInMemory else { continue }
            guard !modelManager.isASRInUse else { continue }
            guard let lastActivity = modelManager.lastASRActivityAt else { continue }
            guard now.timeIntervalSince(lastActivity) >= grace else { continue }

            if modelManager.unloadASRFromMemoryIfPossible() {
                logger.info(
                    "Auto-unloaded ASR model from RAM after dictation idle grace for manager=\(modelManager.residencyManagerID, privacy: .public)."
                )
            }
        }
    }

    func evaluateAndUnloadIfNeeded(now: Date = Date()) {
        guard let timeoutInterval = settingsStore.modelResidencyTimeout.inactivityInterval else {
            return
        }

        for modelManager in modelManagers {
            if shouldUnloadASR(using: modelManager, now: now, timeoutInterval: timeoutInterval),
               modelManager.unloadASRFromMemoryIfPossible()
            {
                logger.info("Auto-unloaded ASR model from RAM after inactivity threshold for manager=\(modelManager.residencyManagerID, privacy: .public).")
            }

            if shouldUnloadDiarization(using: modelManager, now: now, timeoutInterval: timeoutInterval),
               modelManager.unloadDiarizationFromMemoryIfPossible()
            {
                logger.info("Auto-unloaded diarization model from RAM after inactivity threshold for manager=\(modelManager.residencyManagerID, privacy: .public).")
            }
        }
    }

    func isResidencyManaged(localModelID: String) -> Bool {
        modelManagers.contains { $0.managedLocalModelIDs.contains(localModelID) }
    }

    private func shouldUnloadASR(
        using modelManager: any LocalModelResidencyManaging,
        now: Date,
        timeoutInterval: TimeInterval
    ) -> Bool {
        guard modelManager.isASRResidentInMemory else { return false }
        guard !modelManager.isASRInUse else { return false }
        guard let lastActivity = modelManager.lastASRActivityAt else { return false }
        return now.timeIntervalSince(lastActivity) >= timeoutInterval
    }

    private func shouldUnloadDiarization(
        using modelManager: any LocalModelResidencyManaging,
        now: Date,
        timeoutInterval: TimeInterval
    ) -> Bool {
        guard modelManager.isDiarizationResidentInMemory else { return false }
        guard !modelManager.isDiarizationInUse else { return false }
        guard let lastActivity = modelManager.lastDiarizationActivityAt else { return false }
        return now.timeIntervalSince(lastActivity) >= timeoutInterval
    }

    private func logLocalModelResidencyCoverage() {
        let managedModelIDs = Set(modelManagers.flatMap(\.managedLocalModelIDs))
        let configuredModelIDs = Set(LocalTranscriptionModel.allCases.map(\.rawValue))
        let uncoveredModelIDs = configuredModelIDs.subtracting(managedModelIDs)

        if uncoveredModelIDs.isEmpty {
            logger.info("Local model residency coverage verified for all configured local model IDs.")
            return
        }

        logger.error(
            "Missing residency manager coverage for local model IDs: \(uncoveredModelIDs.sorted().joined(separator: ", "), privacy: .public)."
        )
    }
}
