# Implementation Plans

This is the active plan ledger. The next available plan number is 139.

## Execution rules

- Read the complete plan and honor its STOP conditions.
- Keep one objective per execution slice and use `reuse -> extend -> create`.
- Respect dependencies and reclassify risk against the live scope.
- Preserve one writer in an explicitly isolated worktree.
- Run the plan's required lane, review, and validation before marking it done.
- Use atomic Conventional Commits; do not push unless requested.
- Keep product source out of guidance-only plans.

Status values: `TODO` | `IN PROGRESS` | `DONE` | `BLOCKED` | `REJECTED`.

## Active and current batch

| Plan | Title | Priority | Effort | Depends on | Status |
|---|---|---:|---:|---|---|
| [083](083-add-settings-form-visual-and-preview-gates.md) | Add route-wide visual evidence and truthful preview gates for Settings | P1 | M | 079, 080, 081, 082 | TODO |
| [102](102-close-fast-validation-gate.md) | Make Fast and guidance pushes pass a real technical gate | P0 | M | - | DONE |
| [103](103-align-auto-lane-with-risk-policy.md) | Make auto lane conservative for product Swift changes | P0 | M | 102 | DONE |
| [104](104-centralize-agent-routing-ownership.md) | Make `agent-ops` the single owner of delegation and profile selection | P1 | S | 103 | DONE |
| [105](105-prune-agent-operational-context.md) | Prune dead agent context and make guidance drift fail closed | P1 | L | 104 | DONE |
| [106](106-snapshot-mode-dictation-configuration.md) | Persist and snapshot dictation configuration per mode | P0 | L | - | DONE |
| [107](107-relocate-dictation-settings-into-mode-drawer.md) | Relocate Dictation settings into the mode drawer and retire the tab | P0 | L | 106 | DONE |
| [108](108-move-assistant-integrations-into-drawers.md) | Move Assistant and Integrations into Dictation Modes drawers | P0 | L | 107 | DONE |
| [109](archive/completed/109-promote-dictionary-and-add-vocabulary-workflow.md) | Promote Dictionary and add a separate vocabulary workflow | P1 | L | 108 | DONE |
| [110](archive/completed/110-wire-vocabulary-through-transcription.md) | Wire vocabulary snapshots through transcription and enhancement | P1 | L | 109 | DONE |
| [111](archive/completed/111-add-dictionary-quick-add-panel.md) | Add the VoiceInk-style Dictionary quick-add panel | P1 | L | 109 | DONE |
| [112](112-rebrand-visible-app-name-to-verbi.md) | Rebrand the visible app name to Verbi | P1 | L | - | DONE |
| [113](113-interactive-release-build-and-install-runner.md) | Add an interactive Release-aware build and install runner | P1 | L | 112 | DONE |
| [114](114-prune-dated-agent-guidance.md) | Prune dated agent guidance without losing durable rules | P0 | M | 105 | DONE |
| [115](115-promote-localization-integrity-gate.md) | Promote localization integrity to a deterministic gate | P0 | M | 102 | DONE |
| [116](116-reuse-scope-check-decision.md) | Reuse the scope-check decision in agent validation | P1 | S | 103 | DONE |
| [117](117-cache-agent-swiftpm-resolution.md) | Cache agent SwiftPM resolution safely | P1 | M | 102 | DONE |
| [118](118-report-first-agent-artifact-cleanup.md) | Add report-first cleanup for agent build artifacts | P2 | M | 102 | DONE |
| [119](119-adopt-global-macos-skill-overlays.md) | Adopt global macOS skills with the verbi project overlay | P1 | M | global plan 004; 112–118 reconciled | DONE |
| [120](120-establish-swift-6-2-agent-baseline.md) | Establish the Swift 6.2 agent baseline | P0 | L | 119; clean/reconciled worktree | DONE (merged in `9f1d3603`; review fix `0ec9eacb`) |
| [121](121-deepen-transcription-execution-seam.md) | Centralize transcription execution behind one explicit request seam | P1 | L | 106, 110 | DONE |
| [122](122-extract-recording-lifecycle-boundary.md) | Extract the RecordingManager lifecycle boundary | P1 | L | 121 | DONE (merged in `183bee4e`; remediation `61b13e7f`) |
| [123](123-centralize-post-processing-request-seam.md) | Centralize post-processing behind one explicit request seam | P1 | L | 122 | DONE (merged in `8a5907e9`) |
| [124](124-persist-execution-provenance.md) | Persist execution provenance for transcription and post-processing | P1 | L | 123 | DONE (merged in `35e8fefb`; review remediation `0c80c993`) |
| [125](125-reduce-settings-singleton-coupling.md) | Reduce operation-time coupling to AppSettingsStore.shared | P1 | M | 122, 123, 124 | DONE (merged in `49d83d6a`) |
| [126](126-meeting-reminder-scheduler-slapss.md) | Proactive meeting reminders with full-screen overlay (Slapss-inspired) | P1 | L | ADR 001 | TODO |
| [127](127-meeting-notes-pane-ux.md) | Raycast-style meeting notes panel with WebKit editor (Pane-inspired) | P1 | L | ADR 002; 126 slice 4b recommended | TODO |
| [128](128-dictation-eager-model-warmup.md) | Eager purpose-aware ASR warmup during dictation capture | P1 | M | — | REVIEWED (`99393e84`, merged local) |
| [129](129-dictation-shortcut-hybrid-parity.md) | Characterize/parity hybrid+PTT dictation shortcuts | P1 | M | — | REVIEWED (`b35a94a3`, merged local) |
| [130](130-dictation-incremental-ready-gate.md) | Bound early incremental audio until ASR is ready | P1 | M | 128 | REVIEWED (`f0622716`, merged local) |
| [131](131-dictation-post-session-unload.md) | Unload local ASR after dictation idle grace | P1 | M | 128 | REVIEWED (`d0ad592b`, merged local) |
| [132](132-enable-dictation-intelligence-mode.md) | Enable dictation Intelligence Kernel mode gating | P2 | M | prefer after 128–131 | REVIEWED (`7035c28e`, merged local) |

