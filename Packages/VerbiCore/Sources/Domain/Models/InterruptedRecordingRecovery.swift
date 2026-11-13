import Foundation
import VerbiCoreCommon

/// Launch-time recovery for audio files orphaned by a crash or forced quit.
///
/// A crash can leave finished audio in the recordings directory with no saved
/// transcription referencing it. The retention sweeps must never delete such a
/// file before recovery has seen it, so both flows share the helpers here:
/// recovery finds candidates, cleanup preserves anything not yet recovered.
///
/// Only orphans created within `recoveryWindow` are ever offered for recovery.
/// Older orphans stay on disk and keep following the retention rules that
/// already applied to them.
public enum InterruptedRecordingRecovery {
    // MARK: - Persistence (new keys; existing stored values are untouched)

    /// Filenames whose recovery needs another attempt next launch: persist
    /// failures, attempts skipped while busy, and files active during a scan.
    public static let pendingFilenamesKey = "storage.recovery.interrupted.pending_filenames.v1"
    /// Audio filenames the user deliberately deleted from the library.
    /// Recovery must not resurrect them; cleanup may delete them when old.
    public static let dismissedFilenamesKey = "storage.recovery.interrupted.dismissed_filenames.v1"
    /// Consecutive failed auto-recovery attempts per audio basename.
    public static let attemptCountsKey = "storage.recovery.interrupted.attempt_counts.v1"

    /// Orphans older than this are never offered for recovery.
    public static let recoveryWindow: TimeInterval = 7 * 86400
    /// Audio older than this without a referencing transcription is eligible
    /// for orphan deletion. Matches the previous cleanup behavior.
    public static let orphanAgeThreshold: TimeInterval = 86400
    /// Auto-recovery stops retrying a file after this many failed attempts.
    /// The file and its failed library entry stay for a manual retry.
    public static let maxAutoRecoveryAttempts = 3

    // MARK: - Recovery candidates

    public struct Candidate: Hashable, Sendable {
        public let url: URL
        public let createdAt: Date

        public init(url: URL, createdAt: Date) {
            self.url = url
            self.createdAt = createdAt
        }
    }

    /// Inputs for an orphan scan. Grouped so the scan stays a two-argument call.
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

    /// Finds audio files no saved transcription references.
    ///
    /// Skips files that belong to an active or in-flight transcription, files
    /// that are empty or unreadable (kept on disk, never deleted here), files
    /// the user deliberately deleted, and orphans older than the recovery
    /// window. Files pending a retry are always included. Results are sorted
    /// oldest-first for deterministic serial recovery.
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

    /// Per-file scan state for orphan detection. Used synchronously within a
    /// single scan, so it does not need to cross isolation domains.
    private struct OrphanScanner {
        let knownStandardized: Set<String>
        let activeStandardized: Set<String>
        let context: ScanContext
        let fileManager: FileManager

        /// Creation date when the file is a recovery candidate, nil when it
        /// must be skipped (referenced, active, dismissed, empty, unreadable,
        /// or older than the recovery window without a pending retry).
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

    /// Byte count for a usable audio file, or nil when the file is empty or
    /// unreadable. Never throws: unusable files are skipped, not deleted.
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

    // MARK: - Split recordings

    /// One logical recording reassembled from orphaned parts. `.all` meetings
    /// write separate `_mic` and `_sys` files and only merge them at stop, so
    /// a crash can orphan both parts with no merged file.
    public struct SplitGroup: Hashable, Sendable {
        /// Recording base name without the `_mic`/`_sys` suffix or extension.
        public let baseName: String
        public let microphoneURL: URL?
        public let systemURL: URL?
        /// An already-merged file for the same recording, when present.
        public let mergedURL: URL?
        public let createdAt: Date

        public var partURLs: [URL] {
            [microphoneURL, systemURL].compactMap(\.self)
        }

        /// Inferred capture purpose: a system-audio part means a meeting.
        /// Dictation recordings are saved by an unknown app as a lone
        /// microphone file, so only that combination means a dictation;
        /// anything else (a merged file alone, or a microphone part whose
        /// name does not mark it as a dictation) defaults to a meeting,
        /// because mic-only meeting recordings also produce `_mic` files.
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

