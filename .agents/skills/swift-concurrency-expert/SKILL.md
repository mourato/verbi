---
name: swift-concurrency-expert
description: This skill should be used when the user asks to "fix Swift concurrency errors", "resolve actor isolation issues", "remediate Sendable diagnostics", or "upgrade to Swift 6.2 concurrency".
---

# Swift Concurrency Expert

## Role

Canonical owner for Swift concurrency diagnostics and remediation in Verbi.

## Scope Boundary

Use for concrete compiler concurrency issues. For conceptual guidance without compiler remediation, answer from Swift concurrency principles instead of expanding this workflow.

## When to Use

Use for concrete Swift concurrency compiler issues and remediation in Verbi.

## Project specifics

- The project baseline is Swift 6.2; verify actual language and strict-concurrency settings before applying 6.2-only guidance.
- Keep UI entry points `@MainActor`, mark cross-thread callback aliases `@Sendable`, and prefer a dedicated actor over scattered locks.
- Review factory and default-provider isolation before adding broad annotations; reshape APIs to remove cross-actor callbacks when possible.
- Separate compiler-instability signatures from semantic actor errors; do not repeat crash-inducing rewrites.
- Record the symbol, current isolation, target isolation, and reason for every actor-boundary fix.
- Map diagnostics and writeback ownership before widening isolation; preserve lifecycle ordering across actor hops.
- Pair strict checks with the narrowest targeted test that proves the changed path.

Commands: `make test-strict`, `AGENT=1 make test`, plus the focused test for the changed subsystem.

Reference material:

- `references/swift-6-2-concurrency.md`
- `references/approachable-concurrency.md`
- `references/swiftui-concurrency-tour-wwdc.md`

## Follows global swift-conventions

Concurrency triage, actor-context mapping, `Sendable` remediation, and the smallest-safe-fix method come from global `swift-conventions`. Keep Verbi's Swift 6.2 baseline and the invariants above.

Related: `../architecture/SKILL.md`, `../testing-xctest/SKILL.md`.
