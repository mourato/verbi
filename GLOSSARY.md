# Glossary

Canonical domain vocabulary for Verbi. When code names disagree with this
glossary, the glossary describes the intended meaning and the code name is
naming debt tracked in [ADR 007](docs/adr/007-domain-naming-debt.md).

## Product identity

**Verbi**
The product. Bundle identifier `com.mourato.verbi`.

**MeetingAssistant**
The original product name, before dictation and the assistant existed. It
survives in the Xcode project, target, and scheme (`MeetingAssistant`), the
Swift package and modules (`MeetingAssistantCore*`), the app entry point
(`MeetingAssistantApp`), and the test target. It is not a separate product.

**Frozen legacy identifiers**
Persisted identifiers that must keep their current values even when the code
symbol is renamed, because changing the value drops user state. Examples:
`settingsToolbarIdentifier = "MeetingAssistantSettingsToolbar"`,
`settingsWindowAutosaveName = "MeetingAssistantSettingsWindow"`, the legacy
domain lists in `AppIdentityValues`, Core Data entity names, UserDefaults
keys, and `Codable` raw values.

## Capture

**Capture session**
One recorded or imported audio unit, for any purpose. Code name today:
`Meeting` (UI and audio layers), `MeetingEntity` (domain), `MeetingMO`
(Core Data). A dictation is a capture session, so dictation calls
`createMeeting`.

**Capture purpose**
Why a capture session exists: `.meeting` or `.dictation`. Code name:
`CapturePurpose`. It is the persisted discriminator on a capture session.
`Meeting.isDictation` and `CapturePurpose.supportsMeetingConversation` are
derived from it.

**Capture mode**
Which capture flow is running: meeting, dictation, or assistant. Today this
axis has five enums: `CapturePurpose`, `IntelligenceKernelMode`,
`TranscriptionExecutionMode`, `RecordingExclusivityCoordinator.ActiveMode`,
and `RecordingExclusivityCoordinator.RecordingMode`. The assistant mode does
not create a capture session.

**Capture origin**
Where a capture session came from: a detected meeting app, a manual meeting,
an imported file, or an unknown source (used for dictation). Code name:
`MeetingApp`, duplicated as `DomainMeetingApp`. Not every origin is an app.

**Recording source**
Which audio device feeds the recorder: `.microphone`, `.system`, or `.all`.
Code name: `RecordingSource`. It is orthogonal to capture purpose.
`CapturePurposeFilter` filters by capture purpose.

**Capture state**
Lifecycle of the active capture: idle, recording, paused, processing,
completed. Code name: `MeetingState`, published as
`RecordingManager.meetingState`. Applies to every capture purpose.

**Summary strategy**
The prompt strategy used to summarize a capture (`autodetect`, `general`,
`standup`, ...). Code name: `MeetingType`. It is also stored on dictations.

## Transcription and artifacts

**Transcript**
The text that speech recognition produces from capture audio.

**Capture artifact**
The persisted record of a processed capture: transcript, post-processed
content, canonical summary, prompt provenance, context items, and
conversation state. Code name: `Transcription`, `TranscriptionEntity`,
`TranscriptionMO`. One capture session can own many artifacts.

**Speech recognition (ASR)**
Turning audio into a transcript. Backends: local (FluidAudio), Groq,
ElevenLabs, OpenAI. Selected by the `TranscriptionProvider` enum. Code names
that mean ASR client: `TranscriptionClient` (routes all backends),
`SpeechRecognitionClient` (domain protocol, not a storage repository).

**Local model**
An on-device ASR or diarization model managed by `FluidAIModelManager`.
Load state is the single domain `ModelState`.

**Transcription engine status**
Readiness of local ASR. Code names `ServiceState` and
`ServiceStatusResponse` come from a removed local HTTP server; there is no
remote service.

## AI post-processing

**Post-processing**
AI rewriting or summarization applied to a transcript. Also called
"enhancements" (settings keys and UI) and run through the
**intelligence kernel**. These three names describe one feature.

**Intelligence kernel**
The shared orchestration layer that runs post-processing and Q&A per mode
(`IntelligenceKernelMode`: meeting, dictation, assistant).

**LLM provider**
The AI provider used for post-processing and Q&A (OpenAI, Anthropic, Groq,
Google, custom). Code name: `AIProvider`. Distinct from the ASR provider,
even where both have `.groq` or `.openai`.

**Prompt**
A post-processing template (`PostProcessingPrompt`). Stored in per-mode
lists (`meetingPrompts`, `dictationPrompts`) plus the legacy `userPrompts`
bucket. The meeting-type classifier is an internal prompt, not a user
prompt.

**Grounded Q&A / conversation**
Questions answered from a capture artifact with transcript evidence. Code
names: `MeetingQAService`, `MeetingQA*`, `QATurn`,
`MeetingConversationState`, `MeetingConversationView`.
`MeetingQuestionDictationService` dictates a question into its composer.

## Dictation routing

**Dictation style (mode)**
A named dictation configuration: prompt, ASR selection, context policy, and
targets. Code name: `DictationStyle`. Shown in Settings as "Dictation Modes"
and edited in `DictationStylesSettingsPage`.

**Dictation targets and rules**
Per-app or per-site dictation behavior. Three overlapping models exist:
`DictationStyleTarget`, `DictationAppRule`, and `WebContextTarget` (stored
under the `markdownWebTargets` key, which is not markdown-specific).

## Storage

**Retention cleanup**
Deletion of old capture audio. Code names `cleanupOldTranscriptions` and
`autoDeleteTranscriptions` say "transcriptions", but only audio files are
deleted. Runs 30 seconds after launch.

## Settings UI

**Settings section / page**
A sidebar destination in Settings. Code calls them tabs
(`*SettingsPage`, `pages/settings/sections/`), but pages push their own
navigation. Aliased destinations exist: `.history`/`.transcriptions`,
`.vocabulary`/`.dictionary`, `.models`/`.intelligence`,
`.assistant`/`.integrations`.

**Transcription library**
The page that lists capture artifacts and hosts the conversation page.
View model: `TranscriptionLibraryViewModel`, which holds no settings.
