# Code constraints

Source code carries no comments; the `no_comments` lint rule enforces this.
The exceptions are tool markers (`swift-tools-version:`, `swiftlint:`,
`swiftformat:`, `preview-check:`, `test-hygiene:`), `justified:` notes beside a
lint suppression, and the generated header in `.comment-baseline.json`.
This document is the current contract for the non-obvious constraints those
comments used to hold. Each entry names the file that owns it.

Change a constraint and its code together. Remove an entry when the code no
longer needs it. Security, privacy, and user-data safety decisions may also
have an ADR under `docs/adr/`.

These ADRs explain the main security, privacy, and user-data rules:

- [ADR 008: Speech content never reaches logs or temporary files](adr/008-speech-content-stays-out-of-logs-and-disk.md)
- [ADR 009: Sanitize user text before it enters AI prompts or AppleScript](adr/009-sanitize-user-text-before-prompts-and-scripts.md)
- [ADR 010: Retention never deletes audio that recovery has not processed](adr/010-recording-retention-protects-unrecovered-audio.md)

## App

### `VerbiApp.swift`

- Inside VerbiCommands, registerSettingsSceneOpener() must stay a named let binding consumed by the guard, because a bare Bool expression is not a valid statement in a CommandsBuilder body.

## App/AppDelegate

### `AppDelegateCapabilities.swift`

- Local models are prepared by the meeting capture path; enabling the meeting capability does not load them.

### `AppDelegateLifecycle.swift`

- Transcript retention cleanup must not unload models or purge their execution caches.
- Launch ends with a visibility recovery check so the app never keeps running with no status item and no window.
- A menu bar-only app must decline window reopen on activation, which AppKit otherwise performs in SPM builds.
- Declining untitled-file open on launch prevents an AppKit crash in SPM builds.
- A @Published sink emits in willSet, so anything that re-reads the value must hop to the main queue to observe committed values.
- When onboarding has not completed, launch returns before the menu bar, shortcut controllers and other services start.
- Reactivating the menu-bar app must not create or reopen windows.

### `MenuBar.swift`

- Crash recovery runs before retention cleanup, so cleanup never deletes a file recovery has not seen.

### `RecordingUI.swift`

- The idle menubar icon is drawn by scaling the source asset, whose visible content the code assumes to cover 13/16 of its canvas, so its visible occupancy fills 95% of an 18x18 canvas.
- While transcription is active the indicator keeps showing processing even when the isProcessing flag missed it.
- The RecordingManager flag alone decides the notes panel; OR-ing the pane's sticky isUserOpened re-summons it after a toggle-off.

## App/AssistantShortcutController

### `EventMonitors.swift`

- The assistant shortcut runtime registers native Carbon hotkeys and stops the pluggable input backend's monitoring.

### `ShortcutLayer.swift`

- Shortcut layer mode is deliberately disabled in the assistant shortcut runtime.

## Packages/VerbiCore/Sources/AI

### `ElevenLabsTranscriptionClient.swift`

- Transcription runs off the main actor and invokes onProgress from a background executor, so callers must hop before touching UI.
- In-memory transcription never writes a temporary file to disk.
- The multipart body sends repeated keyterms fields, capped at 1000 terms of 50 characters.

### `FluidAIModelManager.swift`

- Concurrent callers await the in-flight model load instead of returning before the runtime exists.
- Model deserialization and Core ML compilation stay off the main actor so capture is not blocked.

### `FluidAIModelManagerInference.swift`

- Decoder state is created per file and per cumulative preview so runs do not inherit each other's state.
- Each preview transcription creates a fresh decoder state and reprocesses its samples from the start.

### `Sendable.swift`

- FluidAudio logging must be configured before any model loads, because its debug logs can include transcript text.

### `GroqTranscriptionClient.swift`

- Groq transcription runs off the main actor and invokes onProgress from a background executor, so callers must hop before touching UI.
- Groq in-memory transcription never writes a temporary file to disk.

### `LocalModelCompilePrewarmer.swift`

- The launch prewarm runs only when the macOS build, ASR model, or diarization fingerprint changed since the last success.
- The ANE compiles serially, so the prewarm waits 60 seconds without capture before compiling.
- The launch prewarm is fire-and-forget and deferred so it never touches the launch critical path.
- The prewarm releases only what it loaded itself and never unloads during a capture.
- The prewarm targets local meeting models, falls back to local dictation, prepares only installed assets, and never lets missing diarization block ASR.
- The prewarm wait returns only after no capture has been active for a full quiet window, and any capture restarts that window.
- The prewarm fingerprint schema version must be bumped by hand whenever a change invalidates the compiled model cache, otherwise no prewarm pass runs.

