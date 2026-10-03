# Plan 141: Strip the Release executable and keep the dSYM beside the release artifacts

> **Executor instructions**: Follow step by step; run every verification; STOP
> on listed conditions; update this plan's row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat a1070bef..HEAD -- MeetingAssistant.xcodeproj/project.pbxproj scripts/build-release.sh`

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW–MED (crash-log readability)
- **Depends on**: 140 (same pbxproj config block; run after it)
- **Category**: perf / dx
- **Planned at**: commit `a1070bef`, 2026-10-03

## Why this matters

The Release executable is 97 MB; about 30 MB per architecture is
`__LINKEDIT`, and `nm` lists ~331k symbols — it is not stripped. Release is
produced by `xcodebuild ... -action build` (`scripts/run-build.sh`), and Xcode
only strips installed products during `install`/`archive`
(`DEPLOYMENT_POSTPROCESSING`). The dSYM is already generated
(`DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym"`), so symbols can live there
instead of in what users download.

## Current state

- Project-level Release config `F17EC149515900FB817B6C14` in
  `MeetingAssistant.xcodeproj/project.pbxproj`: `COPY_PHASE_STRIP = NO;
  DEAD_CODE_STRIPPING = YES; DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";` —
  no `STRIP_INSTALLED_PRODUCT`, `DEPLOYMENT_POSTPROCESSING`, or `STRIP_STYLE`.
- `scripts/build-release.sh:64-96`: builds via `run-build.sh --configuration
  Release`, copies `${DERIVED_DATA}/Build/Products/Release/${APP_PRODUCT_NAME}.app`
  to `dist/`, `codesign --force --deep ...`, then `ditto` zips
  `dist/${APP_PRODUCT_NAME}-${APP_VERSION}.zip`.
- `Packages/MeetingAssistantCore/Sources/Infrastructure/Infrastructure/CrashReporter.swift:46`
  writes `exception.callStackSymbols` into crash logs. After stripping, local
  frames show as addresses; symbolication then needs the dSYM. That is why the
  dSYM must be kept.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Release dist | `./scripts/build-release.sh --no-interactive` | exit 0 |
| Size | `du -sh dist/Verbi.app` | much smaller than before |
| Symbols | `nm dist/Verbi.app/Contents/MacOS/Verbi \| wc -l` | ≪ 331k |
| dSYM UUID match | `dwarfdump --uuid dist/Verbi.app/Contents/MacOS/Verbi dist/Verbi-*.app.dSYM` | same UUIDs |
| Validate | `make validate` | pass |

## Scope

**In scope**: project-level Release config in `project.pbxproj`;
`scripts/build-release.sh`.

**Out of scope**: Debug config (keep symbols for development), `run-build.sh`,
signing identity logic, DMG script.

## Steps

### Step 1: Enable stripping for Release
In `F17EC149515900FB817B6C14` add `DEPLOYMENT_POSTPROCESSING = YES;`,
`STRIP_INSTALLED_PRODUCT = YES;`, `STRIP_STYLE = all;`, and
`STRIP_SWIFT_SYMBOLS = YES;`.
**Verify**: `plutil -lint` OK; `./scripts/build-release.sh --no-interactive`
exit 0; `nm dist/Verbi.app/Contents/MacOS/Verbi | wc -l` drops by >90%.

### Step 2: Preserve the dSYM
In `scripts/build-release.sh`, after the copy step, copy
`${BUILD_DIR}/${APP_PRODUCT_NAME}.app.dSYM` to
`${DIST_DIR}/${APP_PRODUCT_NAME}-${APP_VERSION}.app.dSYM` (read `APP_VERSION`
first or move the existing `APP_VERSION=` line earlier). Fail loudly if the
dSYM is missing. Do not include it in the update zip.
**Verify**: dSYM exists in `dist/`; `dwarfdump --uuid` UUIDs match the binary;
`unzip -l dist/Verbi-*.zip | grep -c dSYM` → `0`.

### Step 3: Smoke
`open dist/Verbi.app`; start/stop one dictation; quit.
`codesign --verify --deep --strict dist/Verbi.app` → exit 0.

### Step 4: Gates
`make validate`.

## Test plan

No unit tests (build output). Evidence = the numbers above in the commit body.

## Done criteria

- [ ] Stripped binary (`nm | wc -l` reduced >90%)
- [ ] `dist/Verbi-<version>.app.dSYM` present, UUID-matched, not in zip
- [ ] `codesign --verify --deep --strict` passes
- [ ] `make validate` passes; `plans/README.md` row updated

## STOP conditions

- Stripping breaks launch (e.g. missing ObjC/Swift runtime symbols) — report
  the crash; try `STRIP_STYLE = non-global` once, then STOP.
- No dSYM is produced for the Release build.

## Maintenance notes

- Keep each released dSYM (attach to the release) — needed to read crash logs.
- If release moves to `xcodebuild archive`, these settings remain valid.
