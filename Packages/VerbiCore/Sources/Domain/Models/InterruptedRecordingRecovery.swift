import Foundation
import VerbiCoreCommon

public enum InterruptedRecordingRecovery {
    public static let pendingFilenamesKey = "storage.recovery.interrupted.pending_filenames.v1"
    public static let dismissedFilenamesKey = "storage.recovery.interrupted.dismissed_filenames.v1"
    public static let attemptCountsKey = "storage.recovery.interrupted.attempt_counts.v1"

    public static let recoveryWindow: TimeInterval = 7 * 86400
    public static let orphanAgeThreshold: TimeInterval = 86400
    public static let maxAutoRecoveryAttempts = 3

    public struct Candidate: Hashable, Sendable {
        public let url: URL
        public let createdAt: Date

        public init(url: URL, createdAt: Date) {
            self.url = url
            self.createdAt = createdAt
        }
    }

    public struct ScanContext: Sendable {
        public let knownAudioPaths: Set<String>
        public let activeAudioPaths: Set<String>
        public let dismissedFilenames: Set<String>
        public let pendingFilenames: Set<String>
        public let now: Date

        public init(
            knownAudioPaths: Set<String> = [],
            activeAudioPaths: Set<String> = [],
            dismissedFilenames: Set<String> = [],
            pendingFilenames: Set<String> = [],
            now: Date = Date()
        ) {
            self.knownAudioPaths = knownAudioPaths
            self.activeAudioPaths = activeAudioPaths
            self.dismissedFilenames = dismissedFilenames
            self.pendingFilenames = pendingFilenames
            self.now = now
        }
    }

    public static func recoverableOrphans(
        in recordingsDirectory: URL,
        context: ScanContext,
        fileManager: FileManager = .default
    ) -> [Candidate] {
        let scanner = OrphanScanner(
            knownStandardized: Set(context.knownAudioPaths.map(standardizedAudioPath(_:))),
            activeStandardized: Set(context.activeAudioPaths.map(standardizedAudioPath(_:))),
            context: context,
            fileManager: fileManager
        )

        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey
        ]
        guard let files = try? fileManager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [Candidate] = []
        for fileURL in files where isAllowedAudioFile(fileURL) {
            guard let createdAt = scanner.recoveryDate(for: fileURL, resourceKeys: resourceKeys) else {
                continue
            }
            candidates.append(Candidate(url: fileURL, createdAt: createdAt))
        }

