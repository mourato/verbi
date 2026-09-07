# AGENTS.md - Prisma Development Guide

## Identity and Purpose

Vozinha is the display brand for this local-first macOS meeting capture, transcription, and AI post-processing app. Technical identifiers remain Prisma-stable by design. Use this repository's CLI-first workflow and Clean Architecture boundaries to make focused, reproducible changes.

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
Prisma/Vozinha facts and hard constraints only.

Vozinha-specific high-risk surfaces are audio, concurrency, persistence,
security, cross-module architecture, and release infrastructure.

## Delivery lifecycle

The global `core/policies/worktrees.md` is authoritative for isolation and
delivery order: `create → work → commit → review → remediation → merge →
validate → push → cleanup`. This file supplies Prisma/Vozinha facts only.
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

<<<<<<< HEAD
Run `make guidance-check` after changing this file, `.agents/`, or referenced
command documentation.
=======
Do not silently bypass gates, security rules, architectural boundaries, or data-integrity protections.

## Risk and Delivery Lanes

| Risk | Triggers | Lane |
|---|---|---|
| Low | Docs/comments, localization, or non-functional refactor in one module | Fast |
| Medium | One-subsystem feature/bugfix, one-package public API, or UI state logic without High triggers | Full |
| High | Audio, concurrency, persistence, security, cross-module architecture, build/release infrastructure, 300+ added lines, or more than 8 source files | Full |

Fast lane:

- Use a feature branch and small implementation slices.
- Run the smallest relevant changed-path checks.
- Use `make scope-check` as the merge gate.

Full lane:

- Use a new feature branch and atomic commits.
- Run targeted checks and narrow builds during iteration.
- Before push/merge, run `make lint` and `make build-test`.
- Changes to `scripts/`, `Makefile`, build/test infrastructure, or broad architecture require the full gate even when mapping appears narrow.
- Full code review uses the thermo-nuclear semaforo: fix all Critical and Medium findings before merge.

During iteration, prefer:

```bash
make scope-check-agent ARGS="--dry-run --base main"
make build-agent
make test-agent
make lint-agent
make guidance-check
```

Use targeted tests before narrow builds, and scope-specific checks only when relevant. The staged pre-commit hook performs SwiftFormat/SwiftLint without tests; the pre-push hook runs compact scoped validation. `SKIP_LINT=1` and `SKIP_TESTS=1` are emergency bypasses only. Use `make preflight-agent` or `make deliverable-gate` for release or high-confidence validation.

## Canonical Commands and References

`Makefile` is the command authority. Use:

- `make build`, `make build-agent`, `make build-test`
- `make test`, `make test-agent`, `make test-full`, `make test-smoke`
- `make scope-check`, `make scope-check-agent`
- `make lint`, `make lint-agent`, `make lint-fix`
- `make arch-check`, `make preview-check`, `make guidance-check`
- `make preflight`, `make preflight-agent`, `make deliverable-gate`
- `make dmg` for distribution; it auto-detects the configured local signing identity

Read [Build and Test Reference](./.agents/docs/build-and-test.md) for command details and [Skill Routing Guide](./.agents/docs/skill-routing.md) for specialist selection. `.swiftlint.yml` is the lint source of truth; keep lint-specific writing rules in `swift-conventions`.

## Skill and Information Routing

Use the canonical skill for the task and no unrelated specialists. `macos-app-engineering` owns ordinary macOS UI/app implementation; `architecture`, `swift-concurrency-expert`, `audio-realtime`, `data-persistence`, `keychain-security`, `debugging-diagnostics`, `localization`, `testing-xctest`, `delivery-workflow`, `project-standards`, and `thermo-nuclear-code-quality-review` own their named domains.

The default Codex session is the orchestrator. Automatically use the global custom-agent catalog at `~/.codex/agents/` when work is genuinely parallelizable, without waiting for the user to request delegation: `explorer` and `diagnostician` are read-only, `reviewer` is read-only, and only one `implementer` may write. The implementer must run in an isolated git worktree and must receive the canonical primary skill plus no more than two complementary skills. Do not load every skill into every child; follow `.agents/docs/skill-routing.md`.

For external project code or documentation, prefer `MCP grep`, then `gh`, then DeepWiki, and use web search last.

Route new knowledge in this order:

1. Absorb reusable operational guidance into `.agents/skills/`.
2. Track pending work or limitations in GitHub issues with appropriate labels.
3. Delete stale or duplicated material.

Do not create a root-level `docs/` directory. Durable references belong in `.agents/docs/`; project policy belongs here or in the owning skill. Run `make guidance-check` after changing this file, `.agents/`, or referenced command documentation.
>>>>>>> chore/agent-orchestration

## Security and Privacy

Apply least privilege to entitlements and integrations. Validate external input at module boundaries. Keep credentials in Keychain. Do not persist or emit full transcripts, prompts, responses, or secrets in diagnostics or agent result artifacts.

## Completion

Completion requires the relevant `make lint` / `make validate` gates, or
`make guidance-check` for guidance-only changes. Use `make validate-agent` when
an explicit lane is needed. The handoff records
commands, results, assumptions, manual gates, and known baseline failures.
