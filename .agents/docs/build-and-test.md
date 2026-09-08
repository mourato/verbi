# Build and Test Reference

This document provides comprehensive CLI and workflow reference for building, testing, and validating changes in Verbi.

## Quick Navigation

Choose commands by lane:

- Canonical Fast/Full/auto technical gate: `make validate-agent ARGS="--lane auto"`
- Workflow fixture gate: `make workflow-test`
- Optional comprehensive validation: `make preflight`

Agent default loop (Low/Fast): run only the smallest changed-path check during
iteration; end of task run strict lint when Swift changed and affected-module
`validate-agent --lane auto` when behavior changed (escalate to Full when the
lane requires it); commit (pre-commit applies staged SwiftFormat/SwiftLint
autofix); push. Pre-push does **not** run build or test validation — that
evidence is owned by the development stage. Do **not** stack manual
working-tree, staged, and committed gates. Guidance-only ranges use
`make guidance-check`. Use
`make validate-agent ARGS="--lane auto --dry-run --base main"` at most once when
the lane is unclear; for Full evidence on a clean tree prefer
`make validate-agent ARGS="--lane auto --base main --agent"` (or `--committed`)
once before push when behavior changed. Treat `validate-agent` as the remembered
technical gate; it proves checks, not merge approval. Required review remains
separate. `scope-check` is an internal engine — do not run both for safety.

Automatic classification treats Swift below `App/`,
`MeetingAssistantAI/Sources/`, and `Packages/MeetingAssistantCore/Sources/` as
production. A trustworthy targeted-test mapping may keep a low-risk production
change in Fast; unmapped changes and high-risk paths still escalate to Full.
Only production paths contribute to the more-than-eight production source-file
threshold. Swift below `Packages/MeetingAssistantCore/Tests/` is test-only and
may remain Fast when it has a trustworthy mapping.

## Primary Build/Test Commands

### Quick start
```bash
make setup
make build
```

### Core workflow commands
```bash
make build-test         # Run build + test in sequence (fast default locally)
make build-test-strict  # Run build + test in strict xcode mode
make build              # Debug build only
make test               # Fast local dev suite
make test-full          # Broad swift-test suite
make test-smoke         # Curated smoke suite
make test-critical-coverage # Coverage for the curated critical smoke flows
make test-perf          # Isolated performance suite
make test-sensitive     # Isolated sensitive subsystem suite
make test-appkit        # Isolated AppKit lifecycle suite
make test-parity        # Xcode parity run
make scope-check        # Scoped validation with smart targeted mapping + escalation
make scope-check ARGS="--committed --base <base> --head <head>"  # Committed range only
make scope-check ARGS="--committed --empty-base --head <head>"  # Full tree from empty base
make workflow-test      # Deterministic validation workflow fixtures (no Xcode)
make test-ci-strict     # Xcode test run without retry/fallback
make preflight          # Build + Test + Lint + Benchmark (full validation)
make preflight-fast     # Lint + Build + Test (skips benchmark, faster feedback)
make deliverable-gate   # build-test + lint
make run                # Run app in debug mode
make build-and-run      # Interactive Debug/Release workflow
make format             # Auto-format with SwiftFormat
make lint               # Run SwiftLint checks
```

### Release and distribution
```bash
make build-release      # Optimized release build
make dmg                # Create DMG installer (auto-detect self-signed identity by exact name)
make setup-self-signed-cert # Bootstrap local self-signed code-signing cert
```

`make build-and-run` never installs Debug into `/Applications`. Release consumes
the signed `dist/Verbi.app`, validates it, and transactionally
replaces only `/Applications/Verbi.app`, restoring the previous bundle on
failure. `--force-terminate` is an explicit fallback after the standard
application quit request times out. `make dmg` remains the packaging flow.
By default, `build-and-run` keeps `.xcode-build` for incremental builds. The
interactive flow asks whether to clean first (default: no); pass `ARGS="--clean"`
to wipe the cache without prompting.

DMG signing mode selection:

```bash
# Auto mode (default via Makefile target): self-signed only if MA_RELEASE_CODE_SIGN_IDENTITY exists
make dmg

# Force ad-hoc mode
MA_RELEASE_SIGNING_MODE=adhoc make dmg

# Force self-signed mode (fails fast if identity is missing)
MA_RELEASE_SIGNING_MODE=self-signed make dmg
```

