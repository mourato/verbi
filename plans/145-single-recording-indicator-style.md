# Plan 145: Collapse the recording indicator to one style with progressive expansion

> **Executor instructions**: Follow step by step; run every verification; STOP
> on listed conditions; update this plan's row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat a1070bef..HEAD -- Packages/MeetingAssistantCore/Sources/UI/components/recording Packages/MeetingAssistantCore/Sources/UI/Presentation Packages/MeetingAssistantCore/Sources/Infrastructure/Models Packages/MeetingAssistantCore/Sources/Audio/Services/AudioRecorder/AudioRecorder.swift Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/GeneralSettingsTab.swift Packages/MeetingAssistantCore/Sources/UI/ViewModels/GeneralSettingsViewModel.swift App/AppDelegate/AppDelegateLifecycle.swift`

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH (most visible surface; removes a user preference)
- **Depends on**: 138 (merged), 143, 144
- **Category**: direction / tech-debt
- **Planned at**: commit `a1070bef`, 2026-10-03

## Why this matters

The indicator has three visual personalities — `classic`, `mini`, `super` —
plus `none`, each with its own layout math, width budgets, waveform bar count
(18 / 9 / 80) and tests. That is ~3.3k lines for one overlay, and
`FloatingRecordingIndicatorSupport.swift` (665 lines) exceeds the project's
600-line guideline. Three styles ask the user to configure something that
should just be right, and make the app feel like it has more knobs than
features. Target: **one** pill — the current `mini` at rest — which reveals
secondary controls on hover/focus (the progressive disclosure plan 138 already
built). `none` is redundant with the existing `recordingIndicatorEnabled` toggle.

## Current state

- `Packages/MeetingAssistantCore/Sources/Infrastructure/Models/AppSettingsCoreConfiguration.swift:155-159`:
  `public enum RecordingIndicatorStyle: String, CaseIterable, Codable, Sendable { case classic, mini, super, none }` + `displayName`.
- Persistence: `AppSettingsStore/AppSettings.swift:754-760` (`recordingIndicatorEnabled`,
  `recordingIndicatorStyle` → UserDefaults `Keys.recordingIndicatorStyle`);
  `AppSettingsStore/Initialization.swift:420,440` decodes with
  `RecordingIndicatorStyle(rawValue:) ?? .mini` — so unknown raw values already
  fall back to `.mini`; `DefaultsReset.swift:71-72` defaults `true` / `.mini`.
- Settings UI: `UI/pages/settings/tabs/GeneralSettingsTab.swift:276-296` —
  enabled switch, then style `Picker` over `allCases`, then position picker.
  `UI/ViewModels/GeneralSettingsViewModel.swift:139-141,282`.
- Rendering: `FloatingRecordingIndicatorView.swift:59-86` switches on style
  for confirmation and recording (`indicatorPill(size: .classic/.mini)`,
  `superIndicatorCard`); `IndicatorSize { classic, mini, super }` at `:90-94`.
  Style-specific code: `FloatingRecordingIndicatorSuperCard.swift` (336 lines),
  `FloatingRecordingIndicatorSupport.swift` per-size switches (`:207-242` etc.,
  `super*` helpers `:478-600`), `FloatingRecordingIndicatorWaveformMetrics.swift`,
  `FloatingRecordingIndicatorControls.swift:193-194` (`usesInlineDictationSelectors`).
- Panel: `UI/Presentation/FloatingRecordingIndicatorController.swift:198,252,290,318,325,482,557`
  read the style (`!= .none`, size per style).
- Audio: `Audio/Services/AudioRecorder/AudioRecorder.swift:167-182,494-505`
  `waveformBarCount(for:)` per style and a subscription to style changes.
- `App/AppDelegate/AppDelegateLifecycle.swift:196-202` prewarms only for
  `.mini` ("Classic style has a known NSPanel constraint-loop instability");
  `:427` checks `!= .none`.
- Tests: `FloatingRecordingIndicatorWidthTests.swift`,
  `RecordingIndicatorSuperConfigurationTests.swift`,
  `AssistantIndicatorActionWiringTests.swift`.
- Strings: 9 `recording_indicator.style.*` / `recording_indicator.super.*` keys
  in `Packages/MeetingAssistantCore/Sources/Common/Resources/{en,pt}.lproj/Localizable.strings`.
  Project rule: remove orphaned keys when text is deleted.
