# Plan 142: Remove the unused waveform-envelope pipeline from AudioLevelMonitor

> **Executor instructions**: Follow step by step; run every verification; STOP
> on listed conditions; update this plan's row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat a1070bef..HEAD -- Packages/MeetingAssistantCore/Sources/Audio/Services/AudioLevelMonitor.swift Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/AudioLevelMonitorTests.swift`

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf / tech-debt
- **Planned at**: commit `a1070bef`, 2026-10-03

## Why this matters

On every audio meter tick while recording, `AudioLevelMonitor` computes a
48-sample "canonical envelope", appends/trims a frame buffer, and publishes
three `@Published` arrays. Nothing in the app reads them: the only consumer of
the monitor, the floating indicator, reads `audioMeter.averagePower` and
`isSilenceWarningVisible`. Each extra `@Published` assignment also fires
`objectWillChange`, re-rendering the whole indicator (see plan 143). Deleting
the pipeline removes ~150 lines and per-tick work.

## Current state

`Packages/MeetingAssistantCore/Sources/Audio/Services/AudioLevelMonitor.swift` (371 lines):
- `:17` `struct CanonicalWaveformFrame`
- `:28-36` published: `audioMeter` (KEEP), `canonicalEnvelopeLevels`,
  `instantBarLevels`, `recentAverageLevels` (all three unused), `isSilenceWarningVisible` (KEEP)
- `:56-74` `Constants` — envelope constants (`canonicalResolution`, `peakBlend`,
  `attackBlend`, `decayBlend`, `adaptiveScaleBlend`, `minimumAdaptiveScale`,
  `gateThreshold`, `gateKnee`, `centerBiasEdgeFloor`, `centerBiasExponent`,
  `symmetryBlend`, `projection*PhaseOffset`) vs silence/meter constants (KEEP:
  `silenceThresholdDb`, `silenceDurationSeconds`,
  `silenceWarningStartupWindowSeconds`, `meterMinDb`, `meterMaxDb`)
- `:76-80` private envelope state: `canonicalFrames`, `waveformClock`,
  `lastEnvelopeLevel`, `adaptiveScale`; `windowDuration` init param
- `:137-183` `ingestLevels(averageDB:peakDB:barLevelsDB:deltaTime:)` — after
  setting `audioMeter` (`:160`) it computes `blendedTargetLevel`,
  `normalizedBars`, `smoothedLevel`, appends frames,
  `trimCanonicalFrames`, `rebuildCanonicalEnvelope()`
- `:185-225` `public func displayLevels(for:)` — no callers outside tests
- private helpers `:275-360`: `blendedEnvelopeLevel`, `smoothedEnvelopeLevel`,
  `trimCanonicalFrames`, `rebuildCanonicalEnvelope`, `softGatedLevel`,
  `phasedProjection`, `resample`, `interpolatedSample`, `lerp` (KEEP
  `normalizeDecibels`, `updateSilenceWarning`)
- `resetState()` `:227-240` resets envelope fields too.

Verified consumers (at `a1070bef`):
`grep -rn 'canonicalEnvelopeLevels\|instantBarLevels\|recentAverageLevels\|displayLevels(' Packages App`
→ only `AudioLevelMonitor.swift` and `AudioLevelMonitorTests.swift`.

Tests `Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/AudioLevelMonitorTests.swift`:
envelope-only tests `testIngestLevels_BuildsCanonicalEnvelopeAndProjectedLevels`,
`testDisplayLevels_ProducesQuasiSymmetricProfile`,
`testIngestLevels_UsesFastAttackAndSlowDecay`,
`testIngestLevels_CollapsesNearSilence`; `testStopMonitoring_Resets...` asserts
on `canonicalEnvelopeLevels` at `:136`.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Focused tests | `swift test --package-path Packages/MeetingAssistantCore --filter AudioLevelMonitorTests` | pass |
| Lint | `make lint-agent FILES="Packages/MeetingAssistantCore/Sources/Audio/Services/AudioLevelMonitor.swift"` | pass |
| Validate | `make validate` | pass |

## Scope

**In scope**: `AudioLevelMonitor.swift`, `AudioLevelMonitorTests.swift`.

**Out of scope**: `AudioRecorder`/worker metering (`barPowerDBLevels`,
`setMeteringBarCount`, `waveformBarCount(for:)`) — audio-thread code, see
Maintenance notes. Keep the `barLevelsDB:` parameter of `ingestLevels`
(ignored) so `startMonitoring()` call site and the snapshot type don't change;
mark it `_ barLevelsDB` usage-free only if lint requires.

## Steps

### Step 1: Delete envelope state, API, and helpers
Remove the three arrays, `CanonicalWaveformFrame`, `displayLevels(for:)`, the
envelope constants and private state, `windowDuration` (and its init
parameter — update callers: grep `windowDuration:`), and the helpers listed.
In `ingestLevels` keep: silence update, normalization, `audioMeter =`. Update
`resetState()`.
**Verify**: `grep -n 'canonical\|Envelope\|displayLevels\|instantBar\|recentAverage' Packages/MeetingAssistantCore/Sources/Audio/Services/AudioLevelMonitor.swift` → no matches; `swift build --package-path Packages/MeetingAssistantCore` → exit 0.

### Step 2: Update tests
Delete the four envelope-only tests; in `testStopMonitoring_...` replace the
envelope assertion with `XCTAssertEqual(monitor.audioMeter, .zero)` after stop.
Keep normalization and silence tests unchanged.
**Verify**: focused test command → all pass.

### Step 3: Gates
`make lint-agent FILES=...` and `make validate`.

## Done criteria

- [ ] `grep -rn 'canonicalEnvelopeLevels\|displayLevels(' Packages App` → empty
- [ ] `AudioLevelMonitor.swift` ≤ 230 lines (`wc -l`)
- [ ] Focused tests and `make validate` pass
- [ ] `plans/README.md` row updated

## STOP conditions

- Any non-test code reads the removed members.
- Silence-warning tests fail after the change (means shared state was cut).

## Maintenance notes

- Follow-up candidate: `ingestLevels` no longer uses per-bar levels, so the
  capture worker's per-buffer bar metering (`setMeteringBarCount`,
  `barPowerDBLevels`) is dead work on the audio path. Remove it in a separate,
  audio-reviewed change.
