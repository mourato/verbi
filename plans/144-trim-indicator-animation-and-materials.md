# Plan 144: Trim the recording pill's animation loops and stacked materials

> **Executor instructions**: Follow step by step; run every verification; STOP
> on listed conditions; update this plan's row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat a1070bef..HEAD -- Packages/MeetingAssistantCore/Sources/UI/components/recording`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 143 (same files; land after it)
- **Category**: perf
- **Planned at**: commit `a1070bef`, 2026-10-03

## Why this matters

The pill lives in an `NSPanel` at `.screenSaver` level that is always on top.
Each `.ultraThinMaterial` there is a live backdrop blur recomposited whenever
anything beneath or inside changes (the waveform moves ~20×/s). The auxiliary
chips stack material + tint + stroke. Setup "bounce" runs a Foundation `Timer`
every 60 ms that hops into a `Task { @MainActor }` per tick. The recording
timer label creates a new `DateComponentsFormatter` on every call. Each is
small; together they are GPU/CPU you pay for during every recording.

## Current state

All paths under `Packages/MeetingAssistantCore/Sources/UI/components/recording/`.
- `FloatingRecordingAudioVisualizer.swift:47-48` `@State bounceIndex`,
  `@State bounceTimer: Timer?`; `:134-147`:
  ```swift
  private func startBounce() {
      bounceIndex = 0
      bounceTimer?.invalidate()
      bounceTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { _ in
          Task { @MainActor in
              bounceIndex = (bounceIndex + 1) % max(barCount, 1)
          }
      }
  }
  ```
  `updateBounceState()` starts it when `isSetup && isAnimationActive && !reduceMotion`.
- `FloatingRecordingIndicatorView/FloatingRecordingIndicatorControls.swift:213-247`
  `promptSelectionPill` / `languageSelectionPill`: `.background(.ultraThinMaterial)`
  then `.background(AppDesignSystem.Colors.recordingIndicatorAuxiliaryBackground)`
  then stroke overlay.
- `FloatingRecordingIndicatorView/FloatingRecordingIndicatorRendering.swift:348`
  and `FloatingRecordingIndicatorView/FloatingRecordingIndicatorConfirmationView.swift:36`
  also use `.ultraThinMaterial` (check what each one is: main pill body vs chip).
- `FloatingRecordingIndicatorSupport.swift:244-252` `formatRecordingDuration`
  allocates `DateComponentsFormatter()` per call (called each second by a
  `TimelineView(.periodic(from: .now, by: 1.0))` at `Rendering.swift:283`).
- `FloatingRecordingIndicatorSupport.swift:11-35` `PulsingModifier`
  (`repeatForever`) — Core Animation-driven, cheap; **keep**.
- Design rules live in `docs/ui.md`; read its overlay/material section before
  changing backgrounds.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Tests | `swift test --package-path Packages/MeetingAssistantCore --filter 'FloatingRecordingIndicator\|AudioVisualizer'` | pass |
| Lint | `make lint` | pass |
| Validate | `make validate` | pass |

## Scope

**In scope**: `FloatingRecordingAudioVisualizer.swift`,
`FloatingRecordingIndicatorControls.swift`, `FloatingRecordingIndicatorRendering.swift`,
`FloatingRecordingIndicatorConfirmationView.swift` (NOT `FloatingRecordingIndicatorSupport.swift`, see Step 3); `docs/ui.md` only if it
states a material rule this changes.

**Out of scope**: warning overlays' shadows, `PulsingModifier`, the main pill
background material if `docs/ui.md` mandates it (then only chips change),
colors/tokens in `AppDesignSystem` (reuse existing tokens; add none).

## Steps

### Step 1: Replace the bounce Timer with TimelineView
Delete `bounceTimer`, `bounceIndex`, `startBounce`, `stopBounce`,
`updateBounceState` and their `onChange`/`onDisappear` hooks. Wrap the bars in
`TimelineView(.animation(minimumInterval: 0.06, paused: !(isSetup && isAnimationActive && !reduceMotion)))`
and derive `bounceIndex = Int(context.date.timeIntervalSinceReferenceDate / 0.06) % max(barCount, 1)`.
**Verify**: `grep -n 'Timer' Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingAudioVisualizer.swift` → empty; tests pass.

### Step 2: Solid chips
In `promptSelectionPill` and `languageSelectionPill`, drop
`.background(.ultraThinMaterial)`; keep the tint background. If the tint is
too transparent to read on light wallpapers, use the main pill's background
token instead (find it in `indicatorPill`/`mainPill`). Apply the same to any
other *chip-level* material found at `Rendering.swift:348`.
**Verify**: `grep -rn 'ultraThinMaterial' Packages/MeetingAssistantCore/Sources/UI/components/recording` → at most the main pill body and confirmation pill.

### Step 3: (moved to plan 145)
Amendment 2 (2026-10-03): any edit to `FloatingRecordingIndicatorSupport.swift`
invalidates its SwiftLint baseline entry and `make lint` fails `file_length`
(file is 665 lines, limit 600). The formatter cache therefore moves to plan 145,
which shrinks that file below 400 lines. **Do not modify
`FloatingRecordingIndicatorSupport.swift` in this plan** and do not create
`RecordingDurationFormatting.swift` here.

### Step 4: Gates and manual check
`make lint`, `make validate`. Manual on light and dark wallpaper: chips
readable; setup bounce still runs; with Reduce Motion on, no bounce.

## Test plan

Existing focused tests only; the duration-formatter test moved to plan 145.

## Done criteria

- [ ] No `Timer` in `FloatingRecordingAudioVisualizer.swift`
- [ ] Chips without material
- [ ] `git diff --stat` shows no change to `FloatingRecordingIndicatorSupport.swift`
- [ ] `make validate` passes; `plans/README.md` row updated

## STOP conditions

- `docs/ui.md` or an ADR explicitly requires material on the chips.
- `TimelineView` cannot pause on macOS 15 as described (check availability).

## Maintenance notes

- Prefer `TimelineView` over `Timer` for any future indicator animation.
