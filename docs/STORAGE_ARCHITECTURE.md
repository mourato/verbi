# Storage Architecture

Local-first persistence for Verbi. Audio, transcripts, and notes stay on the Mac
unless the user configures a remote provider for a specific task.

## Overview

```
UI / ViewModels
  └─ FileSystemStorageService (facade, `StorageService` protocol)
       ├─ CoreDataStack (SQLite, thread-safe)
       │    ├─ CoreDataTranscriptionStorageRepository
       │    └─ CoreDataMeetingRepository
       └─ Files on disk (recordings, legacy JSON archive)
```

- Source of truth for metadata and transcripts: Core Data SQLite store in the
  app-support directory (`AppIdentity.appSupportBaseDirectory`, `<store>.sqlite`
  plus `-wal` / `-shm`).
- Source of truth for audio bytes: files under `recordingsDirectory`.
- Settings: `UserDefaults` via `AppSettingsStore`. Secrets: Keychain via
  `KeychainManager`. No CloudKit sync.

Key files:

- `Packages/VerbiCore/Sources/Data/Data/CoreData/CoreDataStack.swift`
- `Packages/VerbiCore/Sources/Data/Data/Repositories/CoreDataTranscriptionStorageRepository.swift`
- `Packages/VerbiCore/Sources/Data/Data/Repositories/CoreDataMeetingRepository.swift`
- `Packages/VerbiCore/Sources/Data/Services/StorageService/StorageService.swift`
- `Packages/VerbiCore/Sources/Data/Services/StorageService/LegacyMigration.swift`
- `Packages/VerbiCore/Sources/Data/Services/StorageService/RetentionCleanup*.swift`
- `Packages/VerbiCore/Sources/Data/Services/StorageService/PathValidation.swift`

## Core Data model

Current entities (managed-object classes in `Data/CoreData/`):

- `CaptureSessionMO` — one recorded or imported unit (meeting, dictation).
  Holds app origin, timing, `audioFilePath`, calendar link.
- `CaptureArtifactMO` — the persisted result of a processed capture. One
  session owns many artifacts. Holds text, processed content, canonical
  summary, model names, durations, lifecycle state.
- `CaptureArtifactSegmentMO` — timed segments of an artifact.
- `ModelPerformanceAttemptMO` — per-stage timing and model identity for
  transcription and post-processing, backfilled from legacy snapshots.

Relationships: Session 1—* Artifact 1—* Segment; Artifact 1—* PerformanceAttempt.

All writes go through `CoreDataStack.performBackgroundTask`. The main context
is read-only for UI. If the SQLite store cannot load, the stack installs an
in-memory fallback so the app keeps running without touching user data.

Frozen identifiers (entity names, attribute names, `Codable` raw values) must
not change: renaming them drops user data. Rename code symbols only.

## Migration strategy

Three one-way migrations, each guarded by a `UserDefaults` checkpoint so it
runs once:

1. Legacy JSON transcripts → Core Data (`LegacyMigration.swift`,
   `storage.migrations.legacy_json_transcriptions_to_coredata.v1`).
   Reads `*.json` from the legacy transcripts directory, saves each into Core
   Data, moves the source file to `legacy-json-archive/`. Legacy files are
   read but never written.
2. Legacy store location → current app-support location (`CoreDataStack`
   `migrateLegacyPersistentStoreIfNeeded`). Copies the `.sqlite` / `-wal` /
   `-shm` cluster only when the current store looks fresh and the legacy one
   looks richer. Backs up the current cluster to `*.pre-migration-<timestamp>`
   before replacing.
3. Sanitization and backfill (`sanitizeMockTranscriptionArtifactsIfNeeded`,
   `sanitizeMeetingOnlyPresentationDataIfNeeded`,
   `backfillModelPerformanceAttemptsIfNeeded`). Removes test artifacts,
   cleans presentation-only data, synthesizes performance attempts from old
   snapshots.

## Cleanup flow

- `cleanupTemporaryFiles(urls:)` — deletes explicit temp files after a
  recording or import finishes.
- `cleanupOldTranscriptions(olderThanDays:)` and
  `computeRetentionCleanupPreview` / `performRetentionCleanup` — age-based
  deletion with a preview object so Settings can show what will go away.
- `cleanupOrphanedRecordings` / `orphanedFilesToDelete` — scans
  `recordingsDirectory` for `wav` / `m4a` files with no referencing session
  and no active recovery claim, respecting creation date and the
  interrupted-recording recovery window.
- `InterruptedRecordingRecovery` owns the recovery claim so cleanup never
  deletes audio that a crashed session may still need.

All cleanup paths validate paths with `PathValidation.swift` (traversal and
container checks) before deleting.

## Backup and restore

There is no built-in backup UI and no cloud sync.

- What to back up: the whole app-support directory (SQLite cluster plus
  `recordings/`). Copying only the `.sqlite` file without `-wal` loses recent
  writes; copy the cluster together while the app is quit.
- What the app does itself: pre-migration copies (`*.pre-migration-*`) and
  the `legacy-json-archive/` folder are the only automatic backups.
- Restore: quit the app, replace the app-support directory contents, relaunch.
  The stack migrates a legacy location automatically when the rule above
  matches.

## Decisions

- Core Data over SwiftData, UserDefaults+JSON, or CloudKit: the app needs a
  thread-safe store with background writes, predicates for history search,
  and a stable on-disk format without a cloud dependency.
- Hybrid read (legacy JSON) / write (Core Data) during migration: lets old
  installs upgrade without loss, then converges to one writer.
- Files for audio, database for metadata: keeps large blobs out of SQLite
  and makes orphan cleanup a directory scan.
- Facade (`FileSystemStorageService`) over direct repository use: one place
  for sanitization checkpoints, logging, and path validation.
- No sync: privacy default. A future sync would need conflict rules for
  artifacts and segments and is out of scope.
