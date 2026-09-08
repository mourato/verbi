---
name: debugging-diagnostics
description: This skill should be used when the user asks to debug bugs, investigate crashes, analyze flaky behavior, trace unknown root causes, add logging, improve telemetry, or standardize diagnostic signals in Verbi.
---

# Debugging and Diagnostics

## Role

Use this skill as the canonical owner for unknown-root-cause investigation and diagnostic signal design in Verbi.

- Own investigation structure when the root cause is unknown.
- Own logging structure, telemetry naming, payload redaction, and failure-signature guidance.
- Focus on evidence gathering, hypothesis testing, privacy-safe instrumentation, and narrowing scope before subsystem-specific fixes.

## Scope Boundary

Use this skill for:

- crash investigation
- flaky behavior
- regressions after recent changes
- performance symptoms before the bottleneck is confirmed
- `AppLogger` or `Logger` diagnostic design
- structured telemetry events
- diagnostic payload shape
- redaction and privacy-safe logging
- correlation between logs, telemetry, and metrics
- concise failure signatures in task, issue, or PR notes

Use specialist skills once the failure surface is known:

- global `macos-app-engineering` for confirmed SwiftUI rendering, update, layout, lifecycle, or app-structure fixes.
- `../audio-realtime/SKILL.md` for confirmed render-thread and low-latency audio defects.
- `../swift-concurrency-expert/SKILL.md` for concrete actor-isolation or `Sendable` diagnostics.

## When to Use

Use this skill when the root cause is unknown, or when the task is about logging, telemetry, diagnostic payloads, redaction, stable failure signatures, or metrics correlation in Verbi.

## Investigation Workflow

1. Reproduce the issue with exact steps, state, and environment.
2. Reduce the scope to one subsystem, transition, or invariant.
3. Compare working vs broken paths.
4. Add the smallest useful instrumentation.
5. Validate or kill one hypothesis at a time.
6. Route to the subsystem owner once the failure surface is known.

For broad or uncertain investigations, the root session may delegate one `diagnostician` and one bounded `explorer` in parallel. Pass this skill as the primary skill, keep both children read-only, and consolidate evidence before routing to a subsystem specialist.

## Core Principles

### Reproduction First

- Write the failing path down before changing code.
- Separate first-launch, warm-launch, background/foreground, and reopen behavior when relevant.
- Prefer the smallest deterministic repro over broad "seems broken" notes.

### Compare States, Not Stories

- Check what changed in code, persisted data, permissions, feature flags, and app lifecycle.
- Compare working vs broken state with concrete evidence: logs, timestamps, actor hops, menu state, persisted records, metrics, or view transitions.
- Do not trust memory when `git`, logs, metrics, or current code can answer it.

### Instrument Surgically

- Add logging around boundaries, not everywhere.
- Prefer existing diagnostics surfaces and stable log keys.
- Remove speculative instrumentation once the root cause is understood.
- Avoid noisy per-frame or per-buffer logs outside dedicated debug paths.

### Preserve Changed-Path Proof

- Name the focused tests, builds, or manual flows that prove the failing path.
- If full gates fail, distinguish changed-path failures from existing baseline noise.

## Diagnostic Standards

### Logging

- Log state transitions, boundary failures, and recovery attempts.
- Prefer structured context over long free-form messages when the same failure may recur.
- Keep severity consistent with the actionability of the event.

### Telemetry Events

- Use stable, lower_snake_case event names.
- Keep payload keys stable and sanitized.
- Emit telemetry for decision points and degraded states, not for every implementation detail.

### Redaction

- Never log secrets, raw credentials, or sensitive transcript content.
- Sanitize user-controlled strings before attaching them to diagnostic payloads.
- Prefer identifiers, counts, and coarse state tokens over raw content.

### Failure Signatures

- Capture the first failing stage and the first actionable mismatch.
- Keep signatures short enough to repeat in PR notes or issue comments.
- If a metric or diagnostic payload exists, reference it by stable name rather than copying large blobs.

## Verbi-Specific Checklist

Before editing code, check:

- startup vs reopen behavior
- observer or monitor teardown symmetry
- actor ownership of UI-facing state
- persisted settings or migration shape
- feature flags, permissions, and capture mode differences
- SwiftUI row identity, derived state in `body`, and repeated formatting/filtering when UI jank is reported

## Existing Repository References

- `Packages/MeetingAssistantCore/Sources/Common/Logging/ShortcutTelemetry.swift`
- `Packages/MeetingAssistantCore/Sources/Infrastructure/Infrastructure/PerformanceMonitor.swift`
- `Packages/MeetingAssistantCore/Sources/Infrastructure/Services/TextContextLogger.swift`

Use these as the current baseline for structured events, metrics intake, and privacy-aware failure logging.

## Useful Local Commands

```bash
git log --stat -- <path>
git diff -- <path>
make scope-check
make build-agent
./scripts/run-tests.sh --suite dev --test <TestName>
```

## Evidence Notes

- Record one short note per disproved hypothesis.
- When the fix is found, document the invariant that was violated.
- If the issue turns out to be subsystem-specific, stop expanding this skill and move to the subsystem owner.

## Related Skills

- `../audio-realtime/SKILL.md`
- `../swift-concurrency-expert/SKILL.md`
- Global `macos-app-engineering`

## References

- **[assets/debugging-checklist.md](assets/debugging-checklist.md)**: Quick investigation checklist
- **[assets/common-bugs.md](assets/common-bugs.md)**: Common failure patterns in this repo shape
- **[references/debugging-tools-guide.md](references/debugging-tools-guide.md)**: Tooling and capture tips
- **[references/performance-profiling.md](references/performance-profiling.md)**: Performance investigation guidance
- **[references/production-debugging.md](references/production-debugging.md)**: Production-safe debugging habits
