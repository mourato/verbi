import AppKit
import CoreAudio
import Foundation
import MeetingAssistantCoreCommon
import MeetingAssistantCoreDomain
import os

/// Represents a running system audio process.
public struct AudioProcessInfo: Equatable, Sendable {
    public let processID: AudioObjectID
    public let pid: pid_t
    public let bundleIdentifier: String?
    public let displayName: String?
    public let isRunningInput: Bool

    public init(
        processID: AudioObjectID,
        pid: pid_t,
        bundleIdentifier: String?,
        displayName: String?,
        isRunningInput: Bool
    ) {
        self.processID = processID
        self.pid = pid
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.isRunningInput = isRunningInput
    }
}

/// Service protocol for observing and querying audio processes.
public protocol MeetingAudioProcessProviding: AnyObject, Sendable {
    func runningInputProcesses() -> [AudioProcessInfo]
    var onProcessActivityChanged: (@Sendable () -> Void)? { get set }
}

/// Low-level abstraction over CoreAudio HAL property inspection and listeners.
public protocol CoreAudioHALProtocol: Sendable {
    func fetchProcessIDs() -> [AudioObjectID]
    func isProcessRunningInput(_ processID: AudioObjectID) -> Bool
    func fetchBundleIdentifier(for processID: AudioObjectID) -> String?
    func fetchPID(for processID: AudioObjectID) -> pid_t
    func addSystemListener(_ listener: @escaping AudioObjectPropertyListenerBlock) -> OSStatus
    func removeSystemListener(_ listener: @escaping AudioObjectPropertyListenerBlock)
    func addProcessListener(processID: AudioObjectID, _ listener: @escaping AudioObjectPropertyListenerBlock) -> OSStatus
    func removeProcessListener(processID: AudioObjectID, _ listener: @escaping AudioObjectPropertyListenerBlock)
}

/// Default CoreAudio HAL implementation directly invoking AudioObject APIs.
public struct DefaultCoreAudioHAL: CoreAudioHALProtocol {
    public init() {}

    public func fetchProcessIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard sizeStatus == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var processIDs = [AudioObjectID](repeating: 0, count: count)
        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &processIDs
        )
        guard dataStatus == noErr else { return [] }
        return processIDs
    }

    public func isProcessRunningInput(_ processID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isRunningInput: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            processID,
            &address,
            0,
            nil,
            &size,
            &isRunningInput
        )
        return status == noErr && isRunningInput != 0
    }

    public func fetchBundleIdentifier(for processID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var cfBundleID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            processID,
            &address,
            0,
            nil,
            &size,
            &cfBundleID
        )
        guard status == noErr, let cfBundleID else { return nil }
        let bundleID = cfBundleID.takeRetainedValue() as String
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func fetchPID(for processID: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        let status = AudioObjectGetPropertyData(
            processID,
            &address,
            0,
            nil,
            &size,
            &pid
        )
        return status == noErr ? pid : 0
    }

    public func addSystemListener(_ listener: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
        var sysAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &sysAddress,
            .main,
            listener
        )
    }

    public func removeSystemListener(_ listener: @escaping AudioObjectPropertyListenerBlock) {
        var sysAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &sysAddress,
            .main,
            listener
        )
    }

    public func addProcessListener(processID: AudioObjectID, _ listener: @escaping AudioObjectPropertyListenerBlock) -> OSStatus {
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        return AudioObjectAddPropertyListenerBlock(
            processID,
            &inputAddress,
            .main,
            listener
        )
    }

    public func removeProcessListener(processID: AudioObjectID, _ listener: @escaping AudioObjectPropertyListenerBlock) {
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningInput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(
            processID,
            &inputAddress,
            .main,
            listener
        )
    }
}