### Agent-optimized commands (compact output, better for CI/agents)
```bash
make build-test         # Build + test with concise progress
make build-agent        # Debug build only (agent-friendly diagnostics)
make test-agent         # Tests only (machine-readable output)
make scope-check-agent  # Scoped validation in compact agent mode
make test-ci-strict     # Strict xcodebuild run (no fallback/retry)
make lint-agent         # Lint with compact reporting
make lint-strict-agent  # Strict lint with compact reporting
make preflight-agent    # Full validation (agent-optimized)
make preflight-agent-fast # Fast validation (agent-optimized)
```

## Preflight Execution Order Policy

**Default (full verification):**
```
build → test → lint → summary-benchmark
```

**Strict lint gate:**
```bash
make lint-strict-agent
# Strict aliases fail on SwiftLint/SwiftFormat errors while keeping advisory warnings visible.
```

**Fast mode (local feedback only):**
```bash
make preflight-fast         # lint → build → test (skips benchmark)
make preflight-agent-fast   # Agent-optimized fast mode
```

## Direct xcodebuild (when needed)

Use `xcodebuild-safe.sh` to avoid SwiftPM transitive-module resolution instability:

```bash
./scripts/xcodebuild-safe.sh
# Equivalent explicit form:
# xcodebuild -project MeetingAssistant.xcodeproj \
#   -scheme MeetingAssistant \
#   -configuration Debug \
#   -destination 'platform=macOS' build
```

**⛔ NEVER** use bare `xcodebuild build` in this repo.

## Test Workflows

### Run all tests
```bash
make test
make test-agent          # Agent-focused, compact output
make test-full
make test-smoke
make test-critical-coverage
make test-perf
make test-sensitive
make test-appkit
make test-parity
make test-verbose        # Detailed output
make test-ci-strict      # Strict xcodebuild parity mode
```

## Test Suite Selection Matrix

| Suite/Command | Best use case | Typical use |
| --- | --- | --- |
| `make test-smoke` | Quick iteration confidence | Inner loop |
| `make test-critical-coverage` | Coverage measurement for critical smoke flows | Focused periodic check |
| `make test` | Fast local dev suite | Inner loop |
| `make test-full` | Broad swift-test confidence | Pre-gate validation |
| `make test-sensitive` | Audio/concurrency/persistence focus | High-risk subsystem checks |
| `make test-appkit` | Overlay lifecycle coverage | AppKit-specific changes |
| `make test-parity` | Xcode parity diagnostics | Build-system parity checks |
| `make scope-check` | Smart scoped validation + escalation | Iteration feedback |
| `make validate-agent` | Fingerprinted Fast/Full/auto evidence | Technical validation gate |
| `make preflight` | Build + test + lint + benchmark | Optional comprehensive pass |

### Run specific tests
```bash
./scripts/run-tests.sh --suite dev --file RecordingViewModelTests
./scripts/run-tests.sh --suite dev --test testInitialState
./scripts/run-tests.sh --verbose
./scripts/run-tests.sh --agent
```

### Scoped iteration and validation alternatives

Choose the command for the current purpose; do not run every mode as a
sequence:

- **Iteration:** use targeted tests, `make build-agent`, or one relevant scope
  check such as `make scope-check`, `make preview-check`, or `make arch-check`.
- **Final local evidence:** run one clean-tree
  `make validate-agent ARGS="--lane auto"`.
- **Exact committed evidence:** when specifically needed before push, run one
  `make validate-agent ARGS="--lane auto --committed --base <base> --head <head> --agent"`.
- **Pre-push:** let the hook execute or reuse evidence for the exact pushed
  range; do not replay working, staged, and committed modes manually.

Additional diagnostic alternatives, not sequential gates:

```bash
make validate-agent ARGS="--lane auto --staged --base main --agent"
make validate-agent ARGS="--lane auto --committed --empty-base --head <head> --agent"
```

For agent planning, preview the decision without running checks:

```bash
make validate-agent ARGS="--lane auto --dry-run --base main"
```