| [133](133-visual-surface-contract.md) | Establish the shared visual surface contract | P1 | M | - | REVIEWED (`a915fc91`, merged local) |
| [134](134-simplify-settings-sidebar.md) | Simplify the Settings shell and sidebar | P1 | M | 133 | REVIEWED (`e0258d5d`, merged local) |
| [135](135-normalize-settings-surfaces.md) | Normalize Settings surfaces and visual density | P1 | L | 133, 134 | REVIEWED (`852b907a`, merged local) |
| [136](136-lighten-transcription-history.md) | Lighten transcription history with progressive disclosure | P1 | L | 133, 135 | REVIEWED (`fcc00f7d`, merged local) |
| [137](137-recompose-activity-dashboard.md) | Recompose Activity around a clear first-fold story | P1 | M | 133, 135 | REVIEWED (`51d40c59`, merged local) |
| [138](138-simplify-recorder-surface.md) | Simplify the recorder surface and reveal secondary controls progressively | P1 | M | 133 | REVIEWED (`015f252a`, merged local) |

## Dependency order

The Settings reorganization batch is `106 -> 107 -> 108 -> 109`, followed by
runtime vocabulary integration in 110. Plan 111 also depends on 109 and can run
in parallel with 110 only in a separate isolated worktree after confirming that
the shared Dictionary service API is stable. The remediation batch is
`102 -> 103 -> 104 -> 105`. Plan 083 is independent.

Plan 112 is independent of the Settings reorganization batch, but must remain a
single coordinated workstream because it changes shared build, runtime, and
release identity values. It intentionally preserves `com.mourato.prisma`, the
XPC identifier, storage directories, Keychain service, UserDefaults domains,
and `MeetingAssistant*` internal names.

