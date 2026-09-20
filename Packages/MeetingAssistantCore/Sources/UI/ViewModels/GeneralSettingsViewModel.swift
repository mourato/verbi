import AppKit
import Combine
import Foundation
import MeetingAssistantCoreAI
import MeetingAssistantCoreAudio
import MeetingAssistantCoreCommon
import MeetingAssistantCoreData
import MeetingAssistantCoreDomain
import MeetingAssistantCoreInfrastructure
import Observation
import os
import SwiftUI

@MainActor
public protocol GeneralSettingsAudioDeviceManaging: AnyObject {
    var availableInputDevices: [AudioInputDevice] { get }
    var availableInputDevicesPublisher: AnyPublisher<[AudioInputDevice], Never> { get }
    func refreshDevices()
}

@MainActor
extension AudioDeviceManager: GeneralSettingsAudioDeviceManaging {
    public var availableInputDevicesPublisher: AnyPublisher<[AudioInputDevice], Never> {
        $availableInputDevices.eraseToAnyPublisher()
    }
}

@MainActor
@Observable
public final class GeneralSettingsViewModel {
    public var autoStartRecording: Bool {
        didSet {
            settingsStore.autoStartRecording = autoStartRecording
        }
    }

    public var recordingsPath: String {
        didSet {
            settingsStore.recordingsDirectory = recordingsPath
        }
    }

    public var audioFormat: AppSettingsStore.AudioFormat {
        didSet {
            settingsStore.audioFormat = audioFormat
        }
    }

    public var shouldMergeAudioFiles: Bool {
        didSet {
            settingsStore.shouldMergeAudioFiles = shouldMergeAudioFiles
        }
    }

    public var selectedLanguage: AppLanguage {
        didSet {
            settingsStore.selectedLanguage = selectedLanguage
        }
    }

    public var showSettingsOnLaunch: Bool {
        didSet {
            settingsStore.showSettingsOnLaunch = showSettingsOnLaunch
        }
    }

    public var autoCopyTranscriptionToClipboard: Bool {
        didSet {
            settingsStore.autoCopyTranscriptionToClipboard = autoCopyTranscriptionToClipboard
        }
    }

    public var shortcutDoubleTapIntervalMilliseconds: Double {
        didSet {
            settingsStore.shortcutDoubleTapIntervalMilliseconds = shortcutDoubleTapIntervalMilliseconds
        }
    }

    public var autoPasteTranscriptionToActiveApp: Bool {
        didSet {
            settingsStore.autoPasteTranscriptionToActiveApp = autoPasteTranscriptionToActiveApp
        }
    }

    public var smartSpacingAndCapitalizationEnabled: Bool {
        didSet {
            settingsStore.smartSpacingAndCapitalizationEnabled = smartSpacingAndCapitalizationEnabled
        }
    }

    public var smartParagraphsEnabled: Bool {
        didSet {
            settingsStore.smartParagraphsEnabled = smartParagraphsEnabled
        }
    }

    public var recordingMediaHandlingMode: AppSettingsStore.RecordingMediaHandlingMode {
        didSet {
            settingsStore.recordingMediaHandlingMode = recordingMediaHandlingMode
        }
    }

    public var audioDuckingLevelPercent: Int {
        didSet {
            let clamped = AppSettingsStore.clampedAudioDuckingLevelPercent(audioDuckingLevelPercent)
            guard clamped == audioDuckingLevelPercent else {
                audioDuckingLevelPercent = clamped
                return
            }

            settingsStore.audioDuckingLevelPercent = audioDuckingLevelPercent
        }
    }

    public var useSystemDefaultInput: Bool {
        didSet {
            settingsStore.useSystemDefaultInput = useSystemDefaultInput
        }
    }

    public var autoIncreaseMicrophoneVolume: Bool {
        didSet {
            settingsStore.autoIncreaseMicrophoneVolume = autoIncreaseMicrophoneVolume
        }
    }

    public var removeSilenceBeforeProcessing: Bool {
        didSet {
            settingsStore.removeSilenceBeforeProcessing = removeSilenceBeforeProcessing
        }
    }

