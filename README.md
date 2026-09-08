# Verbi for macOS

A native, local-first macOS app for meeting capture, dictation, transcription, and AI-assisted notes. Verbi can detect supported meeting contexts, capture system and microphone audio, transcribe with on-device models via the [FluidAudio SDK](https://github.com/FluidInference/FluidAudio), and keep recordings and transcription history on the Mac.

## Key features

- System and microphone audio capture via ScreenCaptureKit and Core Audio (macOS 15+)
- Meeting detection for Google Meet, Microsoft Teams, Slack, and Zoom
- Separate meeting and dictation workflows with configurable global shortcuts
- On-device transcription through FluidAudio on Apple Silicon; optional remote transcription providers
- Optional AI post-processing for summaries, decisions, action items, and custom prompts
- File import (mp3, m4a, wav)
- Local transcription history, audio playback, and export

## Requirements

- macOS 15.0+ (Sequoia or later)
- Apple Silicon (required for on-device FluidAudio transcription)
- Xcode 26.6 (development; Swift 6.2)
- Xcode command line tools selected (`xcode-select -p`)
- Homebrew (for `make setup`)

## Installation

### First launch

Builds that are not notarized may be blocked by macOS Gatekeeper. If you
downloaded the app from a source you trust, either Control-click
`Verbi.app`, choose **Open**, and confirm, or remove the quarantine
attribute before opening it:

```bash
xattr -dr com.apple.quarantine "/Applications/Verbi.app"
```

This is expected for unsigned, ad-hoc, or self-signed builds. Notarization
requires membership in the paid Apple Developer Program; a free Apple ID is
not sufficient. After approving the app once, open it normally.

## Documentation

- Architecture and operational standards: `AGENTS.md` + `.agents/skills/architecture/SKILL.md`
- Known limitations backlog: GitHub issues labeled `known-limitation`
- Installation, permissions, and troubleshooting: this README

## Development

This project is **CLI-first**, with Xcode supported for debugging and UI iteration. The default transcription path is local; remote providers and AI services are optional and require explicit configuration.

```bash
git clone https://github.com/mourato/verbi.git
cd verbi
./scripts/setup-dev-environment.sh
make build
make run
make dmg
```

`./scripts/setup-dev-environment.sh` verifies the local developer toolchain, including `make`, installs Homebrew-managed tools (`swiftlint`, `swiftformat`), and configures tracked Git hooks (`core.hooksPath=scripts/hooks`). After `make` is available, `make setup` runs the same script. SwiftPM dependencies resolve automatically during build. Local AI model assets may download on first use.

Use `make help` to print the current target list from the `Makefile`.

The `Makefile` is the command source of truth. The script entrypoints behind
the common targets are:

| Purpose | Make target | Script |
|---------|-------------|--------|
| Debug build | `make build` | `scripts/run-build.sh --configuration Debug` |
| Release build | `make build-release` | `scripts/run-build.sh --configuration Release` |
| Meeting notes editor bundle | `make build-meeting-notes-editor` | `scripts/build-meeting-notes-editor.sh` |
| SwiftPM tests | `make test`, `make test-full`, or a suite target | `scripts/run-tests.sh` |
| Xcode parity tests | `make test-parity` | `scripts/run-tests-xcode.sh` |
| Scoped validation | `make scope-check` | `scripts/scope-check.sh` |
| Automatic validation lane | `make validate-agent` | `scripts/validate-agent.sh` |
| Preflight gates | `make preflight` or a preflight variant | `scripts/preflight.sh` |
| Debug/Release run flow | `make build-and-run` | `scripts/build-and-run.sh` |

Agent targets keep their `-agent` names for compact output and shared log
handling. The old aliases `build-debug`, `test-swift`, `install-app`,
`install-release`, and `ci-test` were removed; use the canonical targets above.

### Agent delivery loop

For compact, auditable iteration:

```bash
make scope-check-agent ARGS="--dry-run --base main"  # preview when the gate is unclear
make build-agent                                      # or the smallest relevant check
make lint-strict-agent                                # end of task when Swift changed
make validate-agent ARGS="--lane auto --base main --agent"  # end of task when behavior changed
```

The pre-commit hook applies SwiftFormat and SwiftLint autofix to staged Swift files (re-staging fixes) and does not run tests. The pre-push hook does not run build or test validation — end-of-task development owns `validate-agent` (auto/Full as lane requires). `SKIP_LINT=1` and `SKIP_TESTS=1` are explicit emergency bypasses for local validation commands.

### Make targets

#### Build

| Target | Description |
|--------|-------------|
| `make build` | Build the app in Debug configuration. |
| `make build-release` | Build the app in Release configuration. |
| `make build-agent` | Build Debug with compact agent-oriented output. |
| `make build-test` | Run the standard build and test sequence. |
| `make build-meeting-notes-editor` | Rebuild the CM6 meeting-notes web bundle into `Packages/.../MeetingNotesEditor/dist/` when `Editor/` changed. |
| `make xcodebuild-safe` | Run the canonical wrapped `xcodebuild` command for this repo. |

The meeting notes editor bundle is committed and consumed by Xcode as a resource.
App builds do not run `npm`. After editing `Editor/`, run
`make build-meeting-notes-editor` before `make build` or tests that load the pane.

#### Test and benchmarks

| Target | Description |
|--------|-------------|
| `make test` | Run the fast local development test suite. |
| `make test-agent` | Run tests with compact agent-oriented output. |
| `make test-full` | Run the broad SwiftPM test suite. |
| `make test-verbose` | Run tests with verbose output. |
| `make test-strict` | Run tests with strict concurrency checking enabled. |
| `make test-ci-strict` | Run the strict Xcode parity gate. |
| `make scope-check` | Run scoped validation (targeted checks + automatic escalation to full gate when needed). |
| `make scope-check-agent` | Run scoped validation in compact agent mode. |
| `make benchmark-summary` | Run the summary benchmark gate in report-only mode. |
| `make benchmark-summary-agent` | Run the summary benchmark in compact agent mode. |

#### Quality and verification

| Target | Description |
|--------|-------------|
| `make lint` | Run lint checks. Use `FIX=1 make lint` to auto-fix first. |
| `make lint-agent` | Run lint with compact agent-oriented output. |
| `make lint-fix` | Apply SwiftFormat and SwiftLint autofixes. |
| `make arch-check` | Validate architecture boundary rules. |
| `make preview-check` | Verify SwiftUI preview coverage. |
| `make preflight` | Run the full preflight script (build, test, lint, benchmark). |
| `make preflight-fast` | Run the faster preflight variant. |
| `make preflight-agent` | Run preflight with compact agent-oriented output. |
| `make preflight-agent-fast` | Run the fast preflight variant in agent mode. |
| `make format` | Format source with SwiftFormat. |
| `make health` | Run the repository code health check. |

#### Run and distribution

| Target | Description |
|--------|-------------|
| `make run` | Build Debug and open the app. |
| `make run-release` | Build Release and open the app. |
| `make build-and-run` | Interactively choose Debug or Release; prompts to clean cache (default: keep). |
| `make dmg` | Build Release and create `dist/Verbi.dmg`, prompting for automatic, keychain-identity, or ad-hoc signing. |
| `make setup-self-signed-cert` | Create or import a legacy local self-signed signing certificate. |
| `make new-release` | Build a signed update archive and create a GitHub release with generated notes. |

#### Profiling

| Target | Description |
|--------|-------------|
| `make profile` | Run the full profiling suite. |
| `make profile-report` | Run profiling and export summary metrics. |
| `make profile-cpu` | Run CPU profiling with Time Profiler. |
| `make profile-memory` | Run memory profiling with Allocations. |
| `make profile-animation` | Run Core Animation profiling. |
| `make profile-animation-report` | Run animation profiling and export metrics. |

#### Maintenance and CI

| Target | Description |
|--------|-------------|
| `make clean` | Remove build and distribution artifacts. |
| `make setup` | Install local development dependencies (SwiftLint, SwiftFormat) and configure Git hooks. |
| `make ci-build` | Run the CI build sequence: architecture checks, lint, tests, and release build. |
| `make deliverable-gate` | Run `build-test` and `lint` together. |

#### Documentation

| Target | Description |
|--------|-------------|
| `make docs` | Build the DocC static documentation output into `.agents/docs/api`. |
| `make docs-preview` | Preview DocC documentation locally. |
| `make docs-clean` | Remove generated documentation artifacts. |

### Before push/release

Run the deliverable gate to reduce CI surprises:

```bash
make deliverable-gate
```

This includes `make lint` and `make build-test` (lint runs first as a fast-fail gate).

### Canonical xcodebuild usage

Use the project wrapper (or pass equivalent flags) when invoking `xcodebuild` directly:

```bash
./scripts/xcodebuild-safe.sh
```

Equivalent raw command:

```bash
xcodebuild -project MeetingAssistant.xcodeproj -scheme MeetingAssistant -configuration Debug -destination 'platform=macOS' build
```

Avoid running bare `xcodebuild build` in this repository; it can trigger SwiftPM transitive-module resolution failures.

### B2 architecture layout

The package uses a modular split and an aggregation target:

- `MeetingAssistantCoreCommon` (shared utilities/resources)
- `MeetingAssistantCoreDomain` (entities/protocols/use cases)
- `MeetingAssistantCoreInfrastructure` (integration services)
- `MeetingAssistantCoreData` (persistence repositories)
- `MeetingAssistantCoreAudio` (capture/buffering/worker pipeline)
- `MeetingAssistantCoreAI` (transcription/post-processing/rendering)
- `MeetingAssistantCoreUI` (view models/coordinators/views)
- `MeetingAssistantCore` (compatibility export layer)

Physical source directories under `Packages/MeetingAssistantCore/Sources/` use the short names `Common`, `Domain`, `Infrastructure`, `Data`, `Audio`, `AI`, `UI`, `Core`, `Mocking`, and `MockingMacros`.

Guideline: import only required modules in each file, and expose cross-module APIs intentionally through access control and domain protocols.

### Language standard

- Documentation is maintained in English.
- Code comments are maintained in English.
- UI strings must use localization keys (`"key".localized`), not hardcoded literals.

### Branch and worktree workflow (mandatory)

All changes (code or docs) must be made in a dedicated branch and isolated worktree.

```bash
git worktree add -b <branch-name> .worktrees/<branch-name> main
```

See `AGENTS.md` for the full workflow and project standards.

## Permissions

The app will ask for permissions in **System Settings → Privacy & Security**:

| Permission | Why it is needed |
|-----------|------------------|
| Screen Recording | System audio capture via ScreenCaptureKit |
| Microphone | Fallback audio capture |
| Accessibility | Global shortcuts and Assistant actions |

## Local Apple Development update flow (no Developer ID)

For local-only installs, use the stable Apple Development identity already present in the login Keychain. Developer ID is only needed for public distribution.

```bash
# 1) Build DMG for manual installs
# Interactive mode: detects Apple Development automatically and offers ad-hoc as an alternative
make dmg

# Force Apple Development mode without prompting; fails fast if the identity is missing
MA_RELEASE_SIGNING_MODE=identity make dmg

# Force unsigned/ad-hoc mode without prompting
MA_RELEASE_SIGNING_MODE=adhoc make dmg

```

Notes:
- Keep `CFBundleIdentifier` unchanged between versions.
- Keep `MA_RELEASE_CODE_SIGN_IDENTITY` stable if you customize the identity name.
- `make dmg` builds the Release app, packages it, signs the DMG, and writes `dist/Verbi.dmg`.
- `make dmg` now prompts for signing mode. The default choice is automatic detection: if the configured Apple Development identity is found in the Keychain, the DMG uses it; otherwise it falls back to unsigned/ad-hoc.
- Use `MA_RELEASE_SIGNING_MODE=adhoc make dmg` or `MA_RELEASE_SIGNING_MODE=identity make dmg` to skip the prompt and force a specific mode.
- Install by replacing the existing app in `/Applications` to maximize permission persistence.

AppUpdater releases need a signed ZIP asset named `Verbi-<version>.zip`.
`scripts/build-release.sh` creates this archive beside the app. `make new-release`
builds it and uploads it automatically, and requires the stable Apple Development
identity mode so the updater can compare the code-signing identity between versions.
The release tag must match the app version in `App/Info.plist`.

The main app must remain non-sandboxed for AppUpdater to replace its bundle:
`App/MeetingAssistant.entitlements` is intentionally empty. The sandboxed
`MeetingAssistantAI` XPC target keeps its separate entitlements and is not the
target that performs updates. Do not add App Sandbox to the main app without
replacing this updater flow with a sandbox-compatible installer.

## Troubleshooting

### The model takes a long time to load

On first use, FluidAudio may download and prepare the model(s). This can take a few minutes depending on your network.

### Audio capture does not work

- Check **Privacy & Security → Screen Recording** and ensure Verbi is enabled.
- If you rebuilt/reinstalled the app, macOS may require re-granting permission.

## License

MIT
