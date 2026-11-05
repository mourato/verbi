# Verbi

Verbi is a local-first macOS 15+ app for dictation, meeting capture,
transcription, and AI post-processing. It runs on Apple silicon Macs. It keeps
audio, transcripts, and notes on the Mac unless the user configures a remote
provider for a task. Each install serves one person on one Mac, with no account
and no cloud sync, so a mistake here reaches one user's data and trust.

Identifiers: bundle `com.mourato.verbi`; Xcode app target `Verbi`; SwiftPM
modules `VerbiCore*`.

## What we never compromise

Users record private speech and meetings. These values protect that trust.
Each comes from [PRODUCT.md](PRODUCT.md).

- **Local-first by default.** Audio, transcripts, and notes stay on the device
  unless the user configures a remote provider for that task.
- **Explicit control over capture.** Recording starts from a user action, and
  each reminder layer can be turned off.
- **Native before custom.** macOS controls, materials, and system colors come
  first. A custom surface needs a reason the native one cannot meet.
- **Calm, legible state.** Recording, permissions, configuration, and
  processing state stay obvious, including their failures.
- **Accessibility is part of done.** Keyboard, VoiceOver, and the macOS display
  settings all work. Important state is never shown by color alone.

## Glossary

Full vocabulary is in [GLOSSARY.md](GLOSSARY.md); the domain summary is in
[CONTEXT.md](CONTEXT.md). Terms agents most often misread:

- **Capture session** — one recorded or imported audio unit, for any purpose.
  A dictation is a capture session.
- **Capture mode** — which flow runs: meeting, dictation, or assistant.
  Assistant mode creates no capture session.
- **Capture artifact** — the persisted record of a processed capture. One
  session can own many artifacts.
- **Dictation mode** — a saved set of choices for a class of dictations. Avoid
  "profile", "preset", and "style".
- **Frozen legacy identifiers** — persisted values that keep their current
  value even when the code symbol is renamed.
- **Verbi** — the only product. `MeetingAssistant`, `Vozinha`, and
  `com.mourato.prisma` survive only in migration inputs and frozen identifiers.

## The ways to hurt yourself

Each hazard below breaks user data or trust in a way a diff can hide.

1. **Putting content or secrets in output.** Logs, diagnostics, menu-bar titles,
   and agent artifacts must never carry tokens, transcripts, prompts, responses,
   or PII. Keep secrets in Keychain and keep content out of every output.
2. **Changing persisted identity.** Frozen identifiers, UserDefaults keys, Core
   Data names, and `Codable` raw values drop user state when changed, and macOS
   grants privacy permissions per bundle ID. Rename code symbols only. Keep
   `CFBundleIdentifier` unchanged between ordinary version bumps.
3. **Changing the signing identity.** macOS ties privacy permissions to the
   signing certificate, so a new or lost certificate resets them for every user.
   Keep `MA_RELEASE_CODE_SIGN_IDENTITY` stable and back up the `.p12` with its
   private key.
4. **Editing `Editor/` alone.** App builds do not run npm. The meeting-notes
   editor reaches the app only as a committed bundle. Run
   `make build-meeting-notes-editor` before you build or test the app.
5. **Retrying a release by hand.** `make release-publish` never pushes branches
   or replaces existing tags or assets. A failed publish can leave a GitHub
   draft. Inspect that draft. Then finish it with the prepared assets, or
   delete it deliberately. Never rebuild or overwrite assets silently.

## Hit every surface

Before calling work done, walk this list and say which entries applied:

- **Menu bar and Dock.** One status-item owner, starting at
  `App/AppDelegate/MenuBar.swift`. The activation policy follows Show in Dock
  only, including while Settings is open.
- **Shortcuts and deep links.** Global shortcuts and `verbi://` links run the
  same actions as the menu bar and command router.
- **Settings.** Keep the shared chrome and one owning surface per group, as set
  out in [DESIGN.md](DESIGN.md) under Invariants.
