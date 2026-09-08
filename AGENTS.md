# AGENTS.md - Verbi Development Guide

## Identity and Purpose

Verbi is the display brand for this local-first macOS meeting capture, transcription, and AI post-processing app. Product and technical identifiers use Verbi (`com.mourato.verbi`); MeetingAssistant* remains the Xcode/SwiftPM scaffold. Use this repository's CLI-first workflow and Clean Architecture boundaries to make focused, reproducible changes.

## Project Context

- macOS 15+ is the minimum target; macOS 26 APIs need `#available(macOS 26, *)` guards with macOS 15 fallbacks; macOS 27 is preview-only.
- Swift 6.2+ with strict concurrency; default actor isolation is nonisolated — keep actor boundaries and `Sendable` reasoning explicit.
- SwiftUI-first UI with AppKit for status items, panels, lifecycle, and permissions SwiftUI cannot express reliably.
- New SwiftUI state prefers Observation; preserve `ObservableObject` until an intentional migration is verified.
- `Packages/MeetingAssistantCore/Sources/` uses short dirs: `Common`, `Domain`, `Infrastructure`, `Data`, `Audio`, `AI`, `UI`, `Core`, `Mocking`, `MockingMacros`.
- Public SwiftPM targets remain `MeetingAssistantCore*`; physical paths and public imports differ.
- Read [`docs/ui.md`](docs/ui.md) before changing user-facing UI. Update it
  when a reusable visual rule or invariant changes; use an ADR for durable
  rationale when the project has an ADR directory.
- Colocate types (`Services/RecordingManager/RecordingManager.swift`); no `Type+Concern.swift` filenames.

Module ownership: `Common`, `Domain`, `Infrastructure`, `Data`, `Audio`, `AI`, `UI`, `Core` — utilities, entities, adapters, persistence, capture, transcription, presentation, exports respectively.

## Non-Negotiable Rules

- User-facing strings use `"key".localized`; remove orphaned keys when text is deleted.
- Never hardcode secrets; use Keychain and avoid logging tokens, transcripts, or PII.
- `modelResidencyTimeout` applies to every local model; new models need registry entries and unload hooks.
- Prefer files ≤600 lines; split by owning type and concern.
- Prefer structured concurrency and `Task.sleep(for:)`; justify `Task.detached` and `DispatchQueue` use.

## Agent workflow

Use global routing, worktree, `agent-ops`, and `delivery-workflow` policies.
Load the matching project overlay after its global skill; this file supplies
Verbi facts and hard constraints only.

Verbi-specific high-risk surfaces are audio, concurrency, persistence,
security, cross-module architecture, and release infrastructure.

## Delivery lifecycle

The global `core/policies/worktrees.md` is authoritative for isolation and
delivery order: `create → work → commit → review → remediation → merge →
validate → push → cleanup`. This file supplies Verbi facts only.
Obtain the global worktree write-gate `PASS` before editing and keep
implementation writes in the canonical isolated worktree.

## Agent Validation Loop

`make validate` is the native project validation entry and selects the
automatic lane through `validate-agent`. Use `make validate-lane` for the
global baseline/artifact wrapper; it defaults to `git merge-base origin/main
HEAD`, accepts `VALIDATE_BASE=...`, and runs with unique ignored
`.xcode-build-tests/validate-lane.*` DerivedData and `.tmp/validate-lane.*`
SwiftPM scratch roots. Both run roots are watched and cleaned before the
wrapper returns; their parent roots and parity-specific roots remain outside
this default lane. Run `make lint` for any Swift delta, then the affected-module
validation when behavior changes.
`make guidance-check` covers guidance-only changes; merge review remains
separate. Swift 6.2/toolchain details live in
`.agents/docs/swift-6-2-agent-baseline.md`.

## Commands and Routing

`Makefile` is the command authority. See [Build and Test Reference](./.agents/docs/build-and-test.md) for the command catalog. Route specialists via [Skill Routing Guide](./.agents/docs/skill-routing.md) only. `.swiftlint.yml` is the lint source of truth; keep lint-specific writing rules in `swift-conventions`.

Do not silently bypass gates, security rules, architectural boundaries, or data-integrity protections.

Run `make guidance-check` after changing this file, `.agents/`, or referenced
command documentation.

## Security and Privacy

Apply least privilege to entitlements and integrations. Validate external input at module boundaries. Keep credentials in Keychain. Do not persist or emit full transcripts, prompts, responses, or secrets in diagnostics or agent result artifacts.

## Completion

Completion requires the relevant `make lint` / `make validate` gates, or
`make guidance-check` for guidance-only changes. Use `make validate-agent` when
an explicit lane is needed. The handoff records
commands, results, assumptions, manual gates, and known baseline failures.
