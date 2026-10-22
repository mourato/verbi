# Imported recording policy

## Decision

Imported recordings must be explicitly classified as either meeting recordings
or dictation/audio notes after file selection. The import flow must not silently
classify every imported file as a meeting.

Dictation/audio note remains the safe fallback for non-UI callers and legacy
call sites. Imported meeting recordings retain `CaptureOrigin.importedFile` while
using `CapturePurpose.meeting`; they may use meeting titles, meeting
post-processing, meeting conversation/Q&A, and meeting-history actions.

Imported dictations use `CapturePurpose.dictation` and retain dictation
behavior.

## Persistence and compatibility

Reuse the existing persisted `capturePurpose` field. This decision does not
require a Core Data migration.

## Maintenance

Future import, history, conversation, and metrics work must branch on explicit
capture purpose and must not infer meeting behavior solely from the imported
file application identity.

Source decision: `plans/archive/completed/003-imported-recording-decision.md`.
