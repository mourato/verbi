# ADR 007: Domain naming debt and rename policy

**Status:** Accepted — phase 3 implemented
**Date:** 2026-10-21  
**Reference:** [GLOSSARY.md](../../GLOSSARY.md)

## Context

Verbi started as MeetingAssistant, an app that only recorded meetings. It
later gained dictation, an assistant voice mode, cloud ASR providers, and AI
post-processing. Most names did not follow. A dictation creates a `Meeting`
through `createMeeting`, and `capturePurpose` is the only thing that tells
the two apart.

A read-only naming audit (2026-10-21) found about 70 names that no longer
match behavior. The main clusters:

1. **"Meeting" means any capture session.** `Meeting`, `MeetingEntity`,
   `MeetingMO`, `currentMeeting`, `meetingState`/`MeetingState`,
   `createMeeting` (in `RecordingManager` and `RecordingActor`),
   `MeetingRepository`. `MeetingApp` is a capture origin with non-app cases
   (`importedFile`, `unknown`) and has a duplicate, `DomainMeetingApp`.
   `MeetingType` is a summary strategy that is also stored on dictations.
   `supportsMeetingConversation` repeats `capturePurpose == .meeting` in five
   types.
2. **One capture-mode axis, five enums.** `CapturePurpose`,
   `IntelligenceKernelMode`, `TranscriptionExecutionMode`, `ActiveMode`, and
   `RecordingMode`, with conversion helpers between them.
3. **"Transcription" names a larger aggregate.** `Transcription`,
   `TranscriptionEntity`, and `TranscriptionMO` hold the transcript plus
   post-processing, summary, prompts, context, and conversation.
   `TranscriptionRepository` is an ASR client, not storage.
   `TranscriptionSettingsViewModel` is the transcription library.
   `TranscriptionClient` routes four ASR backends, but its doc says
   "local FluidAudio". `cleanupOldTranscriptions` and
   `autoDeleteTranscriptions` delete only audio.
4. **Post-processing has three names.** `postProcessing*`, `enhancements*`,
   and the intelligence kernel. `AIProvider` is LLM-only but shares case
   names with the ASR `TranscriptionProvider`.
5. **Three dictation routing models.** `DictationStyleTarget`,
   `DictationAppRule`, and `WebContextTarget` (key `markdownWebTargets`).
6. **MeetingAssistant identity in build artifacts.** Package and modules
   `MeetingAssistantCore*` (about 1,300 imports), Xcode target and scheme,
   `MeetingAssistantApp`, test target, the queue label
   `"MeetingAssistant.systemAudioCapture"`.
7. **Dead code and leftovers.** `FluidAIProvider` and `FluidAudioProvider`
   (no production callers), the `TranscriptionProvider` protocol (reported
   without conformers), `ServiceStatusResponse` and `ServiceState` from the
   removed local HTTP server, `RetentionCleanupTranscriptionCandidate`
   (always empty), the empty `MeetingAssistantAI/` folder still referenced by
   `scripts/scope-check.sh`.
8. **Settings UI names.** `*SettingsTab` types are pages with their own
   navigation. Aliased destinations (`.history`/`.transcriptions`,
   `.vocabulary`/`.dictionary`, `.models`/`.intelligence`,
   `.assistant`/`.integrations`). `StylesSettingsTab` edits dictation modes.
   `SmartShortcutHandler` is a shortcut-engine adapter.
9. **Small defects found during the audit.** Key
   `automaticAutomaticMeetingRecordingConfirmationDelay` repeats a word.
   `TranscriptionStatus.statusMessage` hardcodes pt-BR strings.
   `RecordingSourceFilter` filters capture purpose, not `RecordingSource`.

Only the high-impact items were verified by hand. Treat the rest as leads:
verify each one before renaming it.

## Decision

### 1. Canonical vocabulary

[GLOSSARY.md](../../GLOSSARY.md) is the source of truth. New code uses the
glossary terms. Target names:

