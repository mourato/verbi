# Storage architecture and migration policy

This document describes the persistence behavior currently shipped by Verbi. It is a reference for changes to Core Data, recordings, settings, cleanup, credentials, and migration code. It does not promise CloudKit, FRC, FTS, backup, or cross-device synchronization.

## Boundary map

```text
Capture / transcription workflow
            │
            ▼
      StorageService
            │
            ├── CoreDataTranscriptionStorageRepository
            │         │
            │         └── CoreDataStack ── SQLite store
            │
            └── recordingsDirectory ── WAV/M4A files

Settings ── UserDefaults
Credentials ── KeychainManager / KeychainProvider
```

The canonical owners are:

| Concern | Owner | Contract |
| --- | --- | --- |
| Persistent store, contexts, loading, fallback, store migration | [`CoreDataStack.swift`](../../Packages/MeetingAssistantCore/Sources/Data/Data/CoreData/CoreDataStack.swift) | Owns the `NSPersistentContainer`, SQLite URL, background contexts, automatic migration settings, and one-time Core Data maintenance. |
| Domain/Core Data mapping and repository queries | [`CoreDataTranscriptionStorageRepository.swift`](../../Packages/MeetingAssistantCore/Sources/Data/Data/Repositories/CoreDataTranscriptionStorageRepository.swift) | Maps `TranscriptionEntity` and related domain values to `MeetingMO`, `TranscriptionMO`, and `ModelPerformanceAttemptMO`. Performs repository work through background contexts. |
| Application storage facade and recording files | [`StorageService.swift`](../../Packages/MeetingAssistantCore/Sources/Data/Services/StorageService/StorageService.swift) and its [`StorageService/`](../../Packages/MeetingAssistantCore/Sources/Data/Services/StorageService) extensions | Exposes async save/load/delete APIs, creates recording URLs, validates configured paths, migrates legacy JSON, and owns retention cleanup orchestration. |
| Core Data schema | [`CoreDataModel.swift`](../../Packages/MeetingAssistantCore/Sources/Data/Data/CoreData/CoreDataModel.swift) | Builds the programmatic model. Current model version is `1.6`; the stack requests automatic lightweight migration and inferred mapping where Core Data can provide it. |
| Preferences and migration checkpoints | [`AppSettingsStore/`](../../Packages/MeetingAssistantCore/Sources/Infrastructure/Models/AppSettingsStore) | Stores lightweight settings in `UserDefaults`, preserves stable keys, and performs legacy-domain/default migrations during initialization. |
| Secrets | [`KeychainManager.swift`](../../Packages/MeetingAssistantCore/Sources/Infrastructure/Services/KeychainManager.swift) | Stores provider, registration, and transcription credentials through `KeychainProvider`/`DefaultKeychainProvider`; secrets do not belong in UserDefaults, Core Data, or plain files. |

## Data locations and models

`AppIdentity.appSupportBaseDirectory()` resolves the application-support root to the current `Verbi` directory and migrates legacy `Prisma` / `MeetingAssistant` directories (newest first) when the current directory does not yet exist. `FileSystemStorageService` places the default recording directory below that root and keeps the legacy JSON directory at `transcripts/` during migration.

Core Data currently contains:

- `MeetingMO`, including meeting identity, capture purpose, presentation metadata, and an optional audio-file path.
- `TranscriptionMO`, including raw/transcribed/processed content, segments, lifecycle state, summary fields, and relationships to a meeting and performance attempts.
- `TranscriptionSegmentMO` for speaker/timing segments.
- `ModelPerformanceAttemptMO` for immutable transcription and post-processing attempts. Attempts are append-only history; aggregate dashboard queries are separate views over that history.
- `TranscriptionMO.executionProvenanceData` and `ModelPerformanceAttemptMO.executionProvenanceData` hold optional JSON-encoded `ExecutionProvenance`. It contains request/model/vocabulary and post-processing identity metadata only; it never contains credentials, raw prompts, transcript text, or provider responses.

The normal application path is:

1. Capture/transcription code produces a domain `Transcription`.
2. `FileSystemStorageService` converts it to a `TranscriptionEntity` and delegates to `CoreDataTranscriptionStorageRepository`.
3. The repository creates or updates the related managed objects in a background context and saves the context.
4. Audio is not embedded as the primary record payload. The meeting stores a validated file path under the recordings directory.
5. View models request full models or bounded metadata queries through `StorageService`; they do not own Core Data contexts.

## Concurrency and failure boundaries

- `CoreDataStack` is `Sendable`. `mainContext` is configured for UI-facing work; `backgroundContext` creates a private context with merge policies and inaccessible-fault cleanup enabled.
- Repository operations use `performBackgroundTask` and are exposed as `async throws`. Do not perform blocking Core Data fetches directly from SwiftUI view bodies or main-actor presentation code.
- The persistent store is loaded synchronously during stack initialization so startup knows whether the primary store loaded. If loading fails, the stack logs a fault and installs an in-memory fallback. This keeps the process usable but is not a persistence success: callers and diagnostics must treat the fallback as degraded storage.
- Missing/corrupt individual records should produce an absent value or a thrown repository error according to the existing API. Do not silently replace a failed migration with destructive defaults.

## Migration policy

All migrations must be deterministic, idempotent, recoverable, and checkpointed only after successful completion. New migrations should preserve the existing repository/storage abstraction and add tests for a fresh run and a no-op re-run.

