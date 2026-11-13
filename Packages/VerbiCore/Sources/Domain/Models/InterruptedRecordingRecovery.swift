import Foundation
import VerbiCoreCommon

/// Launch-time recovery for audio files orphaned by a crash or forced quit.
///
/// A crash can leave a finished audio file in the recordings directory with no
/// saved transcription referencing it. The retention orphan sweep must never
/// delete such a file before recovery has seen it, so both flows share the
/// helpers here: recovery finds candidates, cleanup preserves anything
/// recovery has not processed yet.
public enum InterruptedRecordingRecovery {
    // MARK: - Persistence (new keys; existing stored values are untouched)

    /// Filenames whose recovery persist failed and must be retried next launch.
    public static let pendingFilenamesKey = "storage.recovery.interrupted.pending_filenames.v1"
    /// When the last recovery scan completed. Orphans created after this date
    /// never had a chance to be recovered, so cleanup preserves them.
    public static let lastScanDateKey = "storage.recovery.interrupted.last_scan.v1"
    /// Audio filenames the user deliberately deleted from the library.
    /// Recovery must not resurrect them; cleanup may delete them when old.
    public static let dismissedFilenamesKey = "storage.recovery.interrupted.dismissed_filenames.v1"

    /// Audio older than this without a referencing transcription is eligible
    /// for orphan deletion. Matches the previous cleanup behavior.
    public static let orphanAgeThreshold: TimeInterval = 86400

    private static let storedSetLimit = 500

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
        public let lastScanDate: Date?
        public let pendingFilenames: Set<String>

        public init(
            knownAudioPaths: Set<String> = [],
            activeAudioPaths: Set<String> = [],
            dismissedFilenames: Set<String> = [],
            lastScanDate: Date? = nil,
            pendingFilenames: Set<String> = []
        ) {
            self.knownAudioPaths = knownAudioPaths
            self.activeAudioPaths = activeAudioPaths
            self.dismissedFilenames = dismissedFilenames
            self.lastScanDate = lastScanDate
            self.pendingFilenames = pendingFilenames
        }
    }

    /// Finds audio files no saved transcription references.
    ///
    /// Skips files that belong to an active recording, files that are empty or
    /// unreadable (kept on disk, never deleted here), files the user
    /// deliberately deleted, and files a previous scan already saw without
    /// recovering (their age shows they predate the watermark instead of
    /// predating a crash). Results are sorted oldest-first for deterministic
    /// serial recovery.
    public static func recoverableOrphans(
        in recordingsDirectory: URL,
        context: ScanContext,
        fileManager: FileManager = .default
    ) -> [Candidate] {
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

        let scanner = OrphanScanner(
            knownStandardized: Set(context.knownAudioPaths.map(standardizePath(_:))),
            activeStandardized: Set(context.activeAudioPaths.map(standardizePath(_:))),
            context: context,
            resourceKeys: resourceKeys,
            fileManager: fileManager
        )

        var candidates: [Candidate] = []
        for fileURL in files where isAllowedAudioFile(fileURL) {
            guard let createdAt = scanner.recoveryDate(for: fileURL) else {
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
        let resourceKeys: [URLResourceKey]
        let fileManager: FileManager

        /// Creation date when the file is a recovery candidate, nil when it
        /// must be skipped (referenced, active, dismissed, empty, unreadable,
        /// or already seen by a previous scan).
        func recoveryDate(for fileURL: URL) -> Date? {
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

            let createdAt = values?.creationDate ?? values?.contentModificationDate ?? Date()
            guard context.pendingFilenames.contains(fileURL.lastPathComponent)
                || context.lastScanDate == nil
                || isNewSinceLastScan(createdAt)
            else {
                return nil
            }
            return createdAt
        }

        private func isNewSinceLastScan(_ date: Date) -> Bool {
            guard let lastScanDate = context.lastScanDate else {
                return true
            }
            return date > lastScanDate
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

    // MARK: - Cleanup guard

    /// Whether the orphan sweep may delete a file. Anything recovery has not
    /// processed yet (pending retry, or created after the last scan) is
    /// preserved, as are files without a usable creation date.
    public static func shouldDeleteOrphanedFile(
        filename: String,
        createdAt: Date?,
        isReferenced: Bool,
        pendingFilenames: Set<String>,
        lastScanDate: Date?,
        now: Date = Date()
    ) -> Bool {
        guard !isReferenced else { return false }
        guard !pendingFilenames.contains(filename) else { return false }
        guard let createdAt else { return false }
        guard now.timeIntervalSince(createdAt) > orphanAgeThreshold else { return false }
        guard let lastScanDate else { return false }
        guard createdAt <= lastScanDate else { return false }
        return true
    }

    // MARK: - Failed-recovery retry

    /// Whether library metadata describes a failed recovery attempt whose
    /// audio may still be on disk. Matched by lifecycle state plus the
    /// recovered title in either supported language, so a locale change
    /// between launches does not lose the retry.
    public static func isFailedRecoveryMetadata(_ metadata: TranscriptionMetadata) -> Bool {
        guard metadata.lifecycleState == .failed else { return false }
        return isRecoveredTitle(metadata.meetingTitle)
    }

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

    public static func loadLastScanDate(defaults: UserDefaults = .standard) -> Date? {
        defaults.object(forKey: lastScanDateKey) as? Date
    }

    public static func saveLastScanDate(_ date: Date, defaults: UserDefaults = .standard) {
        defaults.set(date, forKey: lastScanDateKey)
    }

    public static func loadPendingFilenames(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: pendingFilenamesKey) ?? [])
    }

    public static func savePendingFilenames(_ filenames: Set<String>, defaults: UserDefaults = .standard) {
        defaults.set(Array(filenames.sorted().suffix(storedSetLimit)), forKey: pendingFilenamesKey)
    }

    public static func loadDismissedFilenames(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: dismissedFilenamesKey) ?? [])
    }

    public static func noteUserDeletedAudioFilenames(_ filenames: [String], defaults: UserDefaults = .standard) {
        // Filter raw strings first: an empty path would resolve against the
        // current working directory and produce a bogus basename.
        let basenames = filenames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        guard !basenames.isEmpty else { return }
        let updated = loadDismissedFilenames(defaults: defaults).union(basenames)
        defaults.set(Array(updated.sorted().suffix(storedSetLimit)), forKey: dismissedFilenamesKey)
    }

    // MARK: - Private helpers

    private static func isAllowedAudioFile(_ url: URL) -> Bool {
        ["m4a", "wav"].contains(url.pathExtension.lowercased())
    }

    private static func standardizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