### `LocalModelResidencyCoordinator.swift`

- Dictation idle unload skips the unload when the global residency timeout is 'never' and when the grace period exceeds the configured global inactivity interval.

### `LocalTranscriptionClient.swift`

- A failed model load surfaces its real error instead of a generic not-loaded error at transcribe time.

### `MeetingQAService.swift`

- Dictation grounded Q&A stays unavailable even when mode gating for that mode is enabled.

### `OpenAITranscriptionClient.swift`

- The client reads the shared openai Keychain slot when no key provider is supplied.
- OpenAI transcription runs off the main actor and invokes onProgress from a background executor, so callers must hop before touching UI.
- OpenAI in-memory transcription never writes a temporary file to disk.
- The gpt-4o transcribe models accept only json or text response formats.

### `CanonicalSummaryPipeline.swift`

- Canonical-summary JSON and empty provider output are never persisted as user-visible prose.

### `StructuredAPI.swift`

- `processedText` and `canonicalSummary` follow the same fallback contract, so structured and legacy output never diverge.

### `ProviderConnectionPrewarmer.swift`

- The prewarm probe is a bare HEAD to the host root carrying no credentials and no content.

### `RemoteWindowAudioSupport.swift`

- Rate limiting is signalled by a typed 429 error so batching fails fast even when the provider body omits the status.
- Window WAV encoding and silence analysis stay nonisolated statics that perform no logging, and silence analysis returns only peak and RMS values.
- Rate-limit detection inspects status codes and provider status text only, never speech content.

### `TranscriptionClient.swift`

- Remote window transcription is enabled only for dictation mode with a remote provider; meetings may still use incremental windows with capable local models, and assistant capture stays on the single-request path.
- Local ASR ignores provider vocabulary hints.
- Vocabulary logging records only whether hints were attached, never the raw terms.
- The provider capability mapping is the single owner of which hints field each backend encodes, so the request cannot diverge from the support the UI reports.

### `TranscriptionClientRemoteIncremental.swift`

- Remote window transcription encodes and uploads in memory with zero temporary audio files on disk.

## Packages/VerbiCore/Sources/Audio

### `AudioBufferQueue.swift`

- The audio ring buffer bridges the capture push and the render pull, so its lock must stay real-time safe.
- Enqueue never blocks the audio path; when full it drops the oldest buffer to stay current.

### `AudioDeviceManager.swift`

- The ZoomAudioDevice virtual input, which carries Zoom's own output rather than a microphone, is ignored during input device discovery.
- The raw default-input getter skips usability validation and exists to read the unvalidated system default for override capture, ducking checks, recovery, and diagnostics.
- A custom microphone is applied by briefly changing the system default, not the AUHAL current device, because that forces an aggregate device that fails with Bluetooth SCO.
- AVAudioEngine can run input through a private `CADefaultDeviceAggregate-<pid>-<n>` device. It is hidden from input discovery, and the recorder resolves it to its input sub-device before comparing UIDs; an unresolved aggregate never triggers recovery, because the restart fails with -10875 and loops.

### `AudioSpectrumKernel.swift`

- Spectrum plans (transform plus window) are cached per sample count behind one unfair lock, because the callers share the kernel across threads; the transform runs only while holding that lock. Spectrum analysis never runs on the real-time render tap: the engine path computes it in the worker's processing task.
- The spectrum kernel may use only the DFT sizes vDSP accepts, of the form f * 2^n with f equal to 1 or 3.

### `AudioMerger.swift`

- Export is skipped when the asset has no audio tracks, which would otherwise throw NSInvalidArgumentException.
- The non-Sendable AVFoundation objects cross to the export queue only because that serial queue is their sole owner.
- An existing file at the merge output URL is deleted only when it is not also one of the input recordings.
- All input tracks are inserted at time zero so the microphone and system tracks are mixed together rather than concatenated.

### `BaseAudioRecorder.swift`

- Recording validation gives the first capture buffer up to 4 seconds to arrive, because the first buffer after start can take seconds.
- A capture that restarts after failed validation keeps the session active for observers.
- Every public stop bumps the capture generation, and a start that sees it change stops itself.
- Recording state reports the capture session, so an internal restart is not a stop.
- The microphone permission check accepts a test override so validation-restart tests never depend on hardware permission state.
- Stop cancels a pending validation restart so the microphone never reopens after a stop.
- A recording start must throw CancellationError when a public stop happened after that start captured its generation.
- Finalizing a capture tears down the active source without cancelling a pending restart; only a public stop cancels the restart.