Model `1.6` adds only optional binary attributes for execution provenance. Existing SQLite stores therefore use inferred lightweight migration; legacy rows remain nil rather than receiving guessed Settings values. Missing or malformed provenance decodes as unavailable, so history remains loadable and retry uses the documented compatibility fallback. The migration adds no backfill or checkpoint and is safe to load repeatedly.

### Application Support and SQLite store

`CoreDataStack` searches legacy store candidates for `MeetingAssistant.sqlite` and a same-directory legacy filename. It migrates only when the current store is absent, or when the current store looks fresh and the legacy store is richer. Before replacement it backs up existing SQLite cluster files (`.sqlite`, `-shm`, and `-wal`) with a `.pre-migration-<timestamp>` suffix. It then replaces the destination cluster and lets Core Data perform its configured automatic/lightweight migration.

The migration logs failures and leaves the legacy source available when the replacement cannot complete. Do not delete a legacy store or mark a migration complete before the destination is usable.

### Legacy JSON transcriptions

`FileSystemStorageService.migrateLegacyJSONTranscriptionsToCoreDataIfNeeded()` is a one-time, idempotent migration:

- Reads root-level `.json` files from the legacy `transcripts/` directory.
- Decodes and upserts each transcription by its stable ID through the repository.
- Moves successfully migrated files to `transcripts/legacy-json-archive/`.
- Sets `storage.migrations.legacy_json_transcriptions_to_coredata.v1` only when no root-level JSON files remain.
- Leaves failed files in place for a later retry and reports migrated/failed counts without logging transcript contents.

### UserDefaults and settings

`AppSettingsStore` preserves existing keys and default precedence. Initialization first migrates the legacy `com.meetingassistant.app` domain into the current bundle domain, guarded by `migrations.user_defaults_domain.v1`, then loads and normalizes settings. One-time backfills for audio, web targets, provider registrations, and related settings are owned by the existing `AppSettingsStore` extensions.

Changing a setting key, enum raw value, default, or migration checkpoint is a compatibility change. Add a forward-migration test and a no-op re-run test before changing it.

### Post-load Core Data maintenance

The repository invokes checkpointed maintenance before normal reads/writes where required by the current implementation:

- remove mock transcription artifacts;
- sanitize meeting-only presentation data;
- backfill missing model-performance attempts from persisted transcription snapshots.

These operations use `UserDefaults` checkpoint keys and mark completion only after the background operation succeeds. Backfills must preserve existing snapshots and must not collapse retry/reprocess attempts.

## Recordings and cleanup

`recordingsDirectory` is either the validated user-selected absolute path or the default app-support recordings directory. [`PathValidation.swift`](../../Packages/MeetingAssistantCore/Sources/Data/Services/StorageService/PathValidation.swift) rejects traversal and restricts configured paths to the user home directory or `/Volumes/`. Cleanup additionally requires candidate files to be inside the normalized recordings directory and to use an allowed audio extension.

Retention is a two-phase operation:

1. `computeRetentionCleanupPreview` queries metadata, resolves audio paths, compares them with the retention cutoff, and returns deterministic candidates with byte sizes.
2. `performRetentionCleanup` deletes only validated audio files from the supplied preview.

`cleanupOldTranscriptions` currently removes old recording files and then removes stale orphaned recordings. It does not delete Core Data transcription records; `RetentionCleanupResult.deletedTranscriptionCount` is currently zero. The UI should show the preview before destructive cleanup and should not imply that history records were removed.

Temporary files are deleted explicitly by `cleanupTemporaryFiles`. Stale partial/finalizing dictation checkpoints are removed by the storage maintenance task. Failed file deletion is logged and does not justify deleting the associated history record.

## Credentials and privacy boundary

API keys and tokens are stored through [`KeychainManager.swift`](../../Packages/MeetingAssistantCore/Sources/Infrastructure/Services/KeychainManager.swift), using provider-scoped, registration-scoped, or transcription-provider keys. Keychain migration preserves legacy service identifiers and the current consolidated blob version. `errSecItemNotFound` represents absence; other Keychain statuses are failures. Secret values must never be logged or persisted in UserDefaults, Core Data, JSON, or recording files.

Meeting history, transcript content, metadata, and audio are persisted locally in the app-support/Core Data and recording-file boundaries described above. The app may send content to an explicitly selected remote transcription or language-model provider as part of a configured execution path; that network behavior is separate from persistence and must not be described as local storage synchronization.

There is currently no shipped CloudKit/iCloud synchronization, automatic backup, or cross-device history replication. The current decision is documented in [`cloudkit-boundary-decision-2026-07-12.md`](../reports/cloudkit-boundary-decision-2026-07-12.md): reject CloudKit for sensitive history, defer a narrow preference allowlist, and prioritize local export/import. FRC/FTS and incremental-history changes remain measurement-gated follow-ups in issues #97 and #98; the current implementation uses bounded metadata queries and notification-driven reloads.

## Change checklist

When changing persistence:

1. Keep mechanism ownership in the existing stack, repository, storage, settings, or Keychain owner.
2. State the forward-migration invariant and the no-op re-run behavior.
3. Preserve recovery: back up or retain legacy data before destructive replacement.
4. Add isolated tests for fresh migration, re-run, partial/legacy records, and cleanup safety.
5. Verify background-context usage and avoid blocking the main actor.
6. Update this document when paths, schemas, checkpoints, cleanup semantics, or credential ownership change.
