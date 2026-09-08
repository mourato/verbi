# Plan 138: Simplify the recorder surface and reveal secondary controls progressively

> **Executor instructions**: Follow this brief step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the STOP conditions section occurs, stop and
> report — do not improvise. When done, update the local status row in
> plans/README.md.
>
> **Drift check (run first)**:
> git diff --stat 51b0ac63..HEAD -- Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorView/FloatingRecordingIndicatorView.swift Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorView/FloatingRecordingIndicatorRendering.swift Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorView/FloatingRecordingIndicatorControls.swift Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorView/FloatingRecordingIndicatorSuperCard.swift Packages/MeetingAssistantCore/Sources/UI/Presentation/RecordingIndicatorOverlayLayout.swift Packages/MeetingAssistantCore/Sources/UI/Presentation/FloatingRecordingIndicatorController.swift
> If any in-scope file changed since this plan was written, compare the
> Current state excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: HIGH
- **Depends on**: 133-visual-surface-contract.md
- **Category**: direction
- **Planned at**: commit 51b0ac63, 2026-09-04
- **Finding ID**: recorder-default-visual-density
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: isolated worktree → merge to local main only when the operator authorizes it; no push unless requested

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: High/Full
- **Parallelizable**: no — capture state, overlay geometry, controls, warnings, and accessibility are one interaction surface
- **Reviewer required**: yes — the indicator is always-on and can affect recording confidence, keyboard access, and panel geometry
- **Rationale**: The recorder is functionally rich but exposes meeting, notes, prompt, language, microphone, and selector controls with too much simultaneous weight. A quiet default improves glanceability without changing capture behavior.
- **Escalate when**: The change requires recording state-machine edits, shortcut changes, permissions, audio routing, persisted style migration, or a new interaction state.

## Why this matters

The floating indicator is the most frequently visible Verbi surface. Its
current pill is technically reusable across dictation, assistant, and meeting
states, but the default presentation mixes the primary recording signal with
secondary controls. VoiceInk feels lighter because the default indicator
communicates one state first and reveals configuration only when needed.

This plan changes rendering hierarchy only. It preserves the current mini
default, style persistence, recording and post-processing states, waveform/timer
semantics, meeting notes and microphone controls, prompt/language selectors,
super-card mode, and all existing action callbacks. It reuses the current
hover/focus and overlay-layout seams rather than adding a new state machine.

## Current state

The indicator already has explicit render and style branches:

- Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorView/FloatingRecordingIndicatorView.swift:11-83
  selects render state and styles classic, mini, super, or none.
- FloatingRecordingIndicatorView.swift:88-140 renders the main pill and warning
  overlays.
- FloatingRecordingIndicatorRendering.swift:98-139 owns mode helpers and
  overlay layout.
- FloatingRecordingIndicatorRendering.swift:175-211 owns the recording
  cluster.
- FloatingRecordingIndicatorRendering.swift:278-320 owns the meeting timer.
- FloatingRecordingIndicatorRendering.swift:322-390 owns mainPill; leading
  controls and prompt/language selectors are hover-aware, but the meeting
  timer, microphone, and notes controls currently remain visible in the
  main cluster even outside hover.
- FloatingRecordingIndicatorControls.swift:126-162 owns meeting microphone
  and notes controls; lines 180-234 own dictation/external selectors and
  auxiliary pills.
- FloatingRecordingIndicatorSuperCard.swift:6-77 owns the expanded super card
  with ultra-thin material, tint, stroke, radius, and footer; lines 79-141
  own footer controls and lines 143 onward own prompt/language selectors.
- RecordingIndicatorOverlayLayout.swift:4-62 resolves prompt, language, timer,
  and meeting flags by purpose; meeting currently includes prompt and timer.

Geometry and current style defaults are separate contracts:

- FloatingRecordingIndicatorController.swift:253-350 owns panel/content sizing
  and must not be made dependent on hidden control assumptions without a
  measured width check.
- AppSettingsCoreConfiguration.swift:154-173 defines indicator styles.
- Initialization.swift:435 and DefaultsReset.swift:71-74 preserve mini as the
  default. This plan does not change those defaults or persisted settings.

Existing focused tests cover the risky seams:

- RecordingIndicatorSuperConfigurationTests.swift covers persistence, default,
  and waveform behavior.
- RecordingIndicatorOverlayLayoutTests.swift covers purpose/layout flags.
- FloatingRecordingIndicatorWidthTests.swift covers width calculations.
- RecordingIndicatorRenderStateTests.swift covers render state.
- RecordingIndicatorPostProcessingWarningTests.swift covers warning overlays.

