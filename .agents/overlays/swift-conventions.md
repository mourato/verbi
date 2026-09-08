---
kind: project-overlay
extends: swift-conventions
project: verbi
precedence: project
---

# Verbi Swift checks

- Swift 6.2 strict concurrency and default actor isolation are active; make isolation and `Sendable` decisions explicit.
- Keep files at or below the repository's 600-line policy and use colocated type directories with unique owner-prefixed sibling filenames.
- Preserve the module layout under `Packages/MeetingAssistantCore/Sources/` and the public `MeetingAssistantCore*` target/import names.
- Prefer Observation for new UI state while preserving existing `ObservableObject` contracts until an intentional migration is verified.
- Route concurrency-specific remediation to the retained local `swift-concurrency-expert` specialist and lint/build delivery to global `delivery-workflow` plus its Verbi overlay.
- Use `make lint-agent FILES="App/Changed.swift"` for a compact changed-file check; use `make lint` for the fail-closed merge gate. Strict lint applies `.swiftlint-baseline.json`; `make lint-report` is report-only for the named baseline warnings.
- The durable Swift 6.2 baseline and supported toolchain restriction are documented in `.agents/docs/swift-6-2-agent-baseline.md`.
