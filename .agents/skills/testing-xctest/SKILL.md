---
name: testing-xctest
description: This skill should be used when the user asks to "write XCTest tests", "refactor test doubles", "add async tests", or "improve test structure" in Verbi.
---

# XCTest Patterns

## Role

Use this skill for XCTest implementation details in Verbi.

- Own test structure, naming, doubles, fixtures, and async test patterns.
- Delegate verification gates, merge commands, lifecycle policy, and risk lanes to global `delivery-workflow`.

## Scope Boundary

Use this skill when the task is about writing or refactoring test code, especially under `Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests`.

- XCTestCase organization
- `@MainActor` tests
- async `setUp` and `tearDown`
- mocks, fakes, spies, and fixtures
- deterministic assertions and failure messages

Do not use this skill to choose lane policy or merge gates.

## When to Use

Use this skill when the user asks to write XCTest code, refactor test doubles, add async tests, or improve the structure of test files in this repository.

## Test Structure Standards

### File and Type Layout

- Keep one primary subject area per test file.
- Prefer one top-level `final class ...Tests: XCTestCase` per file unless a second helper test type is clearly justified.
- Name files after the subject under test when possible, for example `TranscriptionDeliveryServiceTests.swift` or `AudioRecorderTests.swift`.

### Naming

- Use descriptive test names that encode behavior and outcome.
- Prefer `test<Action>_<Condition>_<ExpectedResult>` or an equivalent readable pattern already used nearby.
- Avoid vague names such as `testExample` or `testSuccess`.

### Arrange/Act/Assert

- Keep setup obvious and local.
- Extract helpers only when repeated setup obscures intent.
- Use comments sparingly; a short `// Given`, `// When`, `// Then` is acceptable when the flow is long.

## Async and Main-Actor Patterns

- Mark the test type or individual tests with `@MainActor` when they touch UI-bound state or main-actor services.
- Use async `setUp` only when initialization actually requires suspension.
- Prefer awaiting concrete observable effects instead of sleeping for timing.
- Keep task cancellation explicit in tests that start long-lived work.

## Doubles and Fixtures

- Prefer protocol-backed fakes or spies over broad inheritance-based mocks.
- Keep test doubles minimal and scoped to the behavior under assertion.
- Avoid doubles that implement unrelated protocol surface just to satisfy compilation; split protocols or add focused adapters if this becomes common.
- Put reusable fixtures near the owning subject area, not in a generic dumping-ground file.

## Verbi Test Seams

- Inject readiness predicates for models, Keychain state, and filesystem-dependent checks instead of reaching into installation state.
- Keep test seams actor-aware; use `@MainActor` for UI-bound closures and tests.
- Use explicit enum types and unwrap optionals when inference makes XCTest failures noisy.
- Give migration and backfill tests unique checkpoint keys so one scenario cannot mask another.

## Existing Repository Examples

- `Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/TranscriptionDeliveryServiceTests.swift`
- `Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/AudioRecorderTests.swift`
- `Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/ShortcutDefinitionAndEngineTests.swift`

Use these files as examples for local naming, protocol-backed doubles, and behavior-focused assertions.

## Verification

- Run targeted tests first via `./scripts/run-tests.sh --file <TestFile>` or `--test <testName>`.
- Use global `delivery-workflow` for merge-gate selection and broader validation.

## Related Skills

- Global `delivery-workflow`
- Global `code-quality`