## Target behavior

After this plan lands:

- The default mini indicator has one focal signal: active recording/processing
  state, waveform or timer where applicable, and the primary stop/cancel
  affordance.
- Meeting microphone, notes, prompt, language, and selector controls remain
  reachable but appear on hover, keyboard focus, explicit expansion, or the
  existing super-card style as appropriate. They must not disappear from
  VoiceOver or keyboard navigation merely because the pointer is absent.
- Secondary controls use existing auxiliary selector/pill treatment and do not
  create another nested card or gradient surface.
- Warning, processing, paused, failed, and permission states remain visually
  distinct and actionable. Error/status contrast is never traded for
  lightness.
- classic, mini, super, and none continue to honor the existing style setting.
  super remains an intentional expanded state, not the new default.
- Panel sizing remains stable for visible states and does not clip a focused
  control or cause hover-only layout oscillation.
- Reduce Transparency, increased contrast, dynamic type, reduced motion,
  focus, and VoiceOver remain supported.

The executor may choose whether the first reveal is hover/focus or a compact
disclosure action, provided keyboard and assistive-technology users can reach
the same controls without relying on a pointer.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | git diff --stat 51b0ac63..HEAD -- Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorView.swift Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorRendering.swift Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorControls.swift Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorSuperCard.swift Packages/MeetingAssistantCore/Sources/UI/components/recording/RecordingIndicatorOverlayLayout.swift Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorController.swift | Empty, or reviewed as an explicit STOP condition |
| Recorder behavior | ./scripts/run-tests.sh --suite dev --file RecordingIndicatorOverlayLayoutTests --file FloatingRecordingIndicatorWidthTests --file RecordingIndicatorRenderStateTests --file RecordingIndicatorPostProcessingWarningTests --file RecordingIndicatorSuperConfigurationTests | Selected recorder tests pass |
| Preview declarations | make preview-check | Preview declaration coverage PASS |
| Swift lint | make lint | Exit 0 or the documented unchanged baseline |
| Technical lane | make validate-agent ARGS="--lane auto" | PASS or an exact baseline failure is recorded |

## Suggested executor toolkit

- apple-design for native macOS materials, compact controls, motion, and
  visual hierarchy.
- swiftui-expert-skill for state-driven rendering, focus, and layout
  invalidation.
- swiftui-accessibility-audit for hover/focus parity, labels, values,
  keyboard access, contrast, and reduced motion.
- swift-conventions for Swift organization and formatting.
- testing-xctest and test-hygiene for overlay, width, state, warning, and
  visible-window verification.

## Scope

**In scope** (the only files this plan should modify):

- Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorView/FloatingRecordingIndicatorView.swift
- Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorView/FloatingRecordingIndicatorRendering.swift
- Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorView/FloatingRecordingIndicatorControls.swift
- Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorView/FloatingRecordingIndicatorSuperCard.swift
- Packages/MeetingAssistantCore/Sources/UI/Presentation/RecordingIndicatorOverlayLayout.swift
- Packages/MeetingAssistantCore/Sources/UI/Presentation/FloatingRecordingIndicatorController.swift
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/RecordingIndicatorOverlayLayoutTests.swift
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/FloatingRecordingIndicatorWidthTests.swift
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/RecordingIndicatorRenderStateTests.swift
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/RecordingIndicatorPostProcessingWarningTests.swift
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/RecordingIndicatorSuperConfigurationTests.swift

**Out of scope**:

- RecordingManager, audio callbacks, permissions, shortcuts, state-machine
  transitions, transcription, post-processing, or meeting-note persistence.
- AppSettingsCoreConfiguration.swift, Initialization.swift, and
  DefaultsReset.swift; the mini default and persisted style contract stay
  unchanged.
- New overlay state models, new preferences, or a new design-system namespace.
- Settings shell, sidebar, history, Activity, onboarding, or third-party
  floating-window components.
- Copying VoiceInk source, assets, CloudKit behavior, or exact visual values.

## Git workflow

- Branch: simplify-recorder-surface
- Commit style: refactor(ui): simplify recording indicator hierarchy
- Implementation worktrees follow core/policies/worktrees.md.
- Do not push or open a PR unless the operator instructs it.

## Steps

### Step 1: Inventory state, purpose, and geometry invariants

Trace every render state through FloatingRecordingIndicatorView,
RecordingIndicatorOverlayLayout, mainPill, selectors, the super card, warning
overlays, and the controller's width/height calculation. Identify which
controls are primary status, primary action, secondary configuration, and
error recovery. Confirm mini remains the default and enumerate
dictation/assistant/meeting differences.