### `DictationRecorder.swift`

- Mic-only recording always captures through AVCaptureSession instead of AVAudioEngine, because the engine pairs the input with the output device in an aggregate whose clock drift makes the built-in microphone abandon every I/O cycle.
- The dictation recorder has no engine, system-audio recorder, or system-default input override path.
- The microphone capture session starts and stops on its own lifecycle queue, and reports runtime errors or a disconnected device as a recording error, because engine device recovery does not cover it.

### `MicrophoneCapture.swift`

- The stored preference UID is passed to the capture session so a missing device is distinguishable from no preference, and the session result reports whether it fell back, so the pill notice reads the real device.
- Stop clears the published device and fallback flag, and the snapshot keeps the device name captured before stop so history persists it.

### `MicrophoneCaptureSession.swift`

- Starting with an unresolvable device UID falls back to the system default instead of failing, and the start result names the device that actually opened and whether it fell back so callers can report it.
- The microphone capture duplicates its mono input into 2048-frame stereo chunks, because the recording file is stereo and the spectrum needs a full analysis window.

### `MeetingRecorder.swift`

- The system audio queue stays nonisolated so capture threads enqueue without hopping to the main actor.
- The capture queue is passed by value so the tap closure does not capture the main-actor recorder.
- AVAudioEngine's internal aggregate device can produce zero-filled buffers and reconfig loops with USB microphones.
- ScreenCaptureKit starts only after the audio engine is stable, because stream activation can invalidate the output format mid-initialization.

### `Diagnostics.swift`

- The tap callback must not capture the main-actor object, because AVAudioEngine runs it on a real-time audio thread.

### `EngineSetup.swift`

- Microphone capture prefers the input device's native sample rate; using the output rate can trap USB devices in a reconfig loop that records silence.
- The custom microphone override waits for the CoreAudio default-input property to report the device it just selected, never a re-read of the current default, instead of sleeping a fixed interval.
- The listener is stored only if the wait has not finished; a wait that finished during registration removes the listener at once so none outlives it.
- The default-input propagation wait is bounded by defaultInputPropagationTimeout and continues on timeout so recording start never hangs; only cancellation aborts it.
- The original system default input is restored through a defer, including when setup fails.
- Max frames per slice is raised to 2048 so hardware buffers larger than 512 frames do not fail with kAudioUnitErr_TooManyFramesToProcess.
- Only a fresh start may restart capture, because a recovered graph keeps writing to a file that already holds the session's audio.
- The mixer connects to the main mixer without a forced format so the engine follows the hardware output rate and avoids Invalid Element errors.
- The tap uses the mixer's actual output format so it never performs its own sample-rate conversion.
- If a stop released the engine during an earlier await, its start must not open the microphone.

### `InputDeviceSelection.swift`

- The preferred microphone is applied by temporarily overriding the system default before engine initialization, because the AUHAL current-device property forces an aggregate device that is fragile with Bluetooth SCO.
- The system default input is restored once the engine has latched onto the device, so other apps are unaffected.
- The system default input device is captured before the custom mic override is applied, so the previous default can be restored afterwards.

### `SourceNode.swift`

- When the buffer queue runs dry the audio render callback stops filling and returns noErr, so an underrun is deliberately not reported as an error.

### `Validation.swift`

- Validation callbacks from a previous attempt are invalidated before its teardown can yield.
- When a restart would recreate a file that already holds the session's audio, the recorder reports the failure and keeps the audio.

### `AudioRecordingWorker.swift`

- Stopping the recording worker waits for the processing loop to drain the queued buffers before the queue is cleared, so the tail of the recording is not dropped.
- Audio file writes happen only inside the serialized processing loop, which is why no lock guards the file handle.

### `PartialBufferState.swift`

- The partial-buffer tracker is shared with the audio render thread, so all its mutable state sits behind one unfair lock.
- The audio callback path performs no I/O, because blocking I/O inside the render callback can crash.
- The frame copy helper keeps no instance state and avoids heap allocation inside the render callback.

### `SoundFeedbackService.swift`

- Sound playback state lives entirely on its serial queue, which is what makes the engine safe to share.

### `SystemAudioRecorder.swift`

- The stream output holder keeps a strong reference so the capture output is not deallocated mid-recording.
- System audio capture excludes the app's own audio to avoid a feedback loop.
- Buffers are forwarded on the capture queue to keep high-frequency audio off the main thread.
- The system-audio buffer callback is invoked on a background queue, never on the main actor.

## Packages/VerbiCore/Sources/Common

### `AppIdentity.swift`

