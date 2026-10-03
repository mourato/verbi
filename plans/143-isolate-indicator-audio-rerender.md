# Plan 143: Stop re-rendering the whole recording pill on every audio tick

> **Executor instructions**: Follow step by step; run every verification; STOP
> on listed conditions; update this plan's row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat a1070bef..HEAD -- Packages/MeetingAssistantCore/Sources/Audio/Services/AudioLevelMonitor.swift Packages/MeetingAssistantCore/Sources/UI/components/recording`

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (always-visible surface; panel geometry)
- **Depends on**: 142
- **Category**: perf
- **Planned at**: commit `a1070bef`, 2026-10-03

## Why this matters

`FloatingRecordingIndicatorView` holds `@ObservedObject var audioMonitor:
AudioLevelMonitor`. `AudioLevelMonitor` is an `ObservableObject` whose
`audioMeter` changes on every meter tick (~20 Hz, `AudioRecorder`
`simpleMeterUpdateInterval = 0.05`). With `ObservableObject`, any change
invalidates every observing view, so the entire pill body — prompt/language
pickers, materials, layout math, overlays — is re-evaluated ~20×/s while
recording, only to move a few waveform bars. Only the waveform should update
at audio rate. That is the main "feels heavy" cost of the pill.

## Current state

- `Packages/MeetingAssistantCore/Sources/Audio/Services/AudioLevelMonitor.swift:24-25`:
  `@MainActor public final class AudioLevelMonitor: ObservableObject` with
  `@Published audioMeter` and `@Published isSilenceWarningVisible` (after plan 142).
  `startMonitoring()` subscribes with Combine to `audioRecorder?.$latestMeterSnapshot`.
- `.../UI/components/recording/FloatingRecordingIndicatorView/FloatingRecordingIndicatorView.swift:13-15`:
  ```swift
  @ObservedObject var audioMonitor: AudioLevelMonitor
  @ObservedObject var recordingManager: RecordingManager
  @ObservedObject var settingsStore: AppSettingsStore
  ```
  `:136` reads `audioMonitor.isSilenceWarningVisible`.
- `.../FloatingRecordingIndicatorRendering.swift:190-213` `recordingCluster(size:)`
  builds `AudioVisualizer(audioLevel: audioMonitor.audioMeter.averagePower, ...)`
  inside the parent body (`:198-208`). `:32-39` calls
  `audioMonitor.dismissSilenceWarning()`.
- `.../FloatingRecordingIndicatorSuperCard.swift:64` reads `isSilenceWarningVisible`.
- Other `AudioLevelMonitor` users: `FloatingRecordingIndicatorController.swift`
  (owns it, calls start/stop), `FloatingRecordingIndicatorViewPreview.swift`
  (6 previews), `AudioLevelMonitorTests.swift`. No `$audioMeter` publisher
  subscribers exist — verify with `grep -rn '\$audioMeter\|\$isSilenceWarningVisible\|objectWillChange' Packages App`.
- Project rule (AGENTS.md): "New SwiftUI state prefers Observation; preserve
  `ObservableObject` until an intentional migration is verified." This plan is
  that intentional migration, for this one type only.

## Approach

1. Migrate `AudioLevelMonitor` to `@Observable` (Observation tracks per
   property, so readers of `isSilenceWarningVisible` stop depending on
   `audioMeter`).
