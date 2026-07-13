# AGENTS.md - Prisma Development Guide

## Identity and Purpose

Prisma is a local-first macOS meeting capture, transcription, and AI post-processing app. Use this repository's CLI-first workflow and Clean Architecture boundaries to make focused, reproducible changes.

## Project Context

- macOS 15+ remains the minimum deployment target. macOS 26 APIs require `#available(macOS 26, *)` guards and macOS 15 fallbacks; macOS 27 APIs are preview-only.
- Swift 6.2+ is the baseline. Strict concurrency is enabled; default actor isolation remains nonisolated, so keep actor boundaries and `Sendable` reasoning explicit.
- UI is SwiftUI-first with AppKit for status items, panels, lifecycle, permissions, and capabilities SwiftUI cannot express reliably.
- New SwiftUI state prefers Observation; preserve `ObservableObject` surfaces until an intentional migration is verified.
- `Packages/MeetingAssistantCore/Sources/` uses short physical directories: `Common`, `Domain`, `Infrastructure`, `Data`, `Audio`, `AI`, `UI`, `Core`, `Mocking`, and `MockingMacros`.
- Public SwiftPM target names remain `MeetingAssistantCore*`; physical source paths and public imports are different concerns.
- Split types into colocated directories such as `Services/RecordingManager/RecordingManager.swift` and unique owner-prefixed siblings. Do not use `Type+Concern.swift` filenames.

Module ownership:

- `Common`: shared utilities, resources, and logging
- `Domain`: entities, protocols, and use cases
- `Infrastructure`: adapters and providers
- `Data`: persistence repositories and storage
- `Audio`: capture, buffering, and processing
- `AI`: transcription, post-processing, and rendering
- `UI`: view models, coordinators, and presentation
- `Core`: compatibility export surface

## Non-Negotiable Rules

- Prefer correctness, reliability, and safety over short-term convenience. Remove avoidable complexity rather than preserving a merely working design.
- Before coding, scan for reusable blocks and follow `reuse → extend → create`. Do not copy implementations or add speculative abstractions.
- Classify risk before implementation using the matrix below. When uncertain, choose the higher level.
- Clarify ambiguity that changes behavior, safety, architecture, or acceptance criteria; document minor assumptions.
- Never commit knowingly broken code. Use atomic Conventional Commits: `<type>(<scope>): <summary>`.
- User-facing strings use `"key".localized`; remove orphaned localization keys when text is deleted.
- Never hardcode secrets. Use Keychain-backed handling and avoid logging tokens, transcripts, or personal identifiers.
- Do not stack redundant UI copy or helper surfaces in one viewport.
- `modelResidencyTimeout` applies to every local model runtime. New local models require registry entries and unload hooks.
- Prefer files at or below 600 lines; split oversized files by owning type and concern.
- Prefer structured concurrency and `Task.sleep(for:)`; use `DispatchQueue` only for framework callbacks or legacy integration. Justify `Task.detached`.

## Git Safety

- Preserve unrelated worktree changes.
- Do not use destructive commands such as `git reset --hard` or `git checkout --` without explicit authorization.
- Do not rewrite shared history without explicit authorization.

## Policy Precedence

When guidance conflicts, apply this order:

1. This `AGENTS.md`.
2. The relevant skill in `.agents/skills/`.
3. Reference documents, examples, and inline comments.

Hard constraints in this file always override convenience or performance preferences. If a conflict remains material, stop and ask before implementing behavior.

## Deviations and Exceptions

If a task would violate a hard constraint or requires an exceptional workflow:

1. Stop and capture the smallest reproducible example or decision.
2. Record the constraint, reason, scope, impact, rollback, and expiry/review date.
3. Track the limitation or exception in GitHub with `known-limitation` or `needs-review`.
4. Update this file or the owning skill so the same deviation is harder to repeat.
5. Obtain explicit reviewer sign-off before merge.

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

## Security and Privacy

Apply least privilege to entitlements and integrations. Validate external input at module boundaries. Keep credentials in Keychain. Do not persist or emit full transcripts, prompts, responses, or secrets in diagnostics or agent result artifacts.

## Self-Check Before Handoff

- Reuse/extend/create was considered.
- Risk and lane are recorded.
- Relevant scoped checks and required lane gates were run.
- No hard constraint was violated.
- The change is in the correct module/file boundary and does not add avoidable branching or coupling.
- Evidence includes commands, results, assumptions, and known baseline failures.
- Every implementation handoff reports risk/lane, the `reuse → extend → create` decision, validations executed, and known limitations.