- Toolbar and autosave identifiers stay stable so existing window state is preserved.
- Legacy directory migration runs only when the current directory is absent, and when several legacy directories exist the first listed (newest) legacy name is migrated.

### `FeatureFlags.swift`

- Transcription readiness is gated from a cache rather than a synchronous health check on the critical path.

### `MeetingNotesMarkdownSanitizer.swift`

- Prompt block content escapes reserved tags so user text cannot break the wrapper boundaries.

### `AppDeepLink.swift`

- The URL scheme follows the build identity: verbi in Release, verbi-dev in Debug.

### `BundleExtension.swift`

- Localized UI strings resolve through the safe module bundle, because Bundle.module is brittle across SPM and Xcode test builds.
- Xcode package builds must resolve the generated module resource bundle; a hard-coded bundle name breaks localization when targets split into products.

### `TranscriptionOutputSanitizer.swift`

- Post-processing output is sanitized so that captured context metadata can never reach user-visible text.

## Packages/VerbiCore/Sources/Data

### `CaptureArtifactMO.swift`

- The Core Data managed-object class names and their deprecated typealiases (also in `CaptureSessionMO.swift` and `CaptureArtifactSegmentMO.swift`) are frozen: persisted stores reference them, so never rename or remove them without a model migration.

### `LegacyMigration.swift`

- Legacy JSON migration is idempotent: upsert by id, archive migrated files, and mark the checkpoint done only when no .json files remain.

### `PathValidation.swift`

- validatePath accepts only single-component filenames, rejecting any path containing '/', '\', or '..', so it never handles full absolute or nested relative paths.
- Recording-directory validation allows paths outside the app container because the user chose them explicitly.
- Path traversal is checked on the original path before resolution, because resolution collapses .. and hides it.
- A recording directory must resolve at or under the user's home directory or /Volumes: the resolved path must equal the allowed root or start with the root followed by a slash, so a sibling folder that shares the prefix is rejected.
- validatePath accepts a resolved path only when it equals the app container root or starts with the root followed by a slash, for the current and legacy container directories.

### `RetentionCleanup.swift`

- The orphan sweep never deletes files recovery has not processed: pending retries and unclaimed files inside the recovery window.
- Retention and orphan deletion never remove an unreferenced recording that interrupted-recording recovery still has pending.

### `StorageService.swift`

- Retention cleanup deletes only old audio files on disk and always keeps the transcription records.

## Packages/VerbiCore/Sources/Domain

### `CaptureSessionEntity.swift`

- Domain entities stay free of UI and framework dependencies.

### `DomainProtocols.swift`

- Adapters read vocabulary from the explicit provider projection, never from AppSettingsStore.

### `CaptureArtifact.swift`

- A nil post-processing failure reason means the step succeeded or was never attempted, so nil must not be read as success.

### `DictionaryArchive.swift`

- Importing a dictionary archive never overwrites an existing conflicting destination and keeps each valid variant even when another variant of the same rule already exists.

### `DictionaryWord.swift`

- The dictionary word list is a read projection over saved terms and replacement rules; writes go back to those same two sources with no migration.
- An empty word means a text-removal line.

### `ExecutionProvenance.swift`

- Older records may lack the vocabulary source; every new retry records one.
- currentDictionaryFallback means the artifact predates snapshots and the attempt used the dictionary as it stood at start.
- notRecorded must be read as unknown, never as an authoritative empty dictionary.
- The skip-post-processing override is missing in older records and belongs only to the stored meeting session.
- Execution provenance holds only identifiers and selections, never transcript or prompt text, so it can be persisted with each attempt.

### `InterruptedRecordingRecovery.swift`

- Recovery and retention share one candidate set so cleanup never deletes a crashed recording before recovery has seen it.
- Pending filenames are the ones recovery must retry next launch: persist failures, busy skips, and files active during a scan.
- Recovery never resurrects audio the user deleted; cleanup may still delete it when old.
- An unreferenced, non-pending recording older than 24 hours is eligible for orphan deletion once it is dismissed or past the 7-day recovery window.
- Auto-recovery stops retrying a file after three failures and leaves it for a manual retry.
- Orphan detection skips active and in-flight recordings, keeps empty or unreadable files on disk, and returns oldest-first for deterministic serial recovery.
- The byte-count helper never throws: unusable files are skipped, not deleted.
- An all-source meeting writes separate _mic and _sys files and merges them only at stop, so a crash can orphan both parts with no merged file.
- Only a lone microphone file marked as a dictation is a dictation; anything else defaults to a meeting.
- Group keys are lowercase, extension-free, drop the _mic/_sys suffix, and drop -recovered only when the stem looks app-generated.
- A group whose key matches referenced audio inside the recordings directory already has a library entry and must not gain a second one.
- A merged output name that is already taken makes the caller derive a -recovered variant instead of replacing the file.
- Recovered titles are recognized in both supported locales so a locale change between launches does not lose the marker.
- Empty path strings are filtered before basename extraction, because an empty path resolves against the working directory.
- A nil recovery date means the file must be skipped because it is referenced, active, dismissed, empty, unreadable, or older than the recovery window without a pending retry.