2. Move the `audioMeter` read out of the parent body into a small child view
   that receives the monitor and reads `audioMeter.averagePower` inside its own
   `body`. Only that child re-renders per tick.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build --package-path Packages/MeetingAssistantCore` | exit 0 |
| Tests | `swift test --package-path Packages/MeetingAssistantCore --filter 'AudioLevelMonitorTests\|FloatingRecordingIndicator'` | pass |
| Lint | `make lint` | pass |
| Validate | `make validate` | pass |

## Scope

**In scope**: `AudioLevelMonitor.swift`, `FloatingRecordingIndicatorView.swift`,
`FloatingRecordingIndicatorRendering.swift`, `FloatingRecordingAudioVisualizer.swift`,
`FloatingRecordingIndicatorSuperCard.swift` (only if it needs the new child),
`FloatingRecordingIndicatorViewPreview.swift` (only if signatures change).

**Out of scope**: `recordingManager`/`settingsStore` observation (separate
types, separate migration); `FloatingRecordingIndicatorController` panel
sizing; `AudioRecorder`.

## Steps

### Step 1: Migrate the monitor to Observation
Replace `ObservableObject` with `@Observable` (import `Observation`), drop
`@Published`, keep `public private(set)`. Mark non-UI private state
(`meterSubscription`, `audioRecorder`, counters) `@ObservationIgnored`. The
Combine subscription to `AudioRecorder.$latestMeterSnapshot` stays.
In the view, change `@ObservedObject var audioMonitor` to `let audioMonitor`
(or `var` if bindings are needed — they are not today).
**Verify**: build exit 0; `AudioLevelMonitorTests` pass.

### Step 2: Extract the live waveform child
Create in `FloatingRecordingAudioVisualizer.swift`:
```swift
struct LiveAudioVisualizer: View {
    let monitor: AudioLevelMonitor
    let isAnimationActive: Bool
    let isSetup: Bool
    let metrics: RecordingWaveMetrics
    var body: some View {
        AudioVisualizer(
            audioLevel: monitor.audioMeter.averagePower,
            isAnimationActive: isAnimationActive,
            isSetup: isSetup,
            barCount: metrics.barCount, maxHeight: metrics.height,
            barWidth: metrics.barWidth, barSpacing: metrics.barSpacing,
            barCornerRadius: metrics.barCornerRadius,
            minHeight: AppDesignSystem.Layout.recordingIndicatorWaveformMinHeight
        )
    }
}
```
(Use the real metrics type returned by
`FloatingRecordingIndicatorViewUtilities.waveformMetrics(for:)`; confirm its name.)
Replace the inline `AudioVisualizer(...)` in `recordingCluster(size:)` with
`LiveAudioVisualizer(monitor: audioMonitor, ...)`.
**Verify**: `grep -n 'audioMeter' Packages/MeetingAssistantCore/Sources/UI/components/recording -r` → only inside `LiveAudioVisualizer`.

### Step 3: Prove the re-render scope
Temporarily add `let _ = Self._printChanges()` in `FloatingRecordingIndicatorView.body`,
run the Debug app (`make build && make run` or `make build-and-run`), record 5 s
of dictation, check the console: the parent must not print per tick. Remove the
debug line before committing.
**Verify**: `grep -rn '_printChanges' Packages` → empty.

### Step 4: Gates
`make lint`, `make validate`. Manual: classic, mini, super styles still animate
the waveform; silence warning still appears after ~4 s of silence within the
first 10 s and dismisses.

## Test plan

Add one test in `AudioLevelMonitorTests.swift` using
`withObservationTracking`: read only `isSilenceWarningVisible`, call
`ingestLevels(averageDB: -20, peakDB: -10)` once, assert the onChange closure
did **not** fire; then read `audioMeter`, ingest again, assert it **did** fire.
Pattern: existing tests in the same file (`@MainActor final class ...: XCTestCase`).

## Done criteria

- [ ] `grep -n 'ObservableObject\|@Published' Packages/MeetingAssistantCore/Sources/Audio/Services/AudioLevelMonitor.swift` → empty
- [ ] `audioMeter` read only in `LiveAudioVisualizer`
- [ ] New observation-scope test passes; `make validate` passes
- [ ] `plans/README.md` row updated

## STOP conditions

- Something subscribes to `objectWillChange` or `$audioMeter` of the monitor.
- Swift 6 strict-concurrency errors from `@Observable` + `@MainActor` that
  need `nonisolated`/`Sendable` changes beyond this file.
- Panel size starts jittering (NSPanel constraint loops) — report.

## Maintenance notes

- New audio-rate data must be read only inside small leaf views.
- `RecordingManager`/`AppSettingsStore` still invalidate the whole pill on any
  published change; migrating them is larger and separate.