    public var recordingIndicatorEnabled: Bool {
        didSet {
            settingsStore.recordingIndicatorEnabled = recordingIndicatorEnabled
        }
    }

    public var recordingIndicatorStyle: RecordingIndicatorStyle {
        didSet {
            settingsStore.recordingIndicatorStyle = recordingIndicatorStyle
        }
    }

    public var recordingIndicatorPosition: RecordingIndicatorPosition {
        didSet {
            settingsStore.recordingIndicatorPosition = recordingIndicatorPosition
        }
    }

    public var recordingIndicatorAnimationSpeed: RecordingIndicatorAnimationSpeed {
        didSet {
            settingsStore.recordingIndicatorAnimationSpeed = recordingIndicatorAnimationSpeed
        }
    }

    public var autoDeleteTranscriptions: Bool {
        didSet {
            settingsStore.autoDeleteTranscriptions = autoDeleteTranscriptions
        }
    }

    public var autoDeletePeriodDays: Int {
        didSet {
            settingsStore.autoDeletePeriodDays = autoDeletePeriodDays
        }
    }

    // MARK: - Sound Feedback Properties

    public var soundFeedbackEnabled: Bool {
        didSet {
            settingsStore.soundFeedbackEnabled = soundFeedbackEnabled
        }
    }

    public var recordingStartSound: SoundFeedbackSound {
        didSet {
            settingsStore.recordingStartSound = recordingStartSound
        }
    }

    public var recordingStopSound: SoundFeedbackSound {
        didSet {
            settingsStore.recordingStopSound = recordingStopSound
        }
    }

    public var showInMenuBar: Bool {
        didSet {
            settingsStore.showInMenuBar = showInMenuBar
        }
    }

    public var showInDock: Bool {
        didSet {
            settingsStore.showInDock = showInDock
        }
    }

    public var appearanceMode: AppearanceMode {
        didSet {
            settingsStore.appearanceMode = appearanceMode
        }
    }

    public var launchAtLogin: Bool {
        didSet {
            let previousValue = oldValue

            // Avoid infinite loop if we revert the state
            guard launchAtLogin != settingsStore.launchAtLogin else { return }

            settingsStore.launchAtLogin = launchAtLogin
            updateLaunchAtLogin(launchAtLogin, previousValue: previousValue)
        }
    }

    public private(set) var launchAtLoginError: LaunchAtLoginUpdateError?

    public var microphoneWhenChargingUID: String? {
        didSet {
            settingsStore.microphoneWhenChargingUID = microphoneWhenChargingUID
            rebuildAvailableDevices()
        }
    }

    public var microphoneOnBatteryUID: String? {
        didSet {
            settingsStore.microphoneOnBatteryUID = microphoneOnBatteryUID
            rebuildAvailableDevices()
        }
    }

    public var availableDevices: [AudioInputDevice] = []
    public var showCleanupSuccessAlert = false
    public var showCleanupConfirmationDialog = false
    public var cleanupInProgress = false
    public var cleanupError: String?
    public var cleanupPreview: RetentionCleanupPreview?
    public var localAICacheCleanupPreview: LocalAICacheCleanupPreview?

