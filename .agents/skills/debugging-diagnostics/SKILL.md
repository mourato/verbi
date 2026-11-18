---
name: debugging-diagnostics
description: This skill should be used when the user asks to debug bugs, investigate crashes, analyze flaky behavior, trace unknown root causes, add logging, improve telemetry, or standardize diagnostic signals in Verbi.
---

# Debugging and Diagnostics

## Role

Canonical owner for unknown-root-cause investigation and diagnostic signal design in Verbi.

## Scope Boundary

Use for crashes, flaky behavior, logging, telemetry, redaction, failure signatures, and metrics correlation. Delegate confirmed subsystem fixes to the specialist skills below.

## When to Use

Use when the root cause is unknown, or when the task is about logging, telemetry, diagnostic payloads, redaction, stable failure signatures, or metrics correlation in Verbi.

## Project specifics

Route once the surface is known: global `macos-ui` for SwiftUI rendering/lifecycle, `../audio-realtime/SKILL.md` for render-thread audio, `../swift-concurrency-expert/SKILL.md` for actor isolation or `Sendable`.

Verbi checklist before editing code: startup vs reopen; observer or monitor teardown symmetry; actor ownership of UI-facing state; persisted settings or migration shape; feature flags, permissions, and capture mode differences; SwiftUI row identity, derived state in `body`, and repeated formatting/filtering when UI jank is reported.

Logging and telemetry specifics: use stable, lower_snake_case event names and stable, sanitized payload keys; emit telemetry at decision points and degraded states, not every implementation detail; never log secrets, raw credentials, or sensitive transcript content; sanitize user-controlled strings before attaching them to diagnostic payloads; prefer identifiers, counts, and coarse state tokens over raw content.

Existing repository references: `Packages/VerbiCore/Sources/Common/Logging/ShortcutTelemetry.swift`, `Packages/VerbiCore/Sources/Infrastructure/Infrastructure/PerformanceMonitor.swift`, `Packages/VerbiCore/Sources/Infrastructure/Services/TextContextLogger.swift`.

Commands: `git log --stat -- <path>`, `git diff -- <path>`, `make scope-check`, `make build`, `./scripts/run-tests.sh --suite dev --test <TestName>`.

## Follows global forensics

Investigation structure, hypothesis testing, artifact/trace diagnosis, and causal confidence come from global `forensics`. This skill keeps the Verbi logging and telemetry surface.

References: [debugging-checklist](assets/debugging-checklist.md), [common-bugs](assets/common-bugs.md), [debugging-tools-guide](references/debugging-tools-guide.md), [performance-profiling](references/performance-profiling.md), [production-debugging](references/production-debugging.md).

Related: `../audio-realtime/SKILL.md`, `../swift-concurrency-expert/SKILL.md`, global `macos-ui`.