    /// Groups orphaned candidates by recording base name. Parts sort
    /// deterministically by base name because candidates arrive sorted.
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

    /// Normalized identity of a recording for ownership checks: lowercase,
    /// no extension, no `-recovered` merge variant, no `_mic`/`_sys` part
    /// suffix. Files sharing a key belong to the same recording in any mix
    /// of parts and merged formats. Merge outputs created by recovery carry
    /// `-recovered`, so stripping it keeps every launch pointed at the same
    /// entry instead of duplicating it.
    public static func normalizedGroupKey(filename: String) -> String {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent.lowercased()
        let (baseName, _) = splitPartStem(stem)
        return stripRecoveredVariantSuffix(baseName)
    }

    /// Strips a trailing `-recovered` or `-recovered-N` merge-variant suffix.
    static func stripRecoveredVariantSuffix(_ stem: String) -> String {
        if let range = stem.range(of: "-recovered(-[0-9]+)?$", options: .regularExpression) {
            return String(stem[..<range.lowerBound])
        }
        return stem
    }

    /// Normalized group keys for referenced audio that lives inside the
    /// recordings directory. A group sharing a key with any of these is
    /// owned by an existing library entry (in any part or format) and must
    /// not gain a second entry. Paths outside the recordings directory can
    /// never collide with a group, so they are ignored.
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

    /// Merged-file extension for a group, taken from its parts so m4a
    /// recordings merge back to m4a instead of defaulting to wav.
    public static func mergedFileExtension(for group: SplitGroup) -> String {
        let ext = group.microphoneURL?.pathExtension ?? group.systemURL?.pathExtension ?? group.mergedURL?.pathExtension ?? "wav"
        let lowered = ext.lowercased()
        return ["m4a", "wav"].contains(lowered) ? lowered : "wav"
    }

    /// File name for a merged split group inside the recordings directory.
    /// Returns nil when the preferred name is taken; the caller then derives
    /// a `-recovered` variant instead of replacing it.
    public static func mergedOutputURL(for group: SplitGroup, in recordingsDirectory: URL) -> URL? {
        let output = recordingsDirectory
            .appendingPathComponent(group.baseName)
            .appendingPathExtension(mergedFileExtension(for: group))
        if FileManager.default.fileExists(atPath: output.path) {
            return nil
        }
        return output
    }

    // MARK: - Cleanup guard

    /// Whether the orphan sweep may delete a file. Anything recovery has not
    /// processed yet is preserved: pending retries, and unreferenced orphans
    /// inside the recovery window that no scan has claimed (user-dismissed
    /// files follow the normal age rule instead).
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

    // MARK: - Retry accounting

    /// Whether a file may be auto-recovered again this launch.
    public static func autoRetryAllowed(filename: String, attempts: [String: Int]) -> Bool {
        (attempts[filename] ?? 0) < maxAutoRecoveryAttempts
    }

    public static func recordingFailedAttempt(filename: String, attempts: [String: Int]) -> [String: Int] {
        var updated = attempts
        updated[filename, default: 0] += 1
        return updated
    }

    // MARK: - Store pruning

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

    /// Drops stored entries that can no longer apply: files gone from the
    /// recordings directory, and pending files that are referenced again.
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

    // MARK: - Recovery titles

    /// Whether a persisted library title marks a recovered recording. The
    /// title is user-visible, so both supported locales are recognized even
    /// after a locale change between launches.
    public static func isRecoveredTitle(_ title: String?) -> Bool {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return false
        }
        return trimmed == recoveredTitle()
            || trimmed == "Recovered recording"
            || trimmed == "Gravação recuperada"
    }

    // MARK: - User-facing text

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

    // MARK: - Stored state

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
        // Filter raw strings first: an empty path would resolve against the
        // current working directory and produce a bogus basename.
        let basenames = filenames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        guard !basenames.isEmpty else { return }
        var stores = loadStores(defaults: defaults)
        stores.dismissed.formUnion(basenames)
        saveStores(stores, defaults: defaults)
    }

    // MARK: - Private helpers

    public static func standardizedAudioPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func isAllowedAudioFile(_ url: URL) -> Bool {
        ["m4a", "wav"].contains(url.pathExtension.lowercased())
    }
}
