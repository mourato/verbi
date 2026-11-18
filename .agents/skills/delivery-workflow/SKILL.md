---
name: delivery-workflow
description: This skill should be used when the user asks to classify risk, select a Verbi execution lane, choose validation commands, run quality checks, commit, prepare PRs, merge, or enforce pre-merge workflow.
---

# Delivery Workflow

## Role

Canonical owner for Verbi risk classification, lane gates, validation commands, and pre-merge evidence.

## Scope Boundary

Use for lane selection, command choice, hooks, and Git conventions. Delegate lifecycle, review roteiro, merge, and cleanup to global `ship` and `full-ship`.

## When to Use

Use when a Verbi task needs risk classification, lane selection, validation command choice, pre-merge evidence, or repository Git conventions.

## Project specifics

### Risk classification

| Risk | Use when | Lane |
|---|---|---|
| Low | Docs/comments only, localization updates, constrained non-functional refactor in one module | Fast |
| Medium | Feature/bugfix in one subsystem, UI state behavior, public API change in one package | Full |
| High | Audio, concurrency, persistence, security, cross-module architecture, build/release infra, large or broad deltas | Full |

When uncertain, choose the higher risk. High triggers override Medium.

### Verification by lane

Fast lane:

- Run staged lint/format checks or equivalent lightweight checks when relevant.
- Run scoped checks first when the change could affect behavior.
- Before push/merge, run `make scope-check`.

Full lane:

- Iterate with scoped checks; use `AGENT=1` for compact output.
- Preview an unclear gate with `AGENT=1 make scope-check ARGS="--dry-run --base main"`; a dry run is planning evidence, never a gate.
- Before push/merge, run `make lint` then `make build-test`.

Run comprehensive checks only when risk requires them: `make arch-check`, `make test-full`, `make test-parity`, `make test-ci-strict`, `make benchmark-summary`, `make build-release`, `make test-strict`.

### Scoped validation order

1. Targeted tests: `./scripts/run-tests.sh --suite dev --file <TestFile>` or `./scripts/run-tests.sh --suite dev --test <testName>`.
2. Narrow build: `make build` (prefix `AGENT=1` for compact output).
3. Scope checks: `make preview-check`, `make arch-check`, or `make guidance-check`.
4. Full suite: `make build-test` when the lane or an escalation trigger requires it.

Canonical automation for this sequence: `make scope-check`.

Escalate to `make build-test` for build/release/test infrastructure changes, cross-module or public API changes, audio/persistence/concurrency/security paths, large change sets, low-confidence test mapping, or flaky scoped checks.

Scope checks apply when relevant, not by default: `make arch-check` for boundaries/imports, `make preview-check` for SwiftUI views, `make guidance-check` when editing `AGENTS.md`, `.agents/`, command docs, or routing docs.

### Command set

```bash
make scope-check
make build-test
make lint
make validate

AGENT=1 make scope-check
AGENT=1 make build
AGENT=1 make test
AGENT=1 make lint
AGENT=1 make validate

make preview-check
make arch-check
make guidance-check
```

Compact-mode logs go under `${MA_AGENT_LOG_DIR:-/tmp/ma-agent}`; scripts emit deterministic `AGENT_*` summary lines and `*.result.json` metadata with no prompts, transcripts, file contents, or secrets.

### Hooks and sequencing

- Pre-commit checks staged guidance/localization and scoped Swift lint without modifying the index or worktree.
- Pre-push checks ref/transport metadata only; end-of-task development owns `make validate` and lane checks.
- Run `make lint-fix` deliberately when needed; diverged Swift content defers scoped lint to end-of-task validation.
- For release or high-confidence validation, run `make validate ARGS="--lane full"` plus the explicit paths the risk requires.
- Tests are intentionally not run before every commit; tests stay scoped to behavior and lane/risk requirements.

### Evidence contract

Every handoff, commit, or PR states:

- risk level and selected lane;
- reusable-block decision (`reuse`, `extend`, or `create`);
- files or subsystem inspected;
- commands executed and their results;
- escalation rationale when a broader gate ran;
- known baseline failures and whether they are in scope;
- review outcome, including unresolved Minor findings.

Fast lane evidence includes scoped checks and the final `make scope-check` result. Full lane evidence includes scoped iteration checks, `make lint`, `make build-test`, and the `thermo-nuclear-code-quality-review` semáforo review. Critical and Medium findings block handoff; Minor findings may defer only with an explicit follow-up note.

### Git conventions

- Use Conventional Commits: `<type>(<optional-scope>): <summary>`.
- Keep commits atomic by intent; keep version/build bumps out of functional commits and use `chore(release): bump version` when intended.
- Preserve unrelated worktree changes and do not commit knowingly broken code.
- Use `SKIP_DAILY_VERSION_BUMP=1 git commit -m "<type>(<scope>): <summary>"` for functional commits.
- When work finishes an open issue, the PR body carries `Closes #N`; on the direct merge path, close it with a comment naming the commit.
- Use `gh --body-file` for multiline GitHub content and non-interactive Git commands.
- Stop before rewriting shared history unless the intent is explicit.

## Follows global ship + full-ship

Global `ship` owns the Standard/full implement-validate-review-remediate roteiro; global `full-ship` owns end-to-end merge and cleanup. Delegate merge and PR mechanics there. This skill stays authoritative for the Verbi risk table, lane gates, command names, hooks, and evidence contract above.

Related: `../testing-xctest/SKILL.md`, global `thermo-nuclear-code-quality-review` + `.agents/docs/verbi-review-profile.md`.