        candidates.sort {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.url.path < $1.url.path
        }
        return candidates
    }

    private struct OrphanScanner {
        let knownStandardized: Set<String>
        let activeStandardized: Set<String>
        let context: ScanContext
        let fileManager: FileManager

        func recoveryDate(for fileURL: URL, resourceKeys: [URLResourceKey]) -> Date? {
            let standardizedPath = fileURL.standardizedFileURL.path
            guard !knownStandardized.contains(standardizedPath) else {
                return nil
            }
            guard !activeStandardized.contains(standardizedPath) else {
                return nil
            }
            guard !context.dismissedFilenames.contains(fileURL.lastPathComponent) else {
                return nil
            }

            let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
            if values?.isDirectory == true {
                return nil
            }
            guard InterruptedRecordingRecovery.nonEmptyByteCount(
                values: values,
                fileURL: fileURL,
                fileManager: fileManager
            ) != nil else {
                return nil
            }

            let createdAt = values?.creationDate ?? values?.contentModificationDate ?? context.now
            if context.pendingFilenames.contains(fileURL.lastPathComponent) {
                return createdAt
            }
            guard context.now.timeIntervalSince(createdAt) <= InterruptedRecordingRecovery.recoveryWindow else {
                return nil
            }
            return createdAt
        }
    }

    static func nonEmptyByteCount(
        values: URLResourceValues?,
        fileURL: URL,
        fileManager: FileManager
    ) -> Int64? {
        if let fileSize = values?.fileSize, fileSize > 0 {
            return Int64(fileSize)
        }
        if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
           let size = attributes[.size] as? NSNumber, size.int64Value > 0
        {
            return size.int64Value
        }
        return nil
    }

    public struct SplitGroup: Hashable, Sendable {
        public let baseName: String
        public let microphoneURL: URL?
        public let systemURL: URL?
        public let mergedURL: URL?
        public let createdAt: Date

        public var partURLs: [URL] {
            [microphoneURL, systemURL].compactMap(\.self)
        }

        public var inferredCapturePurpose: CapturePurpose {
            if systemURL != nil {
                return .meeting
            }
            if microphoneURL != nil, mergedURL == nil {
                let stem = microphoneURL?.deletingPathExtension().lastPathComponent.lowercased() ?? ""
                if stem.hasPrefix("unknown_") {
                    return .dictation
                }
            }
            return .meeting
        }

        public init(
            baseName: String,
            microphoneURL: URL? = nil,
            systemURL: URL? = nil,
            mergedURL: URL? = nil,
            createdAt: Date
        ) {
            self.baseName = baseName
            self.microphoneURL = microphoneURL
            self.systemURL = systemURL
            self.mergedURL = mergedURL
            self.createdAt = createdAt
        }
    }

    public static func groupSplitParts(_ candidates: [Candidate]) -> [SplitGroup] {
        var order: [String] = []
        var groups: [String: SplitGroup] = [:]

        for candidate in candidates {
            let stem = candidate.url.deletingPathExtension().lastPathComponent
            let (baseName, part) = splitPartStem(stem)
            if groups[baseName] == nil {
                order.append(baseName)
            }
            let existing = groups[baseName] ?? SplitGroup(baseName: baseName, createdAt: candidate.createdAt)
            let merged = SplitGroup(
                baseName: baseName,
                microphoneURL: part == .microphone ? candidate.url : existing.microphoneURL,
                systemURL: part == .system ? candidate.url : existing.systemURL,
                mergedURL: part == .merged ? candidate.url : existing.mergedURL,
                createdAt: min(existing.createdAt, candidate.createdAt)
            )
            groups[baseName] = merged
        }

        return order.compactMap { groups[$0] }
    }

    private enum SplitPart {
        case microphone
        case system
        case merged
    }

    private static func splitPartStem(_ stem: String) -> (String, SplitPart) {
        let lowered = stem.lowercased()
        if lowered.hasSuffix("_mic") {
            return (String(stem.dropLast(4)), .microphone)
        }
        if lowered.hasSuffix("_sys") {
            return (String(stem.dropLast(4)), .system)
        }
        return (stem, .merged)
    }

    public static func normalizedGroupKey(filename: String) -> String {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent.lowercased()
        let (baseName, _) = splitPartStem(stem)
        let stripped = stripRecoveredVariantSuffix(baseName)
        if stripped != baseName, isAppGeneratedStem(stripped) {
            return stripped
        }
        return baseName
    }

    static func isAppGeneratedStem(_ baseName: String) -> Bool {
        baseName.range(of: "^[a-z0-9_.-]+_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil
    }

    static func stripRecoveredVariantSuffix(_ stem: String) -> String {
        if let range = stem.range(of: "-recovered(-[0-9]+)?$", options: .regularExpression) {
            return String(stem[..<range.lowerBound])
        }
        return stem
    }

    public static func referencedGroupKeys(
        audioPaths: Set<String>,
        recordingsDirectory: URL
    ) -> Set<String> {
        let recordingsPath = recordingsDirectory.standardizedFileURL.path
        var keys = Set<String>()
        for path in audioPaths {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            guard standardized == recordingsPath || standardized.hasPrefix(recordingsPath + "/") else {
                continue
            }
            keys.insert(normalizedGroupKey(filename: URL(fileURLWithPath: standardized).lastPathComponent))
        }
        return keys
    }

    public static func mergedFileExtension(for group: SplitGroup) -> String {
        let ext = group.microphoneURL?.pathExtension ?? group.systemURL?.pathExtension ?? group.mergedURL?.pathExtension ?? "wav"
        let lowered = ext.lowercased()
        return ["m4a", "wav"].contains(lowered) ? lowered : "wav"
    }

    public static func mergedOutputURL(for group: SplitGroup, in recordingsDirectory: URL) -> URL? {
        let output = recordingsDirectory
            .appendingPathComponent(group.baseName)
            .appendingPathExtension(mergedFileExtension(for: group))
        if FileManager.default.fileExists(atPath: output.path) {
            return nil
        }
        return output
    }

    public static func shouldDeleteOrphanedFile(
        filename: String,
        createdAt: Date?,
        isReferenced: Bool,
        pendingFilenames: Set<String>,
        dismissedFilenames: Set<String>,
        now: Date = Date()
    ) -> Bool {
        guard !isReferenced else { return false }
        guard !pendingFilenames.contains(filename) else { return false }
        guard let createdAt else { return false }
        guard now.timeIntervalSince(createdAt) > orphanAgeThreshold else { return false }
        if now.timeIntervalSince(createdAt) <= recoveryWindow,
           !dismissedFilenames.contains(filename)
        {
            return false
        }
        return true
    }

    public static func autoRetryAllowed(filename: String, attempts: [String: Int]) -> Bool {
        (attempts[filename] ?? 0) < maxAutoRecoveryAttempts
    }

    public static func recordingFailedAttempt(filename: String, attempts: [String: Int]) -> [String: Int] {
        var updated = attempts
        updated[filename, default: 0] += 1
        return updated
    }

    public struct Stores: Sendable, Equatable {
        public var pending: Set<String>
        public var dismissed: Set<String>
        public var attempts: [String: Int]

        public init(
            pending: Set<String> = [],
            dismissed: Set<String> = [],
            attempts: [String: Int] = [:]
        ) {
            self.pending = pending
            self.dismissed = dismissed
            self.attempts = attempts
        }
    }

    public static func prunedStores(
        _ stores: Stores,
        existingFilenames: Set<String>,
        referencedFilenames: Set<String>
    ) -> Stores {
        var pruned = Stores(
            pending: stores.pending.intersection(existingFilenames).subtracting(referencedFilenames),
            dismissed: stores.dismissed.intersection(existingFilenames),
            attempts: stores.attempts.filter { existingFilenames.contains($0.key) }
        )
        for filename in pruned.pending where !autoRetryAllowed(filename: filename, attempts: pruned.attempts) {
            pruned.pending.remove(filename)
        }
        return pruned
    }

    public static func isRecoveredTitle(_ title: String?) -> Bool {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return false
        }
        return trimmed == recoveredTitle()
            || trimmed == "Recovered recording"
            || trimmed == "Gravação recuperada"
    }

    public static func recoveredTitle() -> String {
        "recovery.interrupted.title".localized
    }

    public static func pendingFailureReason() -> String {
        "recovery.interrupted.pending".localized
    }

    public static func notificationTitle() -> String {
        "recovery.interrupted.notification.title".localized
    }

    public static func notificationBody(recoveredCount: Int) -> String {
        if recoveredCount <= 1 {
            return "recovery.interrupted.notification.body.one".localized
        }
        return "recovery.interrupted.notification.body.other".localized(with: recoveredCount)
    }

    public static func loadStores(defaults: UserDefaults = .standard) -> Stores {
        Stores(
            pending: Set(defaults.stringArray(forKey: pendingFilenamesKey) ?? []),
            dismissed: Set(defaults.stringArray(forKey: dismissedFilenamesKey) ?? []),
            attempts: (defaults.dictionary(forKey: attemptCountsKey) as? [String: Int]) ?? [:]
        )
    }

    public static func saveStores(_ stores: Stores, defaults: UserDefaults = .standard) {
        defaults.set(Array(stores.pending), forKey: pendingFilenamesKey)
        defaults.set(Array(stores.dismissed), forKey: dismissedFilenamesKey)
        defaults.set(stores.attempts, forKey: attemptCountsKey)
    }

    public static func noteUserDeletedAudioFilenames(_ filenames: [String], defaults: UserDefaults = .standard) {
        let basenames = filenames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        guard !basenames.isEmpty else { return }
        var stores = loadStores(defaults: defaults)
        stores.dismissed.formUnion(basenames)
        saveStores(stores, defaults: defaults)
    }

    public static func standardizedAudioPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func isAllowedAudioFile(_ url: URL) -> Bool {
        ["m4a", "wav"].contains(url.pathExtension.lowercased())
    }
}
