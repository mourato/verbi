# Plan 146: Remove per-bar audio metering from the capture path

> **Executor instructions**: Follow step by step; run every verification; STOP
> on listed conditions; update this plan's row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat a1070bef..HEAD -- Packages/MeetingAssistantCore/Sources/Audio Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/AudioRecordingWorkerMeteringTests.swift`

## Status

- **Priority**: P2
- **Effort**: S–M
- **Risk**: MED (audio capture path; high-risk surface per AGENTS.md)
- **Depends on**: 142 (envelope removed, so bar levels have no reader) and 145
  (removes `RecordingIndicatorStyle`, which `waveformBarCount(for:)` switches on).
  If 145 is not done yet, this plan may still run after 142 — see Step 3.
- **Category**: perf / tech-debt
- **Planned at**: commit `a1070bef`, 2026-10-03

## Why this matters

For every metered buffer, the capture worker splits the buffer into N bars
(9/18/80 by style) and computes a dB level per bar. Its only reader was the
waveform envelope in `AudioLevelMonitor`, which plan 142 deletes. After 142
this is pure wasted work on the audio queue, plus a `[Float]` allocation per
snapshot and a style subscription in `AudioRecorder`. The pill's waveform only
uses `averagePowerDB`/`peakPowerDB`.

## Current state

All under `Packages/MeetingAssistantCore/Sources/Audio/Services/`.
- `AudioRecordingWorker.swift`
  - `:13-23` `AdaptiveMeteringMode`, `AdaptiveMeteringConstants` (incl.
    `reducedBarCountCap = 12`; other constants drive snapshot stride — KEEP those)
  - `:44-49` `struct MeterSnapshot { averagePowerDB; peakPowerDB; barPowerDBLevels: [Float]; deltaTime }`
  - `:69` `onPowerUpdate: (@Sendable (Float, Float, [Float]) -> Void)?`
  - `:72` `private var meteringBarCount = 0`
  - `:102-120` `setMeteringBarCount(_:)` / `setMeteringBarCountIsolated`
  - `:270-283` builds snapshot with `barCount: effectiveMeteringBarCount` and
    calls `onPowerUpdate?(avg, peak, snapshot.barPowerDBLevels)`
  - `:300-307` `effectiveMeteringBarCount`
  - `:360` static helper calling `makeMeterSnapshot(from:barCount:)`
- `AudioKernels/AudioKernels.swift:40-75` — `SwiftEnergyMeterKernel.makeMeterSnapshot(from:barCount:)`
  computes RMS/peak, then `makeBarPowerDBLevels(...)` (`:73+`). Protocol
  `EnergyMeterKernel` is used via `AudioKernels/AudioKernelProvider.swift`.
- `AudioRecorder/AudioRecorder.swift`
  - `:167-172` subscription to `AppSettingsStore.shared.$recordingIndicatorStyle` → `worker.setMeteringBarCount`
  - `:182` initial `setMeteringBarCount`
  - `:470-492` `publishMeterSnapshot(averagePower:peakPower:barPowerLevels:)`
    stores `currentBarPowerLevels`, builds `MeterSnapshot`
  - `:494-505` `static func waveformBarCount(for:)` (18/9/80/0)
- `AudioRecorder/AudioRecorderOutputInterruption.swift:68,244,284` reset `currentBarPowerLevels = []`.
- `AudioLevelMonitor.swift:114` passes `barLevelsDB: snapshot.barPowerDBLevels`
  (after 142 the parameter is ignored).
- Tests: `Tests/MeetingAssistantCoreTests/AudioRecordingWorkerMeteringTests.swift`
  (`:24-29,53-55,69` assert bar levels); `RecordingIndicatorSuperConfigurationTests.swift:39`
  asserts `waveformBarCount(for: .super) == 80` (deleted by 145 if done).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Build | `swift build --package-path Packages/MeetingAssistantCore` | exit 0 |
| Tests | `swift test --package-path Packages/MeetingAssistantCore --filter 'AudioRecordingWorker\|AudioLevelMonitor\|AudioRecorder\|AudioKernel'` | pass |
| Lint | `make lint` | pass |
| Validate | `make validate` | pass (auto lane will pick full for audio) |

## Scope

