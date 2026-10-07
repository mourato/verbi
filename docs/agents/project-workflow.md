# Project workflow facts

Read before implementation, validation, or delivery. Paths below name repository-root facts; links resolve from this document. Shared project conventions (UI contract, reference apps, lint baseline, `validate-lane`, pre-commit hook) live in `${AGENT_CONFIG_HOME:-$HOME/.agents}/core/policies/project-context.md`.

## Identity and Purpose

Verbi is the display brand for this local-first macOS meeting capture, transcription, and AI post-processing app. Product and technical identifiers use Verbi (`com.mourato.verbi`); MeetingAssistant* remains the Xcode/SwiftPM scaffold. Use this repository's CLI-first workflow and Clean Architecture boundaries to make focused, reproducible changes.

## Project Context

- macOS 15+ is the minimum target; macOS 26 APIs need `#available(macOS 26, *)` guards with macOS 15 fallbacks; macOS 27 is preview-only.
- SwiftUI-first UI with AppKit for status items, panels, lifecycle, and permissions SwiftUI cannot express reliably.
- `Packages/MeetingAssistantCore/Sources/` uses short dirs: `Common`, `Domain`, `Infrastructure`, `Data`, `Audio`, `AI`, `UI`, `Core`, `Mocking`, `MockingMacros`.
- Colocate types (`Services/RecordingManager/RecordingManager.swift`).
- Public SwiftPM targets remain `MeetingAssistantCore*`; physical paths and public imports differ.

Module ownership: `Common`, `Domain`, `Infrastructure`, `Data`, `Audio`, `AI`, `UI`, `Core` — utilities, entities, adapters, persistence, capture, transcription, presentation, exports respectively.
- Menu-bar keeps one explicit status-item owner starting at `App/AppDelegate/MenuBar.swift`; the floating recording indicator lives under `Packages/MeetingAssistantCore/Sources/UI/` and follows reactive recording state.
- Inspect the recording indicator, onboarding, settings, and menu-bar surfaces before introducing new motion or material tokens; keep capture → transcription → AI post-processing states legible.

## Non-Negotiable Rules

- User-facing strings use `"key".localized`; remove orphaned keys when text is deleted.
- Never hardcode secrets; use Keychain and avoid logging tokens, transcripts, or PII.
- `modelResidencyTimeout` applies to every local model; new models need registry entries and unload hooks.

## Agent workflow

Project skills load from `.agents/skills/{name}/SKILL.md` in this worktree;
`delivery-workflow` supplies Verbi delivery facts. Do not silently bypass
gates, security rules, architectural boundaries, or data-integrity protections.
Use `make validate` when an explicit lane is needed.

For code entry points and dependency lookup, read [Navigation](../../.agents/docs/navigation.md).

Verbi-specific high-risk surfaces are audio, concurrency, persistence,
security, cross-module architecture, and release infrastructure.

## Agent Validation Loop

`make validate` selects its automatic lane through the `validate-agent.sh` engine; `make validate-lane` supplies the global wrapper. `VALIDATE_BASE` defaults to merge-base `origin/main HEAD`; unique ignored `.xcode-build-tests/validate-lane.*` DerivedData and `.tmp/validate-lane.*` SwiftPM scratch are watched and cleaned. Parent/parity roots remain. Run `make lint` for every Swift delta and affected-module validation for behavior. Guidance-only: `make guidance-check`; toolchain: `.agents/docs/swift-6-2-agent-baseline.md`.

## Commands and Routing

Run `make guidance-check` after changing this file, `.agents/`, or referenced
command documentation. Guidance-only changes use `make guidance-check`;
validation-infrastructure changes also require `make workflow-test`.
Use `AGENT=1 make lint FILES="App/Changed.swift"` for changed-file proof; `make lint-report` is report-only. Staged hook: `scripts/hooks/pre-commit`; `make test-hook` verifies guidance/localization on index snapshots and scoped lint. Reproduce with `make guidance-check` and `AGENT=1 make lint`.

## Security and Privacy

Apply least privilege to entitlements and integrations. Validate external input at module boundaries. Keep credentials in Keychain. Do not persist or emit full transcripts, prompts, responses, or secrets in diagnostics or agent result artifacts. CloudKit synchronization is intentionally absent. Menu-bar titles, logs, and diagnostics must not carry transcript, prompt, credential, or model internals. Permission flows must communicate microphone, Screen Recording, and Accessibility requirements explicitly.