/// CoreAudio-backed audio process provider monitoring running input audio processes.
public final class CoreAudioMeetingProcessProvider: MeetingAudioProcessProviding, @unchecked Sendable // justified: internal state protected by OSAllocatedUnfairLock and CoreAudio callbacks dispatched to main queue
{
    public static let shared = CoreAudioMeetingProcessProvider()

    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "CoreAudioMeetingProcessProvider")
    private let debounceInterval: TimeInterval
    private let hal: any CoreAudioHALProtocol

    private struct State {
        var monitoredProcessIDs: Set<AudioObjectID> = []
        var onProcessActivityChanged: (@Sendable () -> Void)?
        var debounceTask: Task<Void, Never>?
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: State())
    private nonisolated(unsafe) var systemPropertyListener: AudioObjectPropertyListenerBlock? // justified: property listener reference retained for CoreAudio deregistration on deinit
    private nonisolated(unsafe) var processPropertyListener: AudioObjectPropertyListenerBlock? // justified: property listener reference retained for CoreAudio deregistration on deinit

    public var onProcessActivityChanged: (@Sendable () -> Void)? {
        get {
            stateLock.withLock { $0.onProcessActivityChanged }
        }
        set {
            stateLock.withLock { $0.onProcessActivityChanged = newValue }
        }
    }

    public init(
        debounceInterval: TimeInterval = 1.5,
        startListening: Bool = true,
        hal: any CoreAudioHALProtocol = DefaultCoreAudioHAL()
    ) {
        self.debounceInterval = debounceInterval
        self.hal = hal
        if startListening {
            installPropertyListeners()
        }
    }

    deinit {
        stateLock.withLock { state in
            state.debounceTask?.cancel()
            state.debounceTask = nil
        }
        removePropertyListeners()
    }

    // MARK: - MeetingAudioProcessProviding

    public func runningInputProcesses() -> [AudioProcessInfo] {
        let processIDs = hal.fetchProcessIDs()
        guard !processIDs.isEmpty else { return [] }

        var runningInputProcesses: [AudioProcessInfo] = []
        for processID in processIDs {
            guard hal.isProcessRunningInput(processID) else { continue }
            let bundleID = hal.fetchBundleIdentifier(for: processID)

            // Ignore Verbi itself
            if let bundleID, bundleID == AppIdentity.bundleIdentifier {
                continue
            }

            let pid = hal.fetchPID(for: processID)
            let displayName = resolveDisplayName(pid: pid, bundleID: bundleID)

            runningInputProcesses.append(AudioProcessInfo(
                processID: processID,
                pid: pid,
                bundleIdentifier: bundleID,
                displayName: displayName,
                isRunningInput: true
            ))
        }
        return runningInputProcesses
    }

    private func resolveDisplayName(pid: pid_t, bundleID: String?) -> String? {
        if pid > 0, let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName {
            return name
        }
        if let bundleID,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let name = app.localizedName
        {
            return name
        }
        return nil
    }

    // MARK: - Listener Installation and Debouncing

    private func installPropertyListeners() {
        let sysListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.handleSystemProcessListChanged()
        }
        systemPropertyListener = sysListener

        let sysStatus = hal.addSystemListener(sysListener)
        if sysStatus != noErr {
            logger.warning("Failed to install process object list listener: \(sysStatus)")
        }

        let procListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleDebouncedNotification()
        }
        processPropertyListener = procListener

        let initialProcessIDs = hal.fetchProcessIDs()
        updateMonitoredProcesses(to: Set(initialProcessIDs), processListener: procListener)
    }

    private func handleSystemProcessListChanged() {
        guard let procListener = processPropertyListener else { return }
        let currentProcessIDs = Set(hal.fetchProcessIDs())
        updateMonitoredProcesses(to: currentProcessIDs, processListener: procListener)
        scheduleDebouncedNotification()
    }

    private func updateMonitoredProcesses(
        to newProcessIDs: Set<AudioObjectID>,
        processListener: @escaping AudioObjectPropertyListenerBlock
    ) {
        let (toAdd, toRemove) = stateLock.withLock { state -> (Set<AudioObjectID>, Set<AudioObjectID>) in
            let old = state.monitoredProcessIDs
            state.monitoredProcessIDs = newProcessIDs
            return (newProcessIDs.subtracting(old), old.subtracting(newProcessIDs))
        }

        for processID in toRemove {
            hal.removeProcessListener(processID: processID, processListener)
        }

        for processID in toAdd {
            _ = hal.addProcessListener(processID: processID, processListener)
        }
    }

    private func scheduleDebouncedNotification() {
        let interval = debounceInterval
        stateLock.withLock { state in
            state.debounceTask?.cancel()
            state.debounceTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                let callback = self?.stateLock.withLock { $0.onProcessActivityChanged }
                callback?()
            }
        }
    }

    private func removePropertyListeners() {
        if let sysListener = systemPropertyListener {
            hal.removeSystemListener(sysListener)
            systemPropertyListener = nil
        }

        if let procListener = processPropertyListener {
            let monitored = stateLock.withLock { state -> Set<AudioObjectID> in
                let ids = state.monitoredProcessIDs
                state.monitoredProcessIDs.removeAll()
                return ids
            }
            for processID in monitored {
                hal.removeProcessListener(processID: processID, procListener)
            }
            processPropertyListener = nil
        }
    }
}
