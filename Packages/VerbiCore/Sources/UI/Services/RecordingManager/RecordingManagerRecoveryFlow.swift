import Foundation
import VerbiCoreCommon
import VerbiCoreDomain

// MARK: - Interrupted Recovery Flow

/// Testable orchestration for interrupted-recording recovery.
///
/// All decision logic lives here and is driven by injected closures, so tests
/// cover the full flow with temp directories and fakes. Production wires the
/// closures to `RecordingManager` in `RecordingManagerRecovery`.
struct InterruptedRecoveryFlow: Sendable {
    struct StubRequest: Sendable {
        let audioURL: URL
        let groupPartURLs: [URL]
        let capturePurpose: CapturePurpose
        let title: String
        let startTime: Date
    }

    struct Dependencies: Sendable {
        var loadStores: @Sendable () -> InterruptedRecordingRecovery.Stores
        var saveStores: @Sendable (InterruptedRecordingRecovery.Stores) -> Void
        var listMetadata: @Sendable () async throws -> [TranscriptionMetadata]
        var loadArtifact: @Sendable (UUID) async -> CaptureArtifact?
        var activeAudioPaths: @Sendable () async -> Set<String>
        var persistStub: @Sendable (StubRequest) async -> UUID?
        var retryArtifact: @Sendable (CaptureArtifact) async -> Bool
        var mergeSplitParts: @Sendable ([URL], URL) async -> URL?
        var audioDuration: @Sendable (URL) async -> Double?
        var isBusy: @Sendable () async -> Bool
        var notifySummary: @Sendable (Int) async -> Void
        var now: @Sendable () -> Date
    }

    enum GroupResolution: Sendable {
        case use(audioURL: URL, createdOutput: URL?)
        case ownedElsewhere
        case unreadable
    }

    struct ResolvedGroupAudio: Sendable {
        let group: InterruptedRecordingRecovery.SplitGroup
        let audioURL: URL
        let createdOutput: URL?
    }

    let io: Dependencies

    /// Runs one recovery pass over the recordings directory.
    /// - Returns: The number of newly recovered files (only successes count).
    func run(recordingsDirectory: URL, fileManager: FileManager = .default) async -> Int {
        let now = io.now()
        var stores = io.loadStores()

        let metadata: [TranscriptionMetadata]
        do {
            metadata = try await io.listMetadata()
        } catch {
            AppLogger.error(
                "Interrupted recovery scan failed",
                category: .recordingManager,
                error: error,
                extra: ["step": "load"]
            )
            return 0
        }

        let activePaths = await io.activeAudioPaths()
        let candidates = InterruptedRecordingRecovery.recoverableOrphans(
            in: recordingsDirectory,
            context: InterruptedRecordingRecovery.ScanContext(
                knownAudioPaths: Set(metadata.compactMap(\.audioFilePath)),
                activeAudioPaths: activePaths,
                dismissedFilenames: stores.dismissed,
                pendingFilenames: stores.pending,
                now: now
            ),
            fileManager: fileManager
        )
        stores = trackActiveRecordings(
            stores: stores,
            metadata: metadata,
            activePaths: activePaths,
            recordingsDirectory: recordingsDirectory,
            fileManager: fileManager
        )

        let referencedKeys = InterruptedRecordingRecovery.referencedGroupKeys(
            audioPaths: Set(metadata.compactMap(\.audioFilePath)),
            recordingsDirectory: recordingsDirectory
        )
        var groups: [InterruptedRecordingRecovery.SplitGroup] = []
        for group in InterruptedRecordingRecovery.groupSplitParts(candidates) {
            let key = InterruptedRecordingRecovery.normalizedGroupKey(filename: group.baseName)
            if referencedKeys.contains(key) {
                // Owned groups are handled through their existing entry;
                // release their files from pending so they do not wait forever.
                let ownedFilenames = Set(([group.mergedURL].compactMap(\.self) + group.partURLs).map(\.lastPathComponent))
                stores.pending.subtract(ownedFilenames)
            } else {
                groups.append(group)
            }
        }

        var recoveredCount = 0
        for group in groups {
            let recovered = await processGroup(group, recordingsDirectory: recordingsDirectory, stores: &stores, fileManager: fileManager)
            recoveredCount += recovered ? 1 : 0
        }

        await retryPreviouslyFailed(metadata: metadata, stores: &stores)

        io.saveStores(stores)
        if recoveredCount > 0 {
            AppLogger.info(
                "Interrupted recordings recovered",
                category: .recordingManager,
                extra: ["recoveredCount": "\(recoveredCount)"]
            )
            await io.notifySummary(recoveredCount)
        }
        return recoveredCount
    }

    // MARK: - Active tracking (B1)

