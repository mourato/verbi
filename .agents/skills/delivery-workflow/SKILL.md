---
name: delivery-workflow
description: This skill should be used when the user asks to classify risk, select a Verbi execution lane, choose validation commands, run quality checks, commit, prepare PRs, merge, or enforce pre-merge workflow.
---

# Delivery Workflow

## Role

Use this skill as the canonical owner for Verbi task delivery from risk classification through integration.

- Own risk classification, Fast/Full lane selection, lifecycle sequencing, validation command mapping, Git mechanics, and evidence reporting.
- Keep delivery work aligned with `AGENTS.md`, `Makefile`, repository hooks, and Conventional Commits.
- Delegate implementation-specific testing and review details to specialist skills.

## Scope Boundary

Use this skill for:

- classifying task risk and selecting Fast/Full lane
- sequencing implementation work
- choosing scoped validation and merge-gate commands
- deciding when to escalate to full gates
- branch, commit, PR, merge, push, and cleanup mechanics
- reporting verification evidence and baseline failures

Use specialist skills when the task is primarily about:

- `../testing-xctest/SKILL.md` for XCTest structure, async tests, fakes, spies, and fixtures.
- `../thermo-nuclear-code-quality-review/SKILL.md` for review findings, semaforo severity, approval bars, and strict structural maintainability review.
- subsystem skills for domain-specific rules, such as audio, persistence, concurrency, security, UI, localization, or intelligence-kernel work.

## When to Use

Use this skill when a Verbi task needs risk classification, delivery sequencing, validation command selection, Git operations, PR/merge workflow, or pre-merge evidence.

## Risk Classification

Classify before implementation:

| Risk | Use when | Lane |
|---|---|---|
| Low | Docs/comments only, localization updates, constrained non-functional refactor in one module | Fast |
| Medium | Feature/bugfix in one subsystem, UI state behavior, public API change in one package | Full |
| High | Audio, concurrency, persistence, security, cross-module architecture, build/release infra, large or broad deltas | Full |

When uncertain, choose the higher risk. High triggers override Medium.

## Lifecycle

1. Identify scope and likely owner skills.
2. Scan for reusable services, helpers, components, and patterns: `reuse -> extend -> create`.
3. Clarify material ambiguity; state minor assumptions.
4. Implement in small slices.
5. Run targeted checks first, then narrow builds and relevant scope checks.
6. Before push/merge, run the lane gate.
7. Use `../thermo-nuclear-code-quality-review/SKILL.md` for review when review is required; Full lane requires semaforo review with the thermo structural bar.
8. Fix Critical/Medium review findings, re-run required gates, then integrate and clean up.

## Delegated Execution

Use the global custom-agent catalog when delegation reduces total coordination cost. Keep exploration, diagnosis, and review read-only. Delegate implementation to one `implementer` only after the scope and primary skill are known; require an isolated worktree and stop if the child is attached to the active checkout. Run `reviewer` after implementation when the lane or task risk requires review. Do not spawn parallel writers.

## Verification by Lane

### Fast lane (Low risk)

Minimum expectation:

- Run staged lint/format checks or equivalent lightweight checks when relevant.
- Run scoped checks first when the change could affect behavior.
- Before push/merge, run `make scope-check`.

### Full lane (Medium/High risk)

Minimum expectation:

- During development, run scoped checks continuously.
- Prefer compact `*-agent` commands during iteration; use `make scope-check-agent ARGS="--dry-run --base main"` as a planning preview when the gate is unclear.
- Reserve `make build-test` for milestone validation and mandatory merge gate.
- Before push/merge, run:
  - `make lint` (fast-fail before build)
  - `make build-test`

`make preflight` remains optional and does not replace lane merge gates.

### Evidence Contract

Every handoff, commit, or PR must state:

- risk level and selected lane;
- reusable-block decision (`reuse`, `extend`, or `create`);
- files or subsystem inspected;
- commands executed and their results;
- escalation rationale when a broader gate ran;
- known baseline failures and whether they are in scope;
- review outcome, including unresolved Minor findings when applicable.

Fast lane evidence must include scoped checks and the final `make scope-check` result. Full lane evidence must include scoped iteration checks, `make lint`, `make build-test`, and the thermo-nuclear semaforo review. A dry-run is planning evidence only and never substitutes for the executed gate.

## Scoped Validation

Use this order during implementation:

1. Targeted tests: `./scripts/run-tests.sh --suite dev --file <TestFile>` or `./scripts/run-tests.sh --suite dev --test <testName>`.
2. Narrow build confidence: `make build-agent` or `make build`.
3. Scope-specific checks: `make preview-check`, `make arch-check`, or `make guidance-check`.
4. Full suite gate: `make build-test` when required by lane or escalation triggers.

Canonical automation for this sequence: `make scope-check`.

Escalate immediately to full suite (`make build-test`) when:

- build/release/test infrastructure changes (`Makefile`, `scripts/`, `.github/workflows`, `Package.swift`, project config)
- cross-module or public API changes
- audio, persistence, concurrency, or security-sensitive paths
- large change sets or low-confidence test mapping
- scoped checks show flaky or inconsistent behavior