The Makefile is the command source of truth. Use `make build`, an explicit
`make test`/`make test-full`/suite target, `make test-parity`,
`make scope-check`, `make validate-agent`, or an explicit preflight target
rather than invoking a removed alias. The canonical script mapping is:

| Purpose | Target | Script |
|---------|--------|--------|
| Debug build | `make build` | `scripts/run-build.sh --configuration Debug` |
| Meeting notes editor bundle | `make build-meeting-notes-editor` | `scripts/build-meeting-notes-editor.sh` |
| SwiftPM tests | `make test`, `make test-full`, or a suite target | `scripts/run-tests.sh` |
| Xcode parity | `make test-parity` | `scripts/run-tests-xcode.sh` |
| Scoped validation | `make scope-check` | `scripts/scope-check.sh` |
| Automatic lane | `make validate-agent` | `scripts/validate-agent.sh` |
| Preflight | `make preflight` or a preflight variant | `scripts/preflight.sh` |
| Debug/Release run | `make build-and-run` | `scripts/build-and-run.sh` |

The retired aliases are `build-debug`, `test-swift`, `install-app`,
`install-release`, and `ci-test`.

Escalate early to `make build-test` when touching build/test/release infrastructure, cross-module/public APIs, or high-risk paths (audio, persistence, concurrency, security), or when scoped checks are flaky/inconclusive.

Useful options for the script:

```bash
./scripts/scope-check.sh --dry-run
./scripts/scope-check.sh --max-targeted 12
./scripts/scope-check.sh --base main
./scripts/scope-check.sh --no-build
```

### CI-style local checks
```bash
make ci-build            # Includes arch-check
```

### Deliverable gate (recommended before push/release)
```bash
make deliverable-gate
```
This command keeps fast local iteration while running the build and lint gates.

## Git Hooks Setup

`make setup` configures local Git hooks automatically (`core.hooksPath=scripts/hooks` and executable bits). To configure manually:

```bash
make setup
# or explicitly:
git config --local core.hooksPath scripts/hooks
chmod +x scripts/hooks/pre-commit scripts/hooks/pre-push scripts/hooks/first-commit-version-bump.sh
find scripts/hooks -maxdepth 1 -type f ! -perm -u+x -print
```

The `find` command must print nothing. Stale copies under `.git/hooks/` (for example `pre-push.disabled`) are ignored once `core.hooksPath` points at `scripts/hooks`.

Pre-push acknowledges the push range and enforces basic ref safety; it does not
run `validate-agent`, build, or tests. Complete end-of-task
`validate-agent --lane auto` (or Full when required) during development before
pushing.

### Meeting notes editor bundle

The CM6 editor bundle is committed under
`Packages/MeetingAssistantCore/Sources/UI/Resources/MeetingNotesEditor/dist/`.
Xcode does not rebuild it during app compilation. When you change files under
`Editor/`, run `make build-meeting-notes-editor` before building or testing the
app so the committed bundle stays in sync.

## Script Support Surface

Only scripts explicitly referenced by `Makefile`, `README.md`, `AGENTS.md`, or `.agents` skills/docs are treated as supported developer surface. Other scripts are ad hoc and may be removed during cleanup cycles.

## Linting and Formatting

### Check without fixing
```bash
make lint                # SwiftLint check
./scripts/lint.sh        # Direct lint script
```

### Auto-fix
```bash
make format              # SwiftFormat with auto-fix
./scripts/lint-fix.sh    # Combined lint + format fixes
```

### Specialized checks
```bash
make arch-check          # Architecture boundary/access-control validation
make preview-check       # Per-file SwiftUI preview declaration coverage
./scripts/tests/preview-check-test.sh # Deterministic checker fixtures
```

`make preview-check` verifies that each Settings SwiftUI view source file contains its own
`#Preview` or `PreviewProvider` declaration. A file may be excluded only with
an explicit `preview-check: ignore` or `preview-check: generated` comment.
Pass a source directory directly to `scripts/preview-check.sh` to inspect a
different surface. This is a declaration inventory check: it does not compile
or render previews.
Use `make build-agent` for app compilation. Rendered visual acceptance remains
a manual/Xcode step and must record the inspected widths, states, appearance,
and accessibility settings; text coverage from this script is not visual
evidence.

## Agent Artifacts and Logging