    /// Prunes stale store entries and remembers files active during this scan
    /// so a crash before the next launch still recovers them.
    private func trackActiveRecordings(
        stores: InterruptedRecordingRecovery.Stores,
        metadata: [TranscriptionMetadata],
        activePaths: Set<String>,
        recordingsDirectory: URL,
        fileManager: FileManager
    ) -> InterruptedRecordingRecovery.Stores {
        let existing = Set(
            (try? fileManager.contentsOfDirectory(
                at: recordingsDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))?.map(\.lastPathComponent) ?? []
        )
        let referenced = Set(metadata.compactMap(\.audioFilePath).map {
            URL(fileURLWithPath: $0).lastPathComponent
        })
        var updated = InterruptedRecordingRecovery.prunedStores(
            stores,
            existingFilenames: existing,
            referencedFilenames: referenced
        )
        let activeFilenames = Set(activePaths.map { URL(fileURLWithPath: $0).lastPathComponent })
        updated.pending.formUnion(activeFilenames.intersection(existing))
        return updated
    }

    // MARK: - Fresh orphans

    /// Recovers one split group. Returns true only when the file was
    /// transcribed successfully and now counts toward the summary.
    private func processGroup(
        _ group: InterruptedRecordingRecovery.SplitGroup,
        recordingsDirectory: URL,
        stores: inout InterruptedRecordingRecovery.Stores,
        fileManager: FileManager
    ) async -> Bool {
        let groupFilenames = Set(([group.mergedURL].compactMap(\.self) + group.partURLs).map(\.lastPathComponent))
        if groupFilenames.allSatisfy({ !InterruptedRecordingRecovery.autoRetryAllowed(filename: $0, attempts: stores.attempts) }) {
            // Every file already used its attempts: leave the files on disk
            // without probing or counting them again.
            stores.pending.subtract(groupFilenames)
            return false
        }
        let isBusy = await io.isBusy()
        guard !isBusy else {
            stores.pending.formUnion(groupFilenames)
            return false
        }

        let resolution = await resolveGroupAudio(group, recordingsDirectory: recordingsDirectory, fileManager: fileManager)
        switch resolution {
        case .ownedElsewhere:
            // Owned by another library entry (failed-retry pass handles it).
            stores.pending.subtract(groupFilenames)
            return false
        case .unreadable:
            // Unreadable files stay on disk with no entry. Count attempts so
            // they do not stay pending forever.
            recordSkippedGroupAttempt(groupFilenames: groupFilenames, stores: &stores)
            return false
        case let .use(audioURL, createdOutput):
            return await persistAndRetryGroup(
                ResolvedGroupAudio(
                    group: group,
                    audioURL: audioURL,
                    createdOutput: createdOutput
                ),
                groupFilenames: groupFilenames,
                stores: &stores
            )
        }
    }

    private func resolveGroupAudio(
        _ group: InterruptedRecordingRecovery.SplitGroup,
        recordingsDirectory: URL,
        fileManager: FileManager
    ) async -> GroupResolution {
        if let mergedURL = group.mergedURL, await isReadable(mergedURL) {
            return .use(audioURL: mergedURL, createdOutput: nil)
        }

        let readableParts = await readableURLs(group.partURLs)

        guard readableParts.count >= 2 else {
            if let single = readableParts.first {
                return .use(audioURL: single, createdOutput: nil)
            }
            return .unreadable
        }

        if let output = InterruptedRecordingRecovery.mergedOutputURL(for: group, in: recordingsDirectory),
           let merged = await io.mergeSplitParts(readableParts, output)
        {
            return .use(audioURL: merged, createdOutput: output)
        }

        let preferredOutput = recordingsDirectory
            .appendingPathComponent(group.baseName)
            .appendingPathExtension(InterruptedRecordingRecovery.mergedFileExtension(for: group))
        if fileManager.fileExists(atPath: preferredOutput.path), await isReadable(preferredOutput) {
            // The merged name is taken by an owned file; rely on the
            // failed-retry pass instead of duplicating the entry.
            return .ownedElsewhere
        }

        if let fallback = firstAvailableVariantURL(for: group, in: recordingsDirectory, fileManager: fileManager),
           let merged = await io.mergeSplitParts(readableParts, fallback)
        {
            return .use(audioURL: merged, createdOutput: fallback)
        }

        if let single = readableParts.first {
            return .use(audioURL: single, createdOutput: nil)
        }
        return .unreadable
    }

