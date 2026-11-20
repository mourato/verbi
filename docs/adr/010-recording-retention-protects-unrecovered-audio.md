# ADR 010: Retention never deletes audio that recovery has not processed

**Status:** Accepted
**Date:** 2026-11-20

## Context

Verbi deletes old audio on a retention schedule and recovers recordings interrupted by a crash. Both touch the same files, and the recording folder is user-configurable.

## Decision

- An existing file at the merge output URL is deleted only when it is not also one of the input recordings.
- When a restart would recreate a file that already holds the session's audio, the recorder reports the failure and keeps the audio.
- A recording directory must resolve under the user's home directory or /Volumes.
- Path traversal is checked on the original path before resolution, because resolution collapses .. and hides it.
- Retention and orphan deletion never remove an unreferenced recording that interrupted-recording recovery still has pending.
- The orphan sweep never deletes files recovery has not processed: pending retries and unclaimed files inside the recovery window.
- Retention cleanup deletes only old audio files on disk and always keeps the transcription records.
- Importing a dictionary archive never overwrites an existing conflicting destination and keeps each valid variant even when another variant of the same rule already exists.
- Recovery and retention share one candidate set so cleanup never deletes a crashed recording before recovery has seen it.
- The byte-count helper never throws: unusable files are skipped, not deleted.

## Consequences

Each rule above also lives in `docs/CODE_CONSTRAINTS.md` beside its owning file, because source code carries no comments. Change a rule, its code, and this ADR together.

The home-directory check is a string prefix today, so a sibling folder that shares the prefix passes; issue #221 tracks the fix.

## Rejected or deferred

Running retention independently of recovery was rejected, because cleanup could delete a crashed recording before recovery saw it.

## References and license

Recovered from code comments removed by the comment cleanup; no external material.

## Affected surfaces

- `Packages/VerbiCore/Sources/Audio/Services/AudioMerger.swift`
- `Packages/VerbiCore/Sources/Audio/Services/AudioRecorder/Validation.swift`
- `Packages/VerbiCore/Sources/Data/Services/StorageService/PathValidation.swift`
- `Packages/VerbiCore/Sources/Data/Services/StorageService/RetentionCleanup.swift`
- `Packages/VerbiCore/Sources/Data/Services/StorageService/StorageService.swift`
- `Packages/VerbiCore/Sources/Domain/Models/DictionaryArchive.swift`
- `Packages/VerbiCore/Sources/Domain/Models/InterruptedRecordingRecovery.swift`