### `PostProcessingPrompt.swift`

- Predefined prompts keep stable UUIDs so their persistence identity survives releases.

### `TranscriptionDisplayText.swift`

- A canonical-summary JSON blob is never rendered as prose in any display surface.

### `VocabularyNormalization.swift`

- Vocabulary normalization trims outer whitespace and composes canonically equivalent Unicode while keeping letters and case.
- Destinations are case-sensitive, so US and us are separate entries.
- Origins match case-insensitively, as transcript substitution does.

### `VocabularyRecognitionSupport.swift`

- The per-provider vocabulary parameter mapping lives beside the provider definition and owns no wire limits.
- The support summary derives its counts from the same projections the request applies, so it cannot claim more than the request sends.
- The summary derives from the final wire prompt, because the adapter re-splits terms on commas and counts each fragment against the character budget.

### `VocabularyReplaceableSegment.swift`

- Substitution rules apply per segment, so a cross-segment phrase never invents timings or redistributes speakers.

### `VocabularyReplacementRule.swift`

- Replacement resolves as longest match first, then earliest start, then rule order, then variant order.
- Replacement matches are checked against hand-written word boundaries so punctuation identifiers such as C++ and .NET match while word fragments are left alone.

### `VocabularySnapshot.swift`

- Provider hints carry term strings only; term definitions are never sent to a provider.
- The Groq prompt budget is 800 characters, a conservative estimate of about 224 tokens.
- ElevenLabs batch keyterms are capped at 1000 terms.
- Wire limits are re-applied at the request boundary as defense in depth.
- Only hints for the requested capability parameter are sent; hints destined for other parameters are dropped.
- A session uses an immutable vocabulary snapshot captured at start so mid-recording edits do not change it, and capability routing has a single owner.
- Over-long ElevenLabs keyterms are skipped rather than truncated, unsupported characters are skipped, and the list caps at 1000.
- Vocabulary terms are stripped of control characters and of VOCABULARY delimiter tags before they enter the post-processing prompt, so a saved term cannot break the prompt block.

### `VocabularySubstitutionGroup.swift`

- The dictionary's in-memory shape is substitution groups while persistence stays on the replacement rule, so stored keys and Codable shapes are unchanged.
- An origin that points to several destinations is kept in every entry, because dropping it would silently lose a legacy entry.

### `VocabularyTeachCoordinator.swift`

- A correction is persisted through the same atomic path as archive import, so a storage failure leaves the in-memory dictionary untouched.
- A dictionary changed after preparation is rejected instead of overwriting the newer state.

### `VocabularyTerm.swift`

- Hints are every saved term plus one derived term per non-removal destination, saved terms first so they win case-insensitive dedup.

## Packages/VerbiCore/Sources/Infrastructure

### `CrashReporter.swift`

- Crash handling relies on the system reporter for signals and reserves the exception handler for Objective-C exceptions, because Swift signal handlers conflict with LLDB.

### `AppSettingsAssistantIntegrations.swift`

- Legacy fields are decoded and discarded so older payloads stay readable.

### `AppSettingsAudioAndAIConfiguration.swift`

- Legacy ElevenLabs model IDs stay known for migration identity, retry eligibility, and display names while presets list only scribe_v2.
- The provider owns the single vocabulary capability mapping, mirroring the transcription routing and carrying no wire limits.

### `AppSettings.swift`

- A sentinel prompt UUID represents an explicit no-post-processing choice without changing the persisted schema.
- Clearing a shortcut persists an explicit null so relaunch keeps it cleared instead of restoring the default.
- The previous release's key is written alongside the canonical one as a rollback mirror for older builds.
- When the `redactSensitiveData` setting is on (the default), context metadata is redacted for emails, URLs, tokens and long numeric sequences before it is sent to the AI provider.
- The ducking level is a percentage of the current output volume, where 0 is full mute and 100 leaves the output volume unchanged.

### `ComputedProperties.swift`

- Prompts created by older versions live under userPrompts, and clean-transcription prompts stay out of meeting prompts.

### `GeneralSettings.swift`

- An empty or invalid recordings directory falls back to Application Support.

### `Initialization.swift`