**In scope**: the Audio files listed, `AudioRecorder/AudioRecorderDeviceRecovery.swift`
(amendment 3: `publishSilenceMeterSnapshot()` at ~`:159-166` builds silent bar
levels from `currentBarPowerLevels.count` only to forward them to
`publishMeterSnapshot`; it is a writer, not a reader — drop the bar array
there), `AudioRecordingWorkerMeteringTests.swift`,
`RecordingIndicatorSuperConfigurationTests.swift` (only the bar-count assertion,
if the file still exists).

**Amendment 4 — exhaustive scope (advisor grep at worktree HEAD).** These are
ALL files referencing the removed symbols; every one is in scope:
- `Packages/MeetingAssistantCore/Sources/Audio/Services/AudioKernels/AudioKernels.swift` (and `AudioKernelProvider.swift` if the protocol signature is declared there)
- `.../Audio/Services/AudioLevelMonitor.swift`
- `.../Audio/Services/AudioRecorder/{AudioRecorder,AudioRecorderDeviceRecovery,AudioRecorderOutputInterruption}.swift`
- `.../Audio/Services/AudioRecordingWorker.swift`
- Tests: `AudioRecorderOutputInterruptionTests.swift` (it sets/reads `currentBarPowerLevels` only to test the reset — delete those lines, keep the average/peak reset assertions), `AudioRecordingWorkerMeteringTests.swift`, `RecordingIndicatorSuperConfigurationTests.swift` (if still present)
Test files that only assert on the removed state are follow-through, not
"readers": edit them. STOP only for a production file NOT in this list.

**Out of scope**: RMS/peak math, adaptive stride logic, file writing,
`onProcessedBuffer`, system audio recorder, device recovery subscription
(`AudioRecorder.swift:174-179` — keep it).

## Steps

### Step 1: Shrink the snapshot
Remove `barPowerDBLevels` from `MeterSnapshot`; change
`EnergyMeterKernel.makeMeterSnapshot(from:barCount:)` to `makeMeterSnapshot(from:)`;
delete `makeBarPowerDBLevels`. `onPowerUpdate` becomes `(Float, Float)`.
**Verify**: `grep -rn 'barPowerDBLevels\|makeBarPowerDBLevels' Packages/MeetingAssistantCore/Sources` → empty.

### Step 2: Remove bar-count plumbing
Delete `meteringBarCount`, `setMeteringBarCount*`, `effectiveMeteringBarCount`,
`reducedBarCountCap`. In `AudioRecorder`, delete the style subscription
(`:167-172`), the initial call (`:182`), `currentBarPowerLevels` (and its three
resets), the `barPowerLevels:` parameter of `publishMeterSnapshot`, and
`waveformBarCount(for:)`. In `AudioLevelMonitor`, drop the `barLevelsDB:`
parameter and argument.
**Verify**: `grep -rn 'MeteringBarCount\|waveformBarCount\|BarPowerLevels\|barLevelsDB' Packages/MeetingAssistantCore/Sources` → empty; build exit 0.

### Step 3: Tests
In `AudioRecordingWorkerMeteringTests.swift`, delete bar-level assertions;
keep or add assertions that `averagePowerDB`/`peakPowerDB` are unchanged for
the same input buffers (values currently asserted elsewhere in the file).
Remove the `waveformBarCount` assertion if plan 145 has not removed that test
file yet.
**Verify**: tests command passes.

### Step 4: Gates and manual
`make lint`, `make validate`. Manual (Debug app): dictation and meeting
recording — waveform moves with voice, silence warning still fires, recording
file plays back.

## Done criteria

- [ ] Greps in Steps 1–2 empty
- [ ] Average/peak values unchanged in tests
- [ ] `make validate` passes; manual capture check recorded in commit body
- [ ] `plans/README.md` row updated

## STOP conditions

- Any reader of bar levels exists besides `AudioLevelMonitor` and the
  silence-snapshot writer in `AudioRecorderDeviceRecovery.swift` (e.g. diagnostics,
  benchmarks, Rust staging kernels).
- `EnergyMeterKernel` has another conformer outside `AudioKernels.swift`
  whose signature you cannot update in scope.
- Average/peak dB results change for the same input.

## Maintenance notes

- If a multi-bar spectrum visual returns, compute it in the UI from a
  dedicated, opt-in tap — not in the always-on capture worker.