Plan 113 depends on the Release-visible identity from Plan 112. It adds the
interactive Debug/Release runner, installs only Release into the exact
`/Applications/Verbi.app` target, and must preserve the technical identity
contract from Plan 112. Its AppKit shutdown route and filesystem replacement
transaction are one serial workstream; do not parallelize them.

Plans 114 through 118 are the agent-cost and delivery-automation batch. Plan
114 is guidance-only and should run before routing changes. Plans 115, 116, and
117 are validation infrastructure and should be implemented as separate serial
workstreams. Plan 118 is report-first and must not delete artifacts until its
allowlist and dry-run evidence are accepted. Skill selection otherwise remains
semantic and follows the standard skill descriptions and project guidance.

Plan 121 is a serial architecture migration after the completed dictation
configuration and vocabulary snapshot work in Plans 106 and 110. It owns the
shared transcription request seam across full-file, retry, incremental,
Assistant, provider, and XPC paths; do not parallelize those paths.
Its implementation is reviewed and merged into local `main` through commit
`a5536db9`; it has not been pushed.
Manual validation and the required review are complete. The closeout reran the
gates with Xcode 26.6 (`/Applications/Xcode.app`): Full validation passed, and
`test-sensitive` reproduced the six pre-existing readiness-test failures
already documented in `.agents/reports/phase0-audio-baseline-2026-05-25.md`;
no Plan 121 source or test failure was introduced.

Plan 122 is complete: its lifecycle boundary is merged into local `main` at
`183bee4e`, with stale-callback and reset-order remediation in `61b13e7f`.
Plan 123 is complete: its explicit post-processing request seam is merged
into local `main` at `8a5907e9`; build/test passed all 1,130 tests, with the
known six structural lint baseline violations unchanged. Plan 124 is complete:
execution provenance is persisted through Core Data 1.6, retry and incremental
paths use captured inputs, and the integrated Xcode 26.6 gate passed all 1,138
tests. The only formal gate failure is the unchanged four-violation strict-lint
baseline. Plan 125 is complete: its settings-boundary cleanup is merged into
local `main` at `49d83d6a`, with the remaining singleton reads documented by
semantic allowlist. No separate reminder mechanism is required.

Plan 126 adds proactive calendar reminders (lead notification + full-screen
overlay). It reuses `CalendarEventService` and recording/calendar-note surfaces;
see [ADR 001](../docs/adr/001-meeting-reminder-overlay.md). It is independent of
the completed architecture batch (121–125) and should run as one serial
high-risk workstream.

Plan 127 delivers Pane-inspired meeting notes (hotkey glass panel + CodeMirror
live preview). See [ADR 002](../docs/adr/002-meeting-notes-pane-ux.md). Recommended
order: **126 complete, then 127**. Slice 126-4b (`CalendarEventNotesPanelController`)
merges into Plan 127 slice 2. Plan 127 slice 0–1 can start early only in a
separate worktree with no overlapping panel files.

## Dictation VT parity batch (128–132)

VoiceInk-inspired dictation latency/reliability work (GPL inspiration only; no
source copy). Planned at `08124206` (2026-09-04).

Recommended serial order on shared capture/residency files:

`128 → 130 → 131`, with **129 parallelizable** in a separate worktree, and
**132** after the residency/warmup batch when practical.

| Plan | Intent |
|------|--------|
| 128 | Purpose-aware eager ASR warmup (fix meeting-gated / wrong-model warm) |
| 129 | Hybrid/PTT already exists as `holdOrToggle`; extract, test, clarify UX |
| 130 | Ready-gate so early incremental audio is not transcribed cold |
| 131 | Post-dictation ASR unload grace without weakening meeting residency |
| 132 | Flip `enableDictationIntelligenceMode` and unify kernel gates (no dictation Q&A) |