- The misspelled confirmation-delay key is the newest user value when both keys exist, and both keys stay in sync for downgrade compatibility.
- If either charge or battery device selection was already configured, migration keeps the user's explicit choices.

### `Keys.swift`

- The old mute-output key survives only for one-time migration into audio ducking.

### `VocabularyRulesNormalization.swift`

- Rules are stored consolidated per normalized destination, and origins that conflict across destinations are preserved so legacy data never disappears without a visible resolution.

### `DictationWebContext.swift`

- Older persisted web targets were markdown-only, so a missing forceMarkdownOutput decodes as true.

### `ModifierShortcutGesture.swift`

- Side-agnostic modifier cases are the canonical modifier form of in-house shortcut definitions, which are normalized to them on load and comparison, while advanced patterns still require a side-specific modifier.

### `SoundFeedbackCue.swift`

- The resolved cue key doubles as a durable marker so the migration never re-runs or undoes an explicit re-enable.

### `AXTextContextProvider.swift`

- Accessibility IPC is bounded by a messaging timeout so a hung app cannot freeze main-actor callers forever.

### `AccessibilityPermissionService.swift`

- Permission checks skip system prompts while tests run.

### `CaptureContextResolver.swift`

- Two contexts describe the same meeting when app and room match; query strings, fragments, and display names can change mid-call.

### `KeychainManager.swift`

- Old per-key cleanup is best-effort: a failure is harmless because the fallback path finds and re-migrates the values.
- Deleting a Keychain item treats not-found as success.

### `KeychainManagerAPI.swift`

- The legacy unified API key is migrated into the provider slot and deleted so the fallback cannot re-migrate it for other providers.

### `MediaPlaybackController.swift`

- AppleScript playback pausing runs off the calling actor so the start path never blocks on it.
- Production microphone start must use the scheduled pause, never the synchronous helper.

### `MeetingDetector.swift`

- A detected meeting survives a tab switch or a brief microphone gap; only a sustained absence ends it.
- A meeting inside its loss grace period is still shown but must not start a recording on its own.
- A meeting that lost its signal counts as ended, so the same app returning with a different room is a new meeting.
- The browser URL identifies a meeting only at its start; while the meeting app holds the microphone the meeting stays.
- A present meeting yields only to a different app that itself holds the microphone.
- When microphone owners are resolved, the meeting app must be one of them.
- Chromium captures audio in helper processes and Safari in shared WebKit processes, so both count as the app holding the microphone.
- The detector ignores the app's own lifecycle notifications so teardown does not trigger work.

### `MeetingReminderScheduler.swift`

- A dismissal stays attached to the old occurrence so a moved meeting can alert again.

### `NavigationService.swift`

- The settings opener may register after launch work, so an early request is held as a pending flag and presented once the opener registers, with no fallback presentation path.
- The accessory app is activated before the settings window is ordered front.
- On first open the autosave name may not be applied until the configurator runs.

### `NotificationService+InterruptedRecovery.swift`

- The recovery notification category registers alongside existing categories instead of replacing them.

### `NotificationService.swift`

- UserNotifications may only be used when the process runs as a real app bundle, because UNUserNotificationCenter is unavailable to CLI and test bundles.
- In the Debug fallback for runs outside an app bundle, notification text is sanitized for osascript (backslashes, quotes and metacharacters) and truncated to 200 characters plus an ellipsis afterward; runs inside an app bundle use `UNUserNotificationCenter` and a release build outside the bundle sends no notification.

### `SettingsWindowLayoutStateEvaluator.swift`

- The settings frame autosave key follows the build identity so a Debug build never reuses the installed app's frame.

### `NSEvent.swift`

- AppKit can vend synthetic flags-changed events from menu bar interaction that do not support key-event accessors.

### `WindowTextRecognizer.swift`

- Vision work runs off the calling actor, and an overlapping request is dropped (returns nil) rather than queued or replacing the running request.
- Vision's synchronous perform can ignore cancellation, so its slot stays occupied until the work actually finishes.

## Packages/VerbiCore/Sources/UI

### `DictationStyleRoute.swift`

- Dismissing a side-panel route restores focus to the route's focus target in the same dismiss transaction, not after the panel has fully left the screen.

### `RetryTranscriptionSelectionMatrix.swift`

- Legacy scribe_v1 stays eligible for retry whenever an ElevenLabs key is configured.

### `RetryVocabularyIntent.swift`

- The retry vocabulary choice is independent from the provider and model override and keeps the already selected provider, model, and language.
- Reproducing the original snapshot falls back to the current dictionary for artifacts that predate snapshots, and records that fallback.
- Callers resolve the current dictionary once before the attempt starts so later edits cannot change the result.

