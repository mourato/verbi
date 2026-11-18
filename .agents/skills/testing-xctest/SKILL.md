---
name: testing-xctest
description: This skill should be used when the user asks to "write XCTest tests", "refactor test doubles", "add async tests", or "improve test structure" in Verbi.
---

# XCTest Patterns

## Role

Canonical owner for XCTest structure and test doubles in Verbi.

## Scope Boundary

Use for test code under `Packages/VerbiCore/Tests/VerbiCoreTests`. Delegate lane and merge-gate selection to `../delivery-workflow/SKILL.md`.

## When to Use

Use when writing or refactoring test code under `Packages/VerbiCore/Tests/VerbiCoreTests`. Use `../delivery-workflow/SKILL.md` for lane and merge-gate selection.

## Project specifics

Layout: one primary subject area per file; one top-level `final class ...Tests: XCTestCase` unless a second helper type is justified; name files after the subject, for example `TranscriptionDeliveryServiceTests.swift`; put fixtures near the owning subject.

Async and actor rules: mark the test type or test `@MainActor` when it touches UI-bound state or main-actor services; use async `setUp` only when initialization requires suspension; await concrete observable effects instead of sleeping; keep task cancellation explicit.

Doubles: prefer protocol-backed fakes or spies over inheritance-based mocks; keep doubles minimal; split protocols or add focused adapters instead of implementing unrelated surface.

Verbi test seams: inject readiness predicates for models, Keychain state, and filesystem checks instead of reaching into installation state; keep seams actor-aware; use explicit enum types and unwrap optionals when inference makes failures noisy; give migration and backfill tests unique checkpoint keys.

Commands: `./scripts/run-tests.sh --file <TestFile>` or `./scripts/run-tests.sh --test <testName>`.

Examples: `TranscriptionDeliveryServiceTests.swift`, `AudioRecorderTests.swift`, `ShortcutDefinitionAndEngineTests.swift`.

## Follows global test-hygiene

Behavior contracts, independent oracles, deterministic execution, cleanup, and evidence come from global `test-hygiene`.

Related: `../delivery-workflow/SKILL.md`, global `simplify-as-you-go`.