- Read `docs/ui.md` (recording indicator section) and plan
  `plans/138-simplify-recorder-surface.md` before starting.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build --package-path Packages/MeetingAssistantCore` | exit 0 |
| Tests | `swift test --package-path Packages/MeetingAssistantCore --filter 'RecordingIndicator\|FloatingRecording\|AssistantIndicator\|AppSettings'` | pass |
| Localization | `make localization-check` | pass |
| Lint | `make lint` | pass |
| Validate | `make validate` | pass |

## Scope

**In scope**: files listed in Current state, new `RecordingDurationFormatting.swift` (Step 3b),
`FloatingRecordingIndicatorView/FloatingRecordingIndicatorViewPreview.swift` (amendment 3: its six
`#Preview`s pass `style: .classic/.super`; drop the `style:` argument and dedupe
previews to one per render mode), `docs/ui.md` (update the
indicator rule), the two `Localizable.strings`.

**Out of scope**: recording state machine, shortcuts, position setting,
warning overlays, meeting-reminder overlay, `recordingIndicatorEnabled`
semantics.

## Steps

### Step 1: Parity inventory (no code changes)
List every action available in `super` and `classic` (stop, cancel, meeting
notes, microphone, prompt picker, language picker, timer, confirmation cancel)
and confirm each is reachable in `mini` (at rest or on hover/focus/keyboard).
Write the table into the commit body of step 2.
**Verify**: every row has a `mini` path. If any does not → STOP (see below).

### Step 2: Migrate persisted `none` and remove the enum
Remove `RecordingIndicatorStyle` entirely, plus `recordingIndicatorStyle` from
the store, view model, settings UI, defaults reset, and `Keys` (keep the key
string only for migration). In `Initialization.swift`, add one-time
migration: if the stored raw value is `"none"`, set
`recordingIndicatorEnabled = false`; then remove the key.
**Verify**: `grep -rn 'RecordingIndicatorStyle\|recordingIndicatorStyle' Packages App | grep -v 'Keys.swift\|Initialization.swift'` → empty; build exit 0.

### Step 3: Single rendering path
`FloatingRecordingIndicatorView.body`: confirmation → `confirmationPill(size: .mini)`;
starting/recording/processing → `indicatorPill(size: .mini)`. Delete
`IndicatorSize` (inline mini values) or reduce it to one case only if removal
explodes the diff — prefer removal. Delete `FloatingRecordingIndicatorSuperCard.swift`,
the `classic`/`super` branches and helpers in `Support`, `WaveformMetrics`,
`Controls` (`usesInlineDictationSelectors` collapses to `renderState.kind == .dictation`).
Controller: size from the single layout; drop style subscriptions.
`AudioRecorder`: `waveformBarCount` becomes a constant `9`; drop the style
subscription. AppDelegate: prewarm whenever enabled; drop the style check.
**Verify**: build exit 0; `wc -l Packages/MeetingAssistantCore/Sources/UI/components/recording/FloatingRecordingIndicatorSupport.swift` < 400.

### Step 3b: Cache the duration formatter (moved from plan 144)
Move `formatRecordingDuration(startTime:at:)` from
`FloatingRecordingIndicatorSupport.swift` into new
`Packages/MeetingAssistantCore/Sources/UI/components/recording/RecordingDurationFormatting.swift`
(`enum RecordingDurationFormatting`) with two cached `static let`
`DateComponentsFormatter`s (`[.minute, .second]` and `[.hour, .minute, .second]`,
`zeroFormattingBehavior = .pad`), chosen by `duration >= 3600`; keep the
`"00:00"` fallback. Update callers. Add a test: `0s → "00:00"`, `65s → "01:05"`,
and for 3661 s assert the output the pre-change code produced (capture it first).
**Verify**: `wc -l FloatingRecordingIndicatorSupport.swift` < 400; `make lint` passes.

### Step 4: Tests and strings
Delete `RecordingIndicatorSuperConfigurationTests.swift`; trim width tests to
mini. Add a migration test (stored `"none"` → enabled false; `"super"` →
enabled unchanged). Remove orphaned strings in both locales.
**Verify**: tests command passes; `make localization-check` passes.

### Step 5: Docs and gates
Update `docs/ui.md` indicator rule to "one style; secondary controls revealed
on hover/focus". `make lint`, `make validate`. Manual: dictation, meeting,
auto-meeting confirmation, processing, error, silence warning, keyboard-only
control reveal, VoiceOver labels.

## Done criteria

- [ ] No `RecordingIndicatorStyle` type; no style picker in Settings
- [ ] `FloatingRecordingIndicatorSuperCard.swift` deleted
- [ ] Migration test passes; `make localization-check`, `make validate` pass
- [ ] `docs/ui.md` updated; `plans/README.md` row updated

## STOP conditions

- Step 1 finds an action only reachable in `super` or `classic` — report the
  gap; the maintainer decides whether mini gains it first.
- Removing `classic`/`super` changes `NSPanel` sizing such that the
  constraint-loop warning reappears.
- Meeting flow depends on the super card layout in a way not described here.

## Maintenance notes

- Any new indicator control must go behind the hover/focus reveal, not a style.
- Users who chose `super` silently land on `mini`; mention in release notes.