### `FloatingRecordingIndicatorController.swift`

- The indicator hides without blocking the stop path on WindowServer fences.
- The hosting view keeps a fixed size so transient overlay updates cannot animate the panel's dimensions.

### `MeetingDetectionToastController.swift`

- The toast presents without activating, so it never steals focus from the active app.

### `VocabularyQuickTeachController.swift`

- The correction panel activates only while open and returns focus to the app the user came from.

### `AssistantContextCaptureService.swift`

- Vision OCR ignores cancellation, so the timeout races unstructured tasks rather than a task group that would wait for the OCR child.
- The capture race resumes its continuation exactly once, so a timeout that finishes after the capture already returned is dropped.

### `AssistantTextSelectionService.swift`

- Pasteboard content is deep-copied at capture time because pasteboard items become invalid after any pasteboard change.

### `IncrementalRemoteDictationSupport.swift`

- Remote dictation transcribes closed speech windows in parallel, hides live preview, and pastes the joined result only at stop; meetings and local transcription keep their path.
- Dictations shorter than five seconds use a single full-file request to avoid per-request overhead.
- The transcribing pill state is delayed so fast finalizations skip a redundant redraw.
- A remote session that never crossed the window threshold is treated as a clean single-request fallback, not a failure.
- Latency breakdowns carry durations and identifiers only, never speech content.
- Recordings of four seconds or less with no speech are treated as silent and never reach remote transcription or AI post-processing.

### `IncrementalRemoteWindowBatcher.swift`

- Window results are joined by sequence number, never arrival order, and windows seen before the threshold are buffered so short dictations dispatch none.
- A failed window makes later ingestion return the recorded failure immediately so no more requests are issued.

### `IncrementalTranscriptionCoordinatorCore.swift`

- During full-file fallback the checkpoint stays non-visible.
- Remote dictation publishes no partial preview text; the full post-processed result appears only after stop.
- The ASR gate is left open when no warmup will reopen it, otherwise buffered audio is held forever.
- The no-window sentinel error is rethrown untouched and bypasses the legacy fallback, so the stop path issues exactly one full-file request.

### `MeetingEndPromptScheduler.swift`

- Cancelling a scheduled meeting-end prompt stops its action from running, and that cancellation is swallowed instead of being reported as an error.

### `RecordingControl.swift`

- A prompt resolved before recording must be re-resolved when an output language override is chosen during that recording.
- A recovery snapshot comes from settings defaults only; live session state must never leak into a recovered file.

### `RecordingLifecycleCoordinator.swift`

- Capture is released before finalization so a new recording never waits for the previous session's post-processing.

### `RecordingManager.swift`

- Audio paths of sessions still being transcribed are off-limits to recovery.
- The initialization snapshot must not overwrite a capture that started while the actor read was suspended.
- RecordingManager never calls UserNotifications directly; NotificationService guards requestAuthorization and sendNotification behind an app-bundle check.

### `RecordingManagerAutomaticMeetingRecording.swift`

- The meeting-end timer only launches an unstructured stop task, so cancelling it cannot cancel transcription or post-processing.
- When both the pill and the menu bar item are disabled, a minimal recording toast stays so a meeting never records with no visible state.
- A meeting inside its loss grace period may display, but only a live signal may start recording without a user action.

### `RecordingManagerIncrementalDictation.swift`

- Dictations that are short, silent and have no speech window are never sent to remote transcription or AI post-processing.

### `RecordingManagerRecovery.swift`

- Recovered files are persisted as failed entries, retried through the normal library flow with configured providers, and stay on disk for the next launch up to the attempt cap.
- Recovery retries produce no per-file user notifications and report success only when the entry ends up completed, not merely attempted.

### `RecordingManagerRecoveryFlow.swift`

- Files active during a scan stay remembered so a crash before the next launch still recovers them.
- Files that used all their attempts stay on disk untouched and are not probed or counted again.
- Unreadable files stay on disk without an entry, but the attempt is counted so they do not stay pending forever.
- A merged name taken by an owned file returns owned-elsewhere so the failed-retry pass handles it instead of duplicating the entry.
- Referenced paths are reloaded right before the recovery entry is persisted.
- A group already owned by another library entry leaves the pending set without counting an attempt, because the failed-retry pass owns it.
- Unreadable group files accrue attempts so they leave the pending set instead of being retried on every launch.

### `RecordingManagerStart.swift`

- ASR model load is deferred until after the audio engine starts so warmup cannot race the microphone start.
- Dictation prewarms remote provider connections during speech; meetings are long enough not to need it.