| Concept | Current names | Target name |
|---|---|---|
| Capture session | `Meeting`, `MeetingEntity`, `MeetingMO` | `CaptureSession`, `CaptureSessionEntity`, `CaptureSessionMO` |
| Capture mode | five enums | one `CaptureMode` in Domain |
| Capture origin | `MeetingApp`, `DomainMeetingApp` | `CaptureOrigin` |
| Capture state | `MeetingState` | `CaptureState` |
| Summary strategy | `MeetingType` | `SummaryStrategy` |
| Capture artifact | `Transcription`, `TranscriptionEntity`, `TranscriptionMO` | `CaptureArtifact`, `CaptureArtifactEntity`, `CaptureArtifactMO` |
| ASR client | `TranscriptionRepository` | `SpeechRecognitionClient` |
| LLM provider | `AIProvider` | `LLMProvider` |
| Post-processing | `enhancements*`, `postProcessing*` | `postProcessing*` in code |
| Retention | `cleanupOldTranscriptions` | `cleanupOldRecordings` |

### 2. Persisted-value rule

Rename the symbol, preserve the stored value. This applies to Core Data
entity and attribute names, UserDefaults keys, Keychain items, `Codable`
raw values and coding keys, localization keys, window autosave and toolbar
identifiers, and log category raw values.

- Use `CodingKeys`, `@objc(LegacyName)`, Core Data
  `renamingIdentifier`, or a constant with the legacy string.
- Change a stored value only with an explicit migration, a rollback path,
  and a test that reads data written by the previous version.
- Never change frozen legacy identifiers (see the glossary).

### 3. New code

- Do not add new `Meeting*` names for behavior shared by every capture
  purpose.
- Do not add new mode enums; extend the existing axis until `CaptureMode`
  exists.
- Name a type after what it does today, not after the feature that
  introduced it.

### 4. Execution order

Each phase is a separate unit of work with its own plan and validation.

1. **Dead code and safe fixes (low risk).** Delete `FluidAIProvider`,
   `FluidAudioProvider`, and the `AIInfrastructureProvider` family after
   confirming no callers. Delete the `TranscriptionProvider` protocol if it
   has no conformers. Delete `MeetingAssistantAI/` and its glob in
   `scripts/scope-check.sh`. Fix the `TranscriptionClient` doc comment and
   `FeatureFlags` comment. Localize `TranscriptionStatus.statusMessage`.
   Rename the queue label. Remove always-empty retention fields.
2. **Internal renames with no persisted value.** `SmartShortcutHandler`,
   `RecordingUIRenderState`, `TranscriptionSettingsViewModel`,
   `*SettingsTab` and the `tabs/` folder, `StylesSettingsTab`,
   `RecordingSourceFilter`, `TranscriptionRepository`, the duplicate
   `ModelState`, and collapsing `supportsMeetingConversation` into one
   property.
3. **Domain model renames with preserved storage.** Unify the mode enums
   into `CaptureMode`. Merge `DomainMeetingApp` into `CaptureOrigin`.
   Rename `Meeting` to `CaptureSession`, `MeetingState`, `MeetingType`,
   `AIProvider`, and the routing models, keeping stored values. The
   `Transcription` aggregate is named `CaptureArtifact`. Fix the duplicated-
   word UserDefaults key only with a key migration.
4. **Module and project identity (highest churn).** Rename
   `MeetingAssistantCore*`, the Xcode target and scheme, the app entry
   point, and the test target. Update scripts, CI, and the resource bundle
   name in one coordinated change.

## Consequences

- Readers can map today's code names to intended meaning through the
  glossary before any rename lands.
- Renames ship in small phases, so each diff stays reviewable and
  revertible.
- Persisted data stays readable across versions; the cost is legacy strings
  that remain in coding keys and constants.
- Phase 4 touches almost every file and conflicts with any open branch; it
  needs a quiet window.

## Alternatives considered

- **One big rename.** Rejected: too large to review and risky for
  persisted data.
- **Document only, never rename.** Rejected: the debt keeps growing as new
  code copies the old names.