Agents automatically capture build/test output and diagnostics.

**Log directory:**
- Default: `/tmp/ma-agent/`
- Override: `AGENT_LOG_DIR=/custom/path make build-agent`
- Each invocation creates an immutable `run-*` directory below that root. Nested
  commands inherit `MA_AGENT_RUN_DIR`, so concurrent worktrees cannot truncate
  one another's logs or result files.

**Log contents** (deterministic summary lines):
- `AGENT_STEP` — task milestone
- `AGENT_STATUS` — pass/fail status
- `AGENT_DURATION_SEC` — execution time
- `AGENT_LOG` — path to full log file
- `AGENT_ERROR_COUNT` — number of errors
- `AGENT_SUMMARY` — human-readable summary
- `AGENT_RESULT_JSON` — structured result

Agent result files use `schemaVersion: 2` and contain the step status, duration,
error count, executed command summaries, and validation decision. They contain
log paths and metadata only; full logs remain on disk and prompts, transcripts,
file contents, and secrets are never embedded in the JSON.

`validate-agent` adds a content-addressed fingerprint covering the requested and
selected lane, base/head trees, validation content representation, gate inputs,
external gate inputs (tracked SwiftPM lockfiles only), toolchain identities, and
runner schema.
Committed mode materializes `HEAD_REF` in a temporary detached worktree before
selecting or running the gate, unless the checkout is clean and `HEAD` already
matches `HEAD_REF` (in-place committed validation). If tracked external inputs
differ between the original checkout and materialized tree, reuse and PASS-cache
writes are disabled for that run. Gitignored local SwiftPM lockfile copies do
not participate in external-input comparison. Staged and committed modes
exclude unrelated unstaged/untracked state. Only exact `PASS` evidence with
existing child results and matching fingerprints can be reused. Use
`--no-reuse` after flaky or inconclusive behavior; dry-run output is never proof.
Fresh aggregates pass the same schema-v2 child, status, fingerprint, and log
verification before they can be cached or emitted as technical PASS evidence.
A technical PASS does not replace required review or grant merge approval.

On failure, scripts print compact excerpts to terminal while keeping full logs on disk.

## Minimum Verification Gates

**Before push/merge (mandatory):**
- ✓ Canonical lane: `make validate-agent ARGS="--lane auto"`
- ✓ Guidance changes (`AGENTS.md`, `.agents/`, command docs): `make guidance-check`

**Recommended before merge:**
- ✓ `make preflight` — full validation
- ✓ `make lint-strict` — code quality checks

**Pre-release:**
- ✓ `make preflight` + full validation
- ✓ `make build-release` + DMG creation
- ✓ Manual smoke test on target macOS versions

## Common Workflows

| Goal | Command |
|------|---------|
| Local development loop | `make build && make run` |
| Before committing | Pre-commit applies staged SwiftFormat/SwiftLint autofix; fix residual lint manually |
| Before push/release (recommended) | End-of-task `validate-agent --lane auto` (or Full) for behavior changes; pre-push does not re-run build/test |
| Pre-merge validation | `make preflight` |
| Fast local feedback | `make preflight-fast` |
| Smart scoped iteration | `make scope-check` |
| Agent-based pre-merge | `make preflight-agent` |
| Release preparation | `make lint && make build-test && make build-release && make dmg` |
| CI-style check | `make ci-build` |
| Profile performance | `make profile-report` |

## Troubleshooting

**"unstable SwiftPM transitive-module resolution" errors:**
- Use `./scripts/xcodebuild-safe.sh` instead of bare `xcodebuild build`
- Clear build cache: `rm -rf build/`

**Tests fail intermittently:**
- Run tests in isolation: `./scripts/run-tests.sh --suite dev --file SpecificTestFile`
- Check for concurrency/timing issues in test code

**Linter or formatter issues:**
- Verify `.swiftlint.yml` and `.swiftformat` exist and are valid
- Run `make lint-fix` to auto-correct most issues

## References

- SwiftLint config: `.swiftlint.yml`
- SwiftFormat config: `.swiftformat`
- Build scripts: `scripts/` (e.g., `build-release.sh`, `preflight.sh`, `scope-check.sh`)
- Makefile targets: `Makefile` (root)