Run these scope checks only when relevant:

- `make arch-check` for architecture boundary, access-control, or import-rule changes.
- `make preview-check` when adding or changing SwiftUI views.
- `make guidance-check` when editing `AGENTS.md`, `.agents/`, command docs, routing docs, or referenced guidance.

## Practical Command Set

```bash
# Core gates
make scope-check
make build-test
make lint
make preflight

# Compact AI-agent mode
make build-agent
make test-agent
make lint-agent
make scope-check-agent
make preflight-agent

# Scope-specific checks
make preview-check
make arch-check
make guidance-check

# Targeted tests
./scripts/run-tests.sh --suite dev --file <TestFile>
./scripts/run-tests.sh --suite dev --test <testName>
./scripts/run-tests.sh --agent
```

Compact-mode notes:

- Full logs are written under `${MA_AGENT_LOG_DIR:-/tmp/ma-agent}`.
- Scripts emit deterministic `AGENT_*` summary lines for pass/fail parsing.
- `*.result.json` files use schema version 2 with command summaries and the selected validation decision; they contain metadata and log paths, never prompts, transcripts, file contents, or secrets.
- Use compact mode for iteration; keep lane merge gates unchanged.

Agent delivery sequence:

1. Preview the scoped decision when needed with `make scope-check-agent ARGS="--dry-run --base main"`; this does not prove the change.
2. Run the smallest meaningful changed-path check: targeted tests, `make build-agent`, `make preview-check`, `make arch-check`, or `make guidance-check`.
3. Before commit, the staged pre-commit hook runs SwiftFormat and SwiftLint for staged Swift files. Run `make lint-fix` when it fails; `SKIP_LINT=1` is an explicit emergency bypass.
4. Before push, the pre-push hook runs `make scope-check-agent ARGS="--base <default-branch>"`. Set `PUSH_CHECK_VERBOSE=1` for human-readable output; `SKIP_TESTS=1` remains an emergency bypass.
5. Full-lane changes still require `make lint` and `make build-test`. `STRICT_LINT=1 make lint-agent` currently reports the repository baseline and is not a merge gate until it passes.
6. Use `make preflight-agent` or `make deliverable-gate` for release or high-confidence validation.

Tests are intentionally not run before every commit: staged lint/format is the cheap mechanical gate, while tests remain scoped to behavior and lane/risk requirements.

## Git Workflow

- Preserve unrelated worktree changes.
- Use Conventional Commits: `<type>(<optional-scope>): <summary>`.
- Keep commits atomic by intent: feature, fix, refactor, tests, docs, cleanup, review fix.
- Keep version/build bumps out of functional commits. The pre-commit hook may run `scripts/hooks/first-commit-version-bump.sh`; use `SKIP_DAILY_VERSION_BUMP=1 git commit ...` for normal atomic commits, then make a separate `chore(release): bump version` commit when a release/version bump is actually intended.
- Do not commit knowingly broken code.
- Use PRs for non-trivial work unless the user explicitly chooses the direct local merge path.
- Prefer a GitHub PR with squash merge for non-trivial work. Use the direct local merge exception only when opening a PR is impractical, and record the rationale in the commit or a follow-up issue.
- Use `gh --body-file` patterns for multiline GitHub content.
- Prefer non-interactive Git commands.
- Avoid destructive commands unless the user explicitly requested them.
- Stop before rewriting shared history unless the intent is explicit.

Standard commands:

```bash
git status --short
git diff --stat
git add <files>
SKIP_DAILY_VERSION_BUMP=1 git commit -m "<type>(<scope>): <summary>"
git push origin <branch>
```

Use temporary files for multiline GitHub Markdown to avoid shell interpolation problems:

```bash
cat <<'EOF' >/tmp/prisma-gh-body.md
## Summary
- ...

## Verification
- ...
EOF
gh pr create --body-file /tmp/prisma-gh-body.md
gh issue comment <id> --body-file /tmp/prisma-gh-body.md
```

PR descriptions should include a concise summary, scope/risk, validation commands and results, review findings, baseline failures, and rollback or follow-up notes when relevant. Never include secrets, full transcripts, or large raw logs.

## Evidence To Report

Always report:

- risk level and lane
- reusable-block decision
- commands run and result
- review outcome when relevant
- escalation rationale, if any
- known baseline failures, if any

For Full lane work, Critical and Medium review findings block handoff until fixed. Minor findings may be deferred only with an explicit follow-up note.

## Hook and Troubleshooting Notes

- Install hooks with `git config core.hooksPath scripts/hooks`.
- `pre-commit` runs blocking lightweight staged checks for Swift files and does not run tests.
- `pre-push` enforces compact scoped validation unless explicitly bypassed.
- Emergency bypasses should be rare and followed by immediate remediation.
- If tools are missing, install SwiftLint and SwiftFormat with `brew install swiftlint swiftformat`.

## Related Skills

- `../testing-xctest/SKILL.md`
- `../thermo-nuclear-code-quality-review/SKILL.md`

## References

- `AGENTS.md`
- `Makefile`
- `scripts/lint.sh`
- `scripts/run-tests.sh`