    private func firstAvailableVariantURL(
        for group: InterruptedRecordingRecovery.SplitGroup,
        in recordingsDirectory: URL,
        fileManager: FileManager
    ) -> URL? {
        for index in 1 ... 100 {
            let candidate = recordingsDirectory
                .appendingPathComponent("\(group.baseName)-recovered\(index == 1 ? "" : "-\(index)")")
                .appendingPathExtension(InterruptedRecordingRecovery.mergedFileExtension(for: group))
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    private func persistAndRetryGroup(
        _ resolved: ResolvedGroupAudio,
        groupFilenames: Set<String>,
        stores: inout InterruptedRecordingRecovery.Stores
    ) async -> Bool {
        // S1: reload referenced paths right before persisting.
        guard let freshMetadata = try? await io.listMetadata() else {
            return false
        }
        let freshKnownPaths = Set(freshMetadata.compactMap(\.audioFilePath).map {
            InterruptedRecordingRecovery.standardizedAudioPath($0)
        })
        if freshKnownPaths.contains(resolved.audioURL.standardizedFileURL.path) {
            return false
        }

        let filename = resolved.audioURL.lastPathComponent
        guard InterruptedRecordingRecovery.autoRetryAllowed(filename: filename, attempts: stores.attempts) else {
            stores.pending.remove(filename)
            return false
        }
        let isBusy = await io.isBusy()
        guard !isBusy else {
            stores.pending.formUnion(groupFilenames)
            return false
        }

        guard let transcriptionID = await io.persistStub(StubRequest(
            audioURL: resolved.audioURL,
            groupPartURLs: resolved.group.partURLs,
            capturePurpose: resolved.group.inferredCapturePurpose,
            title: InterruptedRecordingRecovery.recoveredTitle(),
            startTime: resolved.group.createdAt
        )) else {
            stores.pending.formUnion(groupFilenames)
            AppLogger.error(
                "Interrupted recovery persist failed",
                category: .recordingManager,
                extra: ["filename": filename, "step": "persist"]
            )
            return false
        }

        guard let stub = await io.loadArtifact(transcriptionID) else {
            stores.pending.formUnion(groupFilenames)
            AppLogger.error(
                "Interrupted recovery persist failed",
                category: .recordingManager,
                extra: ["filename": filename, "step": "reload"]
            )
            return false
        }

        if await io.retryArtifact(stub) {
            stores.pending.subtract(groupFilenames)
            if let createdOutput = resolved.createdOutput {
                stores.pending.remove(createdOutput.lastPathComponent)
            }
            stores.attempts.removeValue(forKey: filename)
            return true
        }

        stores.attempts = InterruptedRecordingRecovery.recordingFailedAttempt(filename: filename, attempts: stores.attempts)
        if InterruptedRecordingRecovery.autoRetryAllowed(filename: filename, attempts: stores.attempts) {
            stores.pending.formUnion(groupFilenames)
        } else {
            stores.pending.subtract(groupFilenames)
        }
        AppLogger.error(
            "Interrupted recovery retry failed",
            category: .recordingManager,
            extra: ["filename": filename, "step": "transcribe"]
        )
        return false
    }

    // MARK: - Previously failed recoveries

    private func retryPreviouslyFailed(
        metadata: [TranscriptionMetadata],
        stores: inout InterruptedRecordingRecovery.Stores
    ) async {
        let fileManager = FileManager.default
        for item in metadata where item.lifecycleState == .failed {
            guard let audioPath = item.audioFilePath, fileManager.fileExists(atPath: audioPath) else {
                continue
            }
            guard let transcription = await io.loadArtifact(item.id),
                  InterruptedRecordingRecovery.isRecoveredTitle(transcription.meeting.title)
            else {
                continue
            }
            let filename = URL(fileURLWithPath: audioPath).lastPathComponent
            guard InterruptedRecordingRecovery.autoRetryAllowed(filename: filename, attempts: stores.attempts) else {
                stores.pending.remove(filename)
                continue
            }
            let isBusy = await io.isBusy()
            guard !isBusy else {
                continue
            }
            guard await isReadable(URL(fileURLWithPath: audioPath)) else {
                continue
            }
            if await io.retryArtifact(transcription) {
                stores.attempts.removeValue(forKey: filename)
            } else {
                stores.attempts = InterruptedRecordingRecovery.recordingFailedAttempt(filename: filename, attempts: stores.attempts)
                if !InterruptedRecordingRecovery.autoRetryAllowed(filename: filename, attempts: stores.attempts) {
                    stores.pending.remove(filename)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Counts an attempt for unreadable group files so they do not stay
    /// pending forever, and drops capped files from pending.
    private func recordSkippedGroupAttempt(
        groupFilenames: Set<String>,
        stores: inout InterruptedRecordingRecovery.Stores
    ) {
        for filename in groupFilenames {
            stores.attempts = InterruptedRecordingRecovery.recordingFailedAttempt(filename: filename, attempts: stores.attempts)
            if !InterruptedRecordingRecovery.autoRetryAllowed(filename: filename, attempts: stores.attempts) {
                stores.pending.remove(filename)
            }
        }
    }

    private func readableURLs(_ urls: [URL]) async -> [URL] {
        var readable: [URL] = []
        for url in urls {
            guard await isReadable(url) else {
                continue
            }
            readable.append(url)
        }
        return readable
    }

    private func isReadable(_ url: URL) async -> Bool {
        await io.audioDuration(url) != nil
    }
}
