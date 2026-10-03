# Plan 140: Ship Verbi as an arm64-only (Apple silicon) app

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving on. If a
> STOP condition occurs, stop and report. When done, update this plan's row in
> `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat a1070bef..HEAD -- MeetingAssistant.xcodeproj/project.pbxproj App/Info.plist README.md docs/ui.md`

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (product decision already made by the maintainer)
- **Depends on**: 139 (both edit `project.pbxproj`; run sequentially)
- **Category**: perf / migration
- **Planned at**: commit `a1070bef`, 2026-10-03

## Why this matters

The maintainer decided on 2026-10-03 to drop Intel support. Today the Release
binary is universal (`lipo -archs dist/Verbi.app/Contents/MacOS/Verbi` →
`x86_64 arm64`), so every byte of code and symbols ships twice. The local ASR
stack (FluidAudio/Parakeet) targets the Apple Neural Engine anyway. Building
arm64-only halves the main executable and speeds up Release builds.

## Current state

- `MeetingAssistant.xcodeproj/project.pbxproj` sets no `ARCHS` anywhere, so
  Release uses the default `ARCHS_STANDARD` (universal). Debug project-level
  config has `ONLY_ACTIVE_ARCH = YES`.
- Project-level build configurations: Release `F17EC149515900FB817B6C14`
  (contains `COPY_PHASE_STRIP = NO; DEAD_CODE_STRIPPING = YES;
  DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";`) and the matching project-level
  Debug config (the one with `ONLY_ACTIVE_ARCH = YES`).
- App target configs use `Config/Branding.xcconfig` as base. **That file is
  generated** by `scripts/config/generate_app_identity.swift` — do not put
  settings there.
- `MACOSX_DEPLOYMENT_TARGET = 15.0` stays as is.
- `App/Info.plist` — check for `LSArchitecturePriority` /
  `LSRequiresNativeExecution` (none expected).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| pbxproj syntax | `plutil -lint MeetingAssistant.xcodeproj/project.pbxproj` | OK |
| Release build | `make build-release` | exit 0 |
| Arch check | `lipo -archs <built>/Verbi.app/Contents/MacOS/Verbi` | `arm64` |
| Validate | `make validate` | pass |

## Scope

**In scope**: project-level Debug and Release build configurations in
`project.pbxproj`; one line in `README.md` requirements (create a
"Requirements" bullet if none: "Apple silicon Mac (arm64), macOS 15+").

**Out of scope**: `Config/Branding.xcconfig` and the identity generator;
`Package.swift` (SwiftPM builds for the host); test scripts
(`scripts/run-tests-xcode.sh:197` arch probe stays).

## Steps

### Step 1: Set arm64 at project level
In both project-level configs (`F17EC149515900FB817B6C14` Release and the
project-level Debug), add `ARCHS = arm64;` (keep keys alphabetically placed
like neighbours).
**Verify**: `plutil -lint ...` → OK; `grep -c 'ARCHS = arm64;' MeetingAssistant.xcodeproj/project.pbxproj` → `2`.

### Step 2: Build and confirm
`make build-release`; locate the built app under the derived-data path printed
by the build log (`/tmp/ma-build-release.log`).
**Verify**: `lipo -archs .../Verbi.app/Contents/MacOS/Verbi` → `arm64` only.
Record before/after `du -sh` in the commit body.

### Step 3: Document requirement
Add the Apple silicon requirement to `README.md`.
**Verify**: `grep -n 'Apple silicon' README.md` → one match.

### Step 4: Gates
`make validate`.

## Test plan

No unit tests — build setting. Manual: launch the Release build on an Apple
silicon Mac, start and stop one dictation.

## Done criteria

- [ ] `lipo -archs` on built executable prints exactly `arm64`
- [ ] `plutil -lint` OK; `make validate` passes
- [ ] README states Apple silicon requirement
- [ ] `plans/README.md` row updated

## STOP conditions

- Any target overrides `ARCHS`/`VALID_ARCHS` in a way that keeps x86_64.
- The updater (`AppUpdater`) feed or release notes encode per-arch assets —
  report so the maintainer can decide how Intel users are told.

## Maintenance notes

- Existing Intel installs will receive an update they cannot run. If the
  updater supports a minimum-hardware gate, the maintainer may want to stop
  offering updates to x86_64 clients; deliberately not done here.