### `RecordingManagerStop.swift`

- A skipped silent recording discards its checkpoint with no transcription, AI, delivery, or error state.

### `RecordingManagerTranscriptionExecution.swift`

- A transcription configuration is synthesized only when vocabulary hints exist, so hints still reach the remote provider without routing local jobs remotely.

### `RecordingManagerTranscriptionPipeline.swift`

- Latency logging carries only stage timings and model identifiers, never content.

### `Retry.swift`

- Retry captures the dictionary once before asynchronous work, and that snapshot is the only vocabulary source for transcription, post-processing, and provenance.
- The persisted microphone label prefers the device name captured in the transcription session snapshot before stop over the preferred setting, so history shows the real microphone after a fallback.

### `GeneralSettingsViewModel.swift`

- Unavailable persisted audio device selections stay in the picker as unavailable so user intent remains visible.

### `ConversationTranscriptionActions.swift`

- A snapshot is authoritative only when the source recorded it, so a notRecorded artifact falls back to the current dictionary.
- A retry validates the entry and asks the user to pick a vocabulary intent before it overwrites the stored transcription.

### `VocabularySettingsViewModel.swift`

- Words persist through one verified terms-and-rules save that throws and leaves the in-memory dictionary untouched unless both arrays read back intact.
- Saving a word whose heard-as variants belong to another destination returns false and surfaces the conflict instead of persisting silently.
- Removing the last heard-as variant is refused; deleting the line goes through the confirmed deletion.
- Deleting a word persists its term and rules through the same verified terms-and-rules save, and already persisted snapshots keep the removed content.

### `AppTypography.swift`

- The timer overlay width depends on a monospaced-digit font so it stays deterministic.
- Compact overlay typography is fixed to preserve the panel width budget.

### `AppleMotion.swift`

- Disclosure timing stays independent from the reduce-motion fade so tuning one cannot retune the other.

### `DSAppearanceModePicker.swift`

- The appearance picker order is System, Light, Dark, independent of enum declaration order.

### `DSCard.swift`

- Card content uses one surface treatment; stacking a material under an opaque tint competes with the settings canvas.

### `MeetingDetectionToastView.swift`

- The toast keeps a dark HUD material in both appearances and, under Reduce Transparency, switches to adaptive grays so contrast survives.

### `OnboardingDownloadModelsView.swift`

- Already downloaded models count as complete on first onboarding open even if the manager has not reached .ready.

### `FloatingRecordingAudioVisualizer.swift`

- The processing sweep freezes mid-sweep under Reduce Motion.

### `FloatingRecordingIndicatorView.swift`

- Warning overlays stay out of layout sizing so a fixed panel size cannot trigger constraint loops.
- VoiceOver-revealed controls stay visible while the user navigates into them.
- The microphone fallback notice appears only while recording on the system default after the preferred microphone was missing, and it names the device in use.

### `EnhancementsProviderAvatar.swift`

- A non-template menu item image renders in full color on macOS, so the brand tile keeps its background and logo.
- The logo cache stores nil for assets that are missing, so a missing logo is not looked up again on every render.

### `MeetingConversationView.swift`

- On macOS 27 the AppKit markdown engine blanks the Settings window when mounted in the detail column, so that column uses a native editor while the floating panel keeps the engine.

### `MeetingConversationViewCopy.swift`

- A missing summary disables Copy summary and makes Copy-all skip the section instead of copying the display placeholder; transcript text is joined on demand.

### `SettingsSidePanel.swift`

- A clear tap-to-dismiss hit area is built from Color.clear plus contentShape, so taps outside the panel dismiss it.
- Escape is handled at the host level so focus on the underlying list still dismisses the panel.

### `SettingsWindowConfigurator.swift`

- The settings window is not movable by its background, matching stock Settings where dragging a Form does not move the window.

### `SettingsWindowPanelHost.swift`

- A drawer with no key views still clears first responder so typing cannot reach the list.
- Outside presses are consumed before native toolbar controls or window dragging see them, and other windows' events stay untouched.

### `SettingsPage.swift`

- Settings sidebar visibility is healed to visible on launch so a persisted hidden state cannot stick.

### `DictationStylesSettingsPage.swift`

- While the editor drawer owns focus, list rows leave the focus cycle so clearing focus does not land on the first row.

### `MetricsDashboardSupport.swift`

- Unknown loading zeros are never presented as a populated summary.

## Packages/VerbiCore/Tests/VerbiCoreTests

### `AudioSystemTests.swift`

- Stopping the recording worker drains the queue and awaits the processing task, so callbacks have fired once stop returns.
