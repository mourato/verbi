# ADR 008: Speech content never reaches logs or temporary files

**Status:** Accepted
**Date:** 2026-11-20

## Context

Verbi records meetings and dictation and sends audio to local and cloud transcription providers. Transcripts and audio are the most sensitive data the app handles.

## Decision

- In-memory transcription never writes a temporary file to disk.
- FluidAudio logging must be configured before any model loads, because its debug logs can include transcript text.
- Groq in-memory transcription never writes a temporary file to disk.
- OpenAI in-memory transcription never writes a temporary file to disk.
- The prewarm probe is a bare HEAD to the host root carrying no credentials and no content.
- Rate-limit detection inspects status codes and provider status text only, never speech content.
- Window encoding and silence analysis stay nonisolated off the main actor, and nothing there logs or returns speech content.
- Vocabulary logging records only whether hints were attached, never the raw terms.
- Remote window transcription encodes and uploads in memory with zero temporary audio files on disk.
- Execution provenance holds only identifiers and selections, never transcript or prompt text, so it can be persisted with each attempt.
- Latency breakdowns carry durations and identifiers only, never speech content.
- Latency logging carries only stage timings and model identifiers, never content.

## Consequences

Each rule above also lives in `docs/CODE_CONSTRAINTS.md` beside its owning file, because source code carries no comments. Change a rule, its code, and this ADR together.

## Rejected or deferred

Writing audio windows to temporary files for upload was rejected; uploads encode in memory. Logging transcript snippets for debugging was rejected; logs carry timings and identifiers only.

## References and license

Recovered from code comments removed by the comment cleanup; no external material.

## Affected surfaces

- `Packages/VerbiCore/Sources/AI/Services/ElevenLabsTranscriptionClient.swift`
- `Packages/VerbiCore/Sources/AI/Services/FluidAudio/Sendable.swift`
- `Packages/VerbiCore/Sources/AI/Services/GroqTranscriptionClient.swift`
- `Packages/VerbiCore/Sources/AI/Services/OpenAITranscriptionClient.swift`
- `Packages/VerbiCore/Sources/AI/Services/ProviderConnectionPrewarmer.swift`
- `Packages/VerbiCore/Sources/AI/Services/RemoteWindowAudioSupport.swift`
- `Packages/VerbiCore/Sources/AI/Services/TranscriptionClient.swift`
- `Packages/VerbiCore/Sources/AI/Services/TranscriptionClientRemoteIncremental.swift`
- `Packages/VerbiCore/Sources/Domain/Models/ExecutionProvenance.swift`
- `Packages/VerbiCore/Sources/UI/Services/RecordingManager/IncrementalRemoteDictationSupport.swift`
- `Packages/VerbiCore/Sources/UI/Services/RecordingManager/RecordingManagerTranscriptionPipeline.swift`