- **Recording indicator and reminder overlay.** Keep the single pill style. The
  reminder keeps its Return and Esc bindings and the actions in DESIGN.md.
- **Meeting notes pane.** Notes panel visibility has one source of truth:
  `RecordingManager.isMeetingNotesPanelVisible`.
- **Permissions.** Microphone, Screen Recording, Accessibility, Calendar, and
  Automation requirements stay explicit in each permission flow.
- **Text.** New user-facing text uses `"key".localized`, with English and
  Portuguese resources. Delete orphaned keys with their text.
- **Local models.** Honor `modelResidencyTimeout`. A new model needs a registry
  entry and an unload hook.
- **Release and Homebrew.** Release notes, the cask, and the signing identity
  follow [README.md](README.md).
- **Accessibility.** For a visual change, check Light and Dark, Reduce Motion,
  Reduce Transparency, increased contrast, and VoiceOver before shipping.

## Working here

Verbi is CLI-first. Xcode serves debugging and UI iteration. The
[Makefile](Makefile) is the command source of truth; `make help` lists targets.

- Run the current checkout or worktree: `make build-and-run`.
- Prepare a release: `make release-prepare VERSION=v1.2.3`. Review its notes,
  then run `make release-publish VERSION=v1.2.3`.
- Setup: `./scripts/setup-dev-environment.sh`, or `make setup`.

Run `make guidance-check` after changing this file, `.agents/`, or referenced
command docs.

Read the linked file before the matching work:

- Product facts (users, purpose, capabilities, constraints): [Product
  contract](PRODUCT.md).
- UI work (surfaces, tokens, states, motion, accessibility): [Design
  contract](DESIGN.md).
- Implementation, validation, or delivery: [Project workflow
  facts](docs/agents/project-workflow.md).
- Review or retro: [Coding standards](CODING_STANDARDS.md).
- Choosing a specialist: [Skill Routing Guide](.agents/docs/skill-routing.md).
- Code entry points, dependency lookup:
  [Navigation](.agents/docs/navigation.md)
- Choosing a build or test command: [Build and Test
  Reference](.agents/docs/build-and-test.md).
- Delivery facts:
  [delivery-workflow skill](.agents/skills/delivery-workflow/SKILL.md)
- Toolchain questions: [Swift 6.2
  baseline](.agents/docs/swift-6-2-agent-baseline.md).
- Reference apps or clone policy: [Reference
  apps](docs/agents/reference-apps.md).

## Verifying

Gate each change with the smallest command that proves it. Never silently
bypass a gate, security rule, architectural boundary, or data-integrity protection: a skipped
check hides the break.

- **Guidance** (`AGENTS.md`, `.agents/`, command docs, `DESIGN.md`): run
  `make guidance-check`. Validation-infrastructure changes also run
  `make workflow-test`.
- **Swift edits**: run `make lint`. For changed files, run `AGENT=1 make lint
  FILES="App/Changed.swift"`. `make lint-report` only reports.
- **Behavior**: run `make test` or `make test-full`, and `make test-parity` for
  Xcode parity. Build with `make build` for compiled surfaces.
- **Editor changes**: run `make build-meeting-notes-editor` first.
- **Visual changes**: run `make preview-check`, then the manual pass in
  [DESIGN.md](DESIGN.md) under Review & Update Triggers.
- **Staged hook**: `scripts/hooks/pre-commit` checks guidance and localization
  on the index snapshot, plus scoped lint. `make test-hook` verifies it.
- **Before push or release**: run `make validate ARGS="--lane auto"`. Full
  validation runs strict lint, then `make build-test`. `VALIDATE_BASE` defaults
  to the merge-base of `origin/main` and `HEAD`.

## Taste

Project preferences, in positive form:

- Write documentation and code comments in English.
- Use SwiftUI first. Use AppKit where SwiftUI cannot express the system behavior
  reliably: status items, panels, window chrome, lifecycle, permissions.
- New SwiftUI state uses Observation. Keep `ObservableObject` until a migration
  is verified.
- Use semantic system colors and native materials. Keep system values out of
  product tokens.