    @ObservationIgnored private let settingsStore: AppSettingsStore
    @ObservationIgnored private let storage: StorageService
    @ObservationIgnored private let localAICacheMaintenance: LocalAICacheMaintenanceService
    @ObservationIgnored private let launchAtLoginService: any LaunchAtLoginService
    @ObservationIgnored private let deviceManager: any GeneralSettingsAudioDeviceManaging
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    private nonisolated static let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "GeneralSettingsViewModel")

    public init(
        settingsStore: AppSettingsStore = .shared,
        storage: StorageService = FileSystemStorageService.shared,
        localAICacheMaintenance: LocalAICacheMaintenanceService = .shared,
        launchAtLoginService: any LaunchAtLoginService = SystemLaunchAtLoginService(),
        deviceManager: any GeneralSettingsAudioDeviceManaging = AudioDeviceManager()
    ) {
        self.settingsStore = settingsStore
        self.storage = storage
        self.localAICacheMaintenance = localAICacheMaintenance
        self.launchAtLoginService = launchAtLoginService
        self.deviceManager = deviceManager
        autoStartRecording = settingsStore.autoStartRecording
        recordingsPath = settingsStore.recordingsDirectory
        audioFormat = settingsStore.audioFormat
        shouldMergeAudioFiles = settingsStore.shouldMergeAudioFiles
        selectedLanguage = settingsStore.selectedLanguage
        showSettingsOnLaunch = settingsStore.showSettingsOnLaunch
        autoCopyTranscriptionToClipboard = settingsStore.autoCopyTranscriptionToClipboard
        shortcutDoubleTapIntervalMilliseconds = settingsStore.shortcutDoubleTapIntervalMilliseconds
        autoPasteTranscriptionToActiveApp = settingsStore.autoPasteTranscriptionToActiveApp
        smartSpacingAndCapitalizationEnabled = settingsStore.smartSpacingAndCapitalizationEnabled
        smartParagraphsEnabled = settingsStore.smartParagraphsEnabled
        recordingMediaHandlingMode = settingsStore.recordingMediaHandlingMode
        audioDuckingLevelPercent = settingsStore.audioDuckingLevelPercent
        useSystemDefaultInput = settingsStore.useSystemDefaultInput
        microphoneWhenChargingUID = settingsStore.microphoneWhenChargingUID
        microphoneOnBatteryUID = settingsStore.microphoneOnBatteryUID
        autoIncreaseMicrophoneVolume = settingsStore.autoIncreaseMicrophoneVolume
        removeSilenceBeforeProcessing = settingsStore.removeSilenceBeforeProcessing
        recordingIndicatorEnabled = settingsStore.recordingIndicatorEnabled
        recordingIndicatorStyle = settingsStore.recordingIndicatorStyle
        recordingIndicatorPosition = settingsStore.recordingIndicatorPosition
        recordingIndicatorAnimationSpeed = settingsStore.recordingIndicatorAnimationSpeed
        autoDeleteTranscriptions = settingsStore.autoDeleteTranscriptions
        autoDeletePeriodDays = settingsStore.autoDeletePeriodDays
        soundFeedbackEnabled = settingsStore.soundFeedbackEnabled
        recordingStartSound = settingsStore.recordingStartSound
        recordingStopSound = settingsStore.recordingStopSound
        showInMenuBar = settingsStore.showInMenuBar
        showInDock = settingsStore.showInDock
        appearanceMode = settingsStore.appearanceMode
        launchAtLogin = settingsStore.launchAtLogin
        launchAtLoginError = nil

        setupDeviceObservation()
        rebuildAvailableDevices()
    }

    public var usesDuckingControls: Bool {
        recordingMediaHandlingMode.usesDucking
    }

    public var currentPowerSourceState: PowerSourceState {
        PowerSourceStateProvider().currentPowerSourceState()
    }

    public var systemDefaultInputDevice: AudioInputDevice? {
        availableDevices.first(where: { $0.isDefault && $0.isAvailable })
            ?? availableDevices.first(where: \.isDefault)
    }

    public func microphoneUID(for powerSource: PowerSourceState) -> String? {
        switch powerSource {
        case .charging:
            microphoneWhenChargingUID
        case .battery:
            microphoneOnBatteryUID
        }
    }

    public func setMicrophoneUID(_ uid: String?, for powerSource: PowerSourceState) {
        switch powerSource {
        case .charging:
            microphoneWhenChargingUID = uid
        case .battery:
            microphoneOnBatteryUID = uid
        }
    }

    public func selectedMicrophone(for powerSource: PowerSourceState) -> AudioInputDevice? {
        guard let uid = microphoneUID(for: powerSource) else { return nil }
        return availableDevices.first(where: { $0.id == uid })
    }

    public func refreshAudioInputDevices() {
        deviceManager.refreshDevices()
    }

    public var cleanupConfirmationMessage: String {
        let preview = cleanupPreview
        let cachePreview = localAICacheCleanupPreview

        let audioCount = preview?.audioCount ?? 0
        let cacheCount = cachePreview?.candidateCount ?? 0

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        let audioSize = formatter.string(fromByteCount: preview?.totalAudioBytes ?? 0)
        let cacheSize = formatter.string(fromByteCount: cachePreview?.totalBytes ?? 0)

        return String(
            format: "settings.storage.cleanup_confirm_message".localized,
            audioCount,
            audioSize,
            cacheCount,
            cacheSize
        )
    }

    private func setupDeviceObservation() {
        deviceManager.availableInputDevicesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] devices in
                self?.mergeAvailableDevices(detectedDevices: devices)
            }
            .store(in: &cancellables)
    }

    private func mergeAvailableDevices(detectedDevices: [AudioInputDevice]) {
        let selectedUIDs = selectedMicrophoneUIDs
        let detectedUIDs = Set(detectedDevices.map(\.id))
        var merged = detectedDevices

        for uid in selectedUIDs where !detectedUIDs.contains(uid) {
            // Preserve unavailable persisted selections so user intent remains visible in pickers.
            merged.append(AudioInputDevice(id: uid, name: "Unknown Device (\(uid))", isAvailable: false))
        }

        availableDevices = merged
    }

    private var selectedMicrophoneUIDs: [String] {
        [microphoneWhenChargingUID, microphoneOnBatteryUID]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func rebuildAvailableDevices() {
        mergeAvailableDevices(detectedDevices: deviceManager.availableInputDevices)
    }

    public func selectRecordingsDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        // Use current path as starting point if valid
        if !recordingsPath.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: recordingsPath)
        }

        if panel.runModal() == .OK, let url = panel.url {
            recordingsPath = url.path
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool, previousValue: Bool) {
        launchAtLoginError = nil

        do {
            if enabled {
                if !launchAtLoginService.isEnabled {
                    try launchAtLoginService.register()
                }
            } else if launchAtLoginService.isEnabled {
                try launchAtLoginService.unregister()
            }
        } catch {
            let failure: LaunchAtLoginUpdateError = enabled ? .registrationFailed : .unregistrationFailed
            Self.logger.error("Failed to update launch at login: \(error.localizedDescription)")

            settingsStore.launchAtLogin = previousValue
            launchAtLogin = previousValue
            launchAtLoginError = failure
        }
    }

    public func retryLaunchAtLogin() {
        guard let launchAtLoginError else { return }

        self.launchAtLoginError = nil
        launchAtLogin = launchAtLoginError.requestedValue
    }

    public func dismissLaunchAtLoginError() {
        launchAtLoginError = nil
    }

    public func performCleanup() {
        guard !cleanupInProgress else { return }

        cleanupError = nil
        cleanupPreview = nil
        localAICacheCleanupPreview = nil
        cleanupInProgress = true

        Task { [weak self] in
            guard let self else { return }

            do {
                let preview = try await storage.computeRetentionCleanupPreview(olderThanDays: autoDeletePeriodDays)
                let cachePreview = try await localAICacheMaintenance.computeCleanupPreview(olderThanDays: autoDeletePeriodDays)
                cleanupPreview = preview
                localAICacheCleanupPreview = cachePreview
                showCleanupConfirmationDialog = true
            } catch {
                cleanupError = error.localizedDescription
            }

            cleanupInProgress = false
        }
    }

    public func confirmCleanup() {
        guard !cleanupInProgress else { return }
        guard let preview = cleanupPreview else { return }
        let cachePreview = localAICacheCleanupPreview

        cleanupError = nil
        cleanupInProgress = true

        Task { [weak self] in
            guard let self else { return }

            do {
                _ = FluidAIModelManager.shared.unloadDiarizationFromMemoryIfPossible()
                _ = FluidAIModelManager.shared.unloadASRFromMemoryIfPossible()
                _ = try await storage.performRetentionCleanup(preview: preview)
                if let cachePreview {
                    _ = try await localAICacheMaintenance.performCleanup(preview: cachePreview)
                }
                showCleanupSuccessAlert = true
            } catch {
                cleanupError = error.localizedDescription
            }

            cleanupInProgress = false
            cleanupPreview = nil
            localAICacheCleanupPreview = nil
        }
    }
}
