---
name: audio-realtime
description: This skill should be used when the user asks to "fix audio glitches", "optimize low-latency audio", "debug underruns", or "update real-time audio callbacks".
---

# Real-Time Audio Processing

## Role

Use this skill as the canonical owner for low-latency audio and render-callback constraints in Verbi.

- Own hot-path safety rules, buffer/callback constraints, and audio-specific concurrency expectations.
- Keep real-time guidance separate from general performance tuning and UI lifecycle concerns.
- Delegate app-wide performance or non-audio concurrency issues to their specialist owners.

## Scope Boundary

- Use this skill for audio glitches, underruns, render callbacks, and low-latency capture/processing paths.
- Use `../debugging-diagnostics/SKILL.md` for app-wide optimization or unknown bottlenecks outside audio hot paths.
- Use `../swift-concurrency-expert/SKILL.md` for compiler-driven concurrency remediation when the issue is not audio-specific.

## When to Use

Use this skill when the user asks to fix audio glitches, optimize low-latency audio, debug underruns, or update real-time audio callbacks.

## Core Rules

### Render path safety

- No file I/O, networking, sleeps, or UI work on the render callback path.
- Avoid heap allocation during steady-state callbacks.
- Use preallocated buffers or ring-buffer style transfer for hot data paths.
- Keep copies bounded with explicit `min(...)`-style limits.

### Locking and ownership

- Do not use `NSLock` or `@MainActor` on render-thread code.
- Prefer the smallest viable synchronization surface outside the callback.
- Mark cross-thread callbacks `@Sendable`.
- Keep UI state isolated from hot-path state.

### Lifecycle symmetry

- Start/stop/pause paths must be idempotent.
- Observer, tap, and callback registration must have explicit teardown.
- Failure paths must leave recording state recoverable for the next attempt.

## Audio Hotspots

Prioritize these components when debugging:

- `SystemAudioRecorder`
- `AudioBufferQueue`
- `AudioRecorder`
- `AudioRecordingWorker`

## Verification

- Run focused audio tests first.
- Use `make build-agent` for narrow compile confidence.
- Escalate to `make build-test` when the change touches audio lifecycle, concurrency, or shared infrastructure.
- For microphone reliability, verify callback teardown, non-blocking buffer handoff, repeated start/stop/restart, and focused tests.

## References

- `../debugging-diagnostics/SKILL.md`
- `../swift-concurrency-expert/SKILL.md`