**Verify**: rg -n "RenderState|overlayLayout|mainPill|showsMeeting|prompt|language|microphone|notes|super|mini|warning" Packages/MeetingAssistantCore/Sources/UI/components/recording Packages/MeetingAssistantCore/Tests → every visible control has a state/geometry owner.

### Step 2: Quiet the default mini composition

Use the existing mainPill, recording cluster, and control helpers to make
primary recording state and the primary action visually dominant. Defer
meeting microphone/notes and other secondary selectors to the existing
hover/focus/expansion paths. Remove redundant nested fills, strokes, or
simultaneous pills before adding new styling.

Do not hide a live recording/processing/error state. Do not change audio or
recording callbacks. Keep the existing material and semantic status colors,
including their opaque accessibility fallbacks.

**Verify**: make preview-check && make lint → both pass after the rendering change.

### Step 3: Preserve non-pointer reachability and style variants

Ensure every deferred control can be reached through keyboard focus and
VoiceOver with an explicit label/value. Reduced motion must not leave a
control visually or semantically unavailable. Keep classic and super layouts
usable, and keep none as no-surface behavior. Do not make panel geometry
depend on a transient hover-only width without updating the existing measured
width path.

**Verify**: ./scripts/run-tests.sh --suite dev --file RecordingIndicatorOverlayLayoutTests --file FloatingRecordingIndicatorWidthTests --file RecordingIndicatorRenderStateTests --file RecordingIndicatorPostProcessingWarningTests --file RecordingIndicatorSuperConfigurationTests → all selected tests pass.

### Step 4: Inspect real state matrix

Manually inspect idle, recording, paused, post-processing, warning, failed,
dictation, assistant, and meeting states in mini/classic/super styles. Check
hover, keyboard focus, VoiceOver, click/tap targets, panel movement, Light/Dark,
increased contrast, Reduce Transparency, dynamic type, and reduced motion.
Verify that the first glance answers whether capture is active and how to stop
or recover it.

Record unavailable visible-window checks rather than claiming source-level
equivalence.

**Verify**: make preview-check → declarations pass, followed by documented manual evidence.

### Step 5: Run the final technical lane

Run the focused recorder tests, lint, and the technical lane. No localization
gate is needed unless visible labels or keys change; if they do, add both
locale entries and run localization-check.

**Verify**: make validate-agent ARGS="--lane auto" → PASS or an exact documented baseline failure.

## Test plan

- Preserve overlay-layout coverage for dictation, assistant, meeting, prompt,
  language, and timer flags.
- Preserve width coverage for compact and expanded visible-control states.
- Preserve render-state and post-processing-warning coverage.
- Preserve super-style persistence/default/waveform coverage without changing
  configuration defaults.
- Add a focused test only for a new reachability or geometry invariant; visual
  hierarchy is verified through previews and manual state inspection.
- Manual evidence must cover pointer-free keyboard/VoiceOver access and all
  relevant capture/error/appearance states.

## Done criteria

- [ ] The default mini indicator foregrounds recording/processing state and its
      primary action.
- [ ] Secondary meeting/configuration controls remain reachable without a
      pointer and are no longer visually equal to the primary state.
- [ ] Warning, failed, paused, processing, classic, super, and none behavior
      remains intact.
- [ ] The mini default and persisted style configuration are unchanged.
- [ ] Focused recorder tests pass.
- [ ] make preview-check, make lint, and make validate-agent ARGS="--lane auto"
      pass or have exact baseline failures recorded.
- [ ] Manual state and accessibility inspection is recorded.
- [ ] No files outside the in-scope list are modified.
- [ ] plans/README.md records implementation, review, integration, and main
      validation separately when this plan is executed.

## STOP conditions

Stop and report if:

- The live render-state, purpose, or geometry model differs from the excerpts
  above.
- Quieting the indicator requires changing recording/audio state transitions,
  permissions, shortcuts, or persistence.
- A secondary control cannot be reached by keyboard or assistive technology
  after pointer deferral.
- Hidden controls cause clipping, width oscillation, accidental hit-target
  changes, or ambiguity about active recording.
- A warning, processing, failed, or recovery action becomes less visible or
  less accessible.
- A style default or persisted preference would need migration.
- The command fails twice after a reasonable, changed-hypothesis fix attempt.
- Any product source outside this plan's allowlist appears necessary.

## Maintenance notes

- Keep the mini indicator as the default quiet state and the super card as the
  intentional expanded state.
- New recorder controls must declare whether they are primary state, primary
  action, secondary configuration, or recovery before entering the main pill.
- Prefer existing hover/focus/layout seams over a new overlay state machine.