## VoiceInk-inspired UI batch (133–138)

This batch addresses the visual comparison with VoiceInk without copying its
source, assets, CloudKit behavior, or heavier onboarding flow. It keeps
Verbi's native macOS, localization, accessibility, and local-first
contracts.

Recommended serial order:

133 -> 134 -> 135 -> 136 -> 137 -> 138

Plan 133 establishes the shared surface-role contract and deterministic visual
evidence. Plan 134 simplifies the native Settings sidebar. Plan 135 normalizes
shared Form, ScrollView, card, group, panel, and disclosure composition. Plans
136, 137, and 138 then focus separately on transcription history, Activity, and
the floating recorder. Those final three have disjoint product surfaces and
may run in separate isolated worktrees after their dependencies are stable,
but a serial order is the lowest-coordination path.

There is intentionally no separate onboarding plan: the reference onboarding
is heavier than the target direction. There is also no generic design-system
rewrite: Verbi already has reusable tokens and owners; the highest-value
work is reducing competing layers and improving progressive disclosure.

Plan 083 remains listed above for historical continuity. Its referenced file is
not present in this checkout, so this batch does not overwrite or renumber it.

## Archives

- [2026-07-12 ledger history](archive/2026-07-12-plan-ledger-history.md)
- [2026-07-16 ledger history](archive/2026-07-16-plan-ledger-history.md)
- [Completed plan files](archive/completed/)

## Current decisions

- Keep this root ledger active-only; archive completed batches with Git history.
- Keep `AGENTS.md`, the skill descriptions, and the routing guide as the
  sources of truth for agent guidance.
- Keep exact-range technical validation fail closed; reuse only compatible PASS evidence.
- Run high-risk plans as one serial chain: preflight the worktree, toolchain,
  dependencies, and exact test selectors; implement in isolation; validate
  focused behavior; merge; review the integrated diff; remediate; run the full
  gate; then update the ledger.
- Keep `IN PROGRESS` until merge, integrated review, and validation are all
  complete. Record the exact `DEVELOPER_DIR`, commands, results, and any
  stalled reviewer or environment limitation in the plan closeout.
- Store concrete provider/model/language and text-handling values per Dictation
  Mode, then snapshot the effective mode at recording start.
- Keep Dictionary data local-only; preserve Verbi's existing literal and empty
  substitution semantics while adding a separate vocabulary model.
- Use VoiceInk beta as a behavioral benchmark only; do not copy source or adopt
  its CloudKit persistence.
- Treat the VoiceInk-inspired UI batch (133–138) as a composition and
  hierarchy effort over existing native components; do not add a parallel
  design-system namespace or reference-app assets.
- Dictation VT parity (plans 128–132) reuses existing `holdOrToggle`, residency
  coordinator, and incremental coordinator seams; prefer extend-over-create and
  keep meeting defaults (30m residency, meeting warmup gates) intact unless a
  plan explicitly changes them.
- Prefer deterministic scripts and Make gates for repeatable checks; keep model
  reasoning for ambiguity, design judgment, and user-facing decisions.
- Treat token or time savings as hypotheses until a later measurement pass
  confirms them; these plans intentionally do not require manual usage tables.
- Keep transcription provider/model/language/vocabulary selection explicit at
  the operation edge and route it through the existing adapter/client seam;
  do not reintroduce live settings reads or mutable next-call overrides.

Plan 119 is a guidance-only migration. It must wait until the global macOS
skill bundle is merged and the currently dirty 112–118 work is reconciled. It
preserves verbi/Verbi specialist skills and moves only the seven shared
macOS skill copies to project overlays.

## Swift 6.2 baseline batch

Plan 120 is the serial compiler, formatter, lint, concurrency, and agent-gate
migration. It must run only after the current worktree is reconciled. It is the
canonical verbi baseline for sibling-project equalization; source rewrites
are expected but must remain behavior-preserving and diagnostic-driven.
