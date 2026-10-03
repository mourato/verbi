# Plan 139: Remove the unused VerbiAI XPC service from the build and bundle

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat a1070bef..HEAD -- MeetingAssistant.xcodeproj/project.pbxproj MeetingAssistantAI Packages/MeetingAssistantCore/Sources/AI/Services/XPC Packages/MeetingAssistantCore/Sources/AI/Services/TranscriptionClient.swift Packages/MeetingAssistantCore/Sources/Common/Config/FeatureFlags.swift Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/MeetingAssistantAIClientTests.swift`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code; on a mismatch, STOP.

## Status

- **Priority**: P1
- **Effort**: S–M
- **Risk**: MED (hand-editing `project.pbxproj`)
- **Depends on**: none
- **Category**: perf / tech-debt
- **Planned at**: commit `a1070bef`, 2026-10-03

## Why this matters

`dist/Verbi.app` is 185 MB. 86 MB of that is
`Contents/XPCServices/VerbiAI.xpc`, an XPC service that statically links the
whole `MeetingAssistantCore` package plus FluidAudio a second time. The service
is dead: `FeatureFlags.useXPCService` is the constant `false`, so the app never
connects to it and transcription always runs in-process. Removing the target
roughly halves download and disk size, shortens Release builds (one fewer full
link of Core), and deletes a code path nobody exercises.

## Current state

- `Packages/MeetingAssistantCore/Sources/Common/Config/FeatureFlags.swift:28-43`
  — doc comment for the XPC trade-off, then
  `public static let useXPCService: Bool = false` (line 43).
- `Packages/MeetingAssistantCore/Sources/AI/Services/TranscriptionClient.swift`
  — branches on the flag:
  ```swift
  // :30-44
  private enum TranscriptionImplementation { case xpc; case local }
  private enum TranscriptionBackend { case xpc; case local; case groq(modelID: String); case elevenLabs(modelID: String) }
  private var transcriptionImplementation: TranscriptionImplementation {
      FeatureFlags.useXPCService ? .xpc : .local
  }
  ```
  Further `.xpc` branches at roughly lines 80, 97-110, 159-168, 370-372,
  393-402 (`transcribeViaXPC`), 439 (log extra `"implementation"`).
- `Packages/MeetingAssistantCore/Sources/AI/Services/XPC/` —
  `MeetingAssistantAIClient.swift`, `MeetingAssistantXPCModels.swift`,
  `MeetingAssistantXPCProtocol.swift`. Only `TranscriptionClient.swift` and the
  XPC target use them.
- `Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/MeetingAssistantAIClientTests.swift`
  — tests the dead client.
- `MeetingAssistantAI/` (repo root) — XPC target: `Sources/main.swift`,
  `Sources/MeetingAssistantAIService.swift` (122 lines total),
  `Resources/Info.plist`, `Resources/MeetingAssistantAI.entitlements`.
- `MeetingAssistant.xcodeproj/project.pbxproj` objects belonging to the XPC
  target (IDs verified at `a1070bef`):
  - `6BBB1EF6211BC44E3D1CDD0A` PBXNativeTarget `MeetingAssistantAI` (+ its entry in the project `targets = (...)` list)
  - `59205FC94196B4719F82EFC2` its XCConfigurationList; `41531CAC11F0BC523E40BDAD` (Debug), `E1D7D25E93A1519C044989E3` (Release)
  - build phases `108933264B27C8F5BA545296` (Sources), `141BF599BD5857E346F44A67` (Resources), `0F922C47DF08A480913183DE` (Frameworks), `92D1FF9191171B34E2078498` (Embed Frameworks)
  - build files `88CAABED053EF8FF59262B57` (AIService.swift), `9E5DFA937E9BEF2353A8B14E` (main.swift), `FB909604BA3CC691772CA254` (xpc in Embed XPC Services)
  - package product dependency `74E3BB1C36D19BA6FD35B4D4` (MeetingAssistantCore for the XPC target)
  - `A4D2B8E82669F299E248DA81` "Embed XPC Services" copy phase on the app target (+ its entry in the app target `buildPhases`)
  - `8FA671BA1C4ADFD27461B9F6` PBXContainerItemProxy, `AB30F35A9504B6851094A2B7` PBXTargetDependency (+ its entry in the app target `dependencies`)
  - file refs `0EAA0868CC0117903F03BE15` (xpc product), `6D9C3678314B07204259A76D` (AIService.swift), `436B4D167C66E768EB4058D4` (main.swift), `6156FF8CDBCB6116510D6194` (XPC Info.plist — confirm by path), `A1D685B4E97C7BC0C254C723` (entitlements), group `9C713B01509945677CE7046A` and its child groups.
- Identity config mentions the XPC: `Config/AppIdentity.plist:13-14,52`,
  `Config/Branding.xcconfig:6-7`, `scripts/config/app_identity.sh:6-7`,
  `scripts/config/generate_app_identity.swift:57-58,74,97-98`,
  `AppIdentity.xpcServiceName` in
  `Packages/MeetingAssistantCore/Sources/Common/Config/AppIdentityValues.generated.swift`.
  **These stay** (see Scope).

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| pbxproj syntax | `plutil -lint MeetingAssistant.xcodeproj/project.pbxproj` | `OK` |
| Release build | `make build-release` | exit 0 |
| Lint | `make lint` | exit 0 |
| Validate | `make validate` | lane passes |
| Focused tests | `swift test --package-path Packages/MeetingAssistantCore --filter TranscriptionClient` | pass |
| Bundle check | `ls "$(find ~/Library/Developer/Xcode/DerivedData .xcode-build* -path '*Release/Verbi.app' -maxdepth 6 2>/dev/null | head -1)/Contents"` | no `XPCServices` |

## Scope

**In scope**: `MeetingAssistant.xcodeproj/project.pbxproj`; delete
`MeetingAssistant.xcodeproj/xcshareddata/xcschemes/MeetingAssistantAI.xcscheme`; delete
`MeetingAssistantAI/`; delete `Sources/AI/Services/XPC/`;
`TranscriptionClient.swift`; `FeatureFlags.swift`; delete
`MeetingAssistantAIClientTests.swift`.

**Out of scope**: the identity keys (`xpcServiceBundleIdentifier`,
`xpcProductName`, `xpcTargetName`) and the generator — plan 112 froze the
technical identity contract; removing keys is a separate decision. Leave
`AppIdentity.xpcServiceName` even if now unused (if SwiftLint flags it as
unused, STOP and report). Do not touch `LocalTranscriptionClient`,
`FluidAIModelManager`, Groq/ElevenLabs backends.

## Git workflow

Isolated worktree per repo policy. Conventional Commits, e.g.
`build(xpc): drop unused VerbiAI XPC service target`. No push.

## Steps

### Step 1: Remove the `.xpc` branches from `TranscriptionClient`
Delete `TranscriptionImplementation`, the `.xpc` case of
`TranscriptionBackend`, `transcriptionImplementation`, `transcribeViaXPC`, and
every `case .xpc:` arm. Where code was `guard transcriptionImplementation == .local`,
drop that condition (local is now the only implementation). Line 439 log extra:
replace with `"implementation": "local"` or drop the key.
**Verify**: `grep -n 'xpc\|XPC' Packages/MeetingAssistantCore/Sources/AI/Services/TranscriptionClient.swift` → no matches.

### Step 2: Delete the XPC client folder, flag, and test
`git rm -r Packages/MeetingAssistantCore/Sources/AI/Services/XPC Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/MeetingAssistantAIClientTests.swift`.
Remove `useXPCService` and its doc comment from `FeatureFlags.swift`.
**Verify**: `grep -rn 'useXPCService\|MeetingAssistantAIClient\|MeetingAssistantXPC' Packages App` → no matches; `swift build --package-path Packages/MeetingAssistantCore` → exit 0.

### Step 3: Remove the XPC target from the Xcode project
Remove every object listed in Current state from `project.pbxproj`, plus the
references to them inside other objects' lists (project `targets`, app
target `buildPhases` and `dependencies`, group `children`). Then
`git rm -r MeetingAssistantAI MeetingAssistant.xcodeproj/xcshareddata/xcschemes/MeetingAssistantAI.xcscheme`.
**Verify**: `plutil -lint MeetingAssistant.xcodeproj/project.pbxproj` → OK;
`grep -c 'MeetingAssistantAI\b\|6BBB1EF6211BC44E3D1CDD0A\|A4D2B8E82669F299E248DA81' MeetingAssistant.xcodeproj/project.pbxproj` → `0`;
`xcodebuild -list -project MeetingAssistant.xcodeproj` lists no `MeetingAssistantAI` target.

### Step 4: Build and measure
`make build-release`, then confirm the built `Verbi.app/Contents` has no
`XPCServices` directory and record `du -sh` of the app before/after in the
commit body.
**Verify**: exit 0; no `XPCServices`.

### Step 5: Gates
`make lint` and `make validate`.

## Test plan

No new tests: the change deletes a dead path. Existing `TranscriptionClient`
and dictation tests must keep passing — they now cover the only path. Run
`make validate` (auto lane).

## Done criteria

- [ ] `grep -rn 'useXPCService\|MeetingAssistantAIClient\|MeetingAssistantXPC' Packages App` → empty
- [ ] `test ! -d MeetingAssistantAI` succeeds
- [ ] `plutil -lint MeetingAssistant.xcodeproj/project.pbxproj` → OK
- [ ] `make build-release` exit 0; built app has no `Contents/XPCServices`
- [ ] `make lint`, `make validate` pass
- [ ] Only in-scope files changed (`git status`)
- [ ] `plans/README.md` row updated

## STOP conditions

- `FeatureFlags.useXPCService` is no longer the constant `false`.
- Any production code outside `TranscriptionClient.swift` references the XPC client.
- Xcode project fails to open/list after edits and the cause is not obvious.
- Removing the target requires editing the identity generator to build.

## Maintenance notes

- If process isolation for models is wanted again, re-introduce it with a slim
  target that links only FluidAudio, never all of `MeetingAssistantCore`.
- Follow-up: plan 147 retires the `xpc*` identity keys and the README paragraph.
