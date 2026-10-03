# Plan 147: Retire the XPC identity keys and update documentation

> **Executor instructions**: Follow step by step; run every verification; STOP
> on listed conditions; update this plan's row in `plans/README.md`.
>
> **Drift check (run first)**:
> `git diff --stat a1070bef..HEAD -- Config scripts/config Packages/MeetingAssistantCore/Sources/Common/Config Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/AppIdentityContractTests.swift README.md`

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 139 (XPC target and client must already be gone)
- **Category**: tech-debt / docs
- **Planned at**: commit `a1070bef`, 2026-10-03

## Why this matters

Plan 139 deletes the XPC service. The identity manifest still declares an XPC
bundle id, product name, and target name, the generator emits them into three
generated files, a contract test pins them, and the README describes a
sandboxed XPC target that no longer exists. The maintainer decided on
2026-10-03 to remove them. Leaving them would advertise a component that is
gone and keep a dead public constant (`AppIdentity.xpcServiceName`).

## Current state

- `Config/AppIdentity.plist:13-14` (`technical` section):
  `xpcServiceBundleIdentifier` = `com.mourato.verbi.ai-service`, `xpcProductName` = `VerbiAI`;
  `:52` (`internal` section): `xpcTargetName` = `MeetingAssistantAI`.
- `scripts/config/generate_app_identity.swift` — reads the plist and writes
  generated files (list around `:100-110`, incl.
  `Packages/MeetingAssistantCore/Sources/Common/Config/AppIdentityValues.generated.swift`,
  `Config/Branding.xcconfig`, `scripts/config/app_identity.sh`). XPC lines:
  `:57-58` (xcconfig `XPC_SERVICE_BUNDLE_ID`, `XPC_PRODUCT_NAME`), `:74`
  (Swift `xpcServiceName`), `:97-98` (shell `XPC_TARGET_NAME`, `XPC_PRODUCT_NAME`).
  `--check` mode (`:40`) verifies generated files are current; it runs in
  `make guidance-check` (`Makefile:282`).
- Generated outputs today: `Config/Branding.xcconfig:6-7`,
  `scripts/config/app_identity.sh:6-7`,
  `AppIdentityValues.generated.swift:7`.
- `Packages/MeetingAssistantCore/Sources/Common/Config/AppIdentity.swift:7`
  `public static let xpcServiceName = AppIdentityValues.xpcServiceName`.
- `Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/AppIdentityContractTests.swift:9`
  asserts `xpcServiceName`.
- `README.md:300-304`:
  > The main app must remain non-sandboxed for AppUpdater to replace its bundle:
  > `App/MeetingAssistant.entitlements` is intentionally empty. The sandboxed
  > `MeetingAssistantAI` XPC target keeps its separate entitlements and is not the
  > target that performs updates. Do not add App Sandbox to the main app without
  > replacing this updater flow with a sandbox-compatible installer.
- `.agents/reports/phase2-checkpoint-rust-staging-2026-05-25.md` mentions XPC —
  a dated historical report; leave it.

## Commands you will need

| Purpose | Command | Expected |
|---|---|---|
| Regenerate | `./scripts/config/generate_app_identity.swift` | exit 0 |
| Check | `./scripts/config/generate_app_identity.swift --check` | exit 0 |
| Guidance | `make guidance-check` | pass |
| Tests | `swift test --package-path Packages/MeetingAssistantCore --filter AppIdentityContractTests` | pass |
| Validate | `make validate` | pass |

## Scope

**In scope**: `Config/AppIdentity.plist`, `scripts/config/generate_app_identity.swift`,
the three generated files (only via regeneration), `AppIdentity.swift`,
`AppIdentityContractTests.swift`, `README.md`, and any guidance doc found by
the grep in Step 4.

**Out of scope**: other identity keys (`com.mourato.prisma`, storage dirs,
Keychain service, UserDefaults domains), historical `.agents/reports/*` and
archived plans.

## Steps

### Step 1: Confirm nothing else uses the keys
`grep -rn 'xpcServiceName\|XPC_SERVICE_BUNDLE_ID\|XPC_PRODUCT_NAME\|XPC_TARGET_NAME' --exclude-dir=.build --exclude-dir=build --exclude-dir=dist . | grep -v '^./plans/\|^./.agents/reports/'`
**Verify**: only the files listed in Current state appear. Otherwise STOP.

### Step 2: Remove keys and generator lines
Delete the three plist keys and generator lines `:57-58`, `:74`, `:97-98`.
Run the generator to rewrite outputs.
**Verify**: `--check` exit 0; `grep -n 'XPC\|xpc' Config/Branding.xcconfig scripts/config/app_identity.sh Packages/MeetingAssistantCore/Sources/Common/Config/AppIdentityValues.generated.swift` → empty; `plutil -lint Config/AppIdentity.plist` → OK.

### Step 3: Remove the Swift constant and test assertion
Delete `AppIdentity.xpcServiceName` and the test line `:9`.
**Verify**: contract tests pass; `swift build --package-path Packages/MeetingAssistantCore` exit 0.

### Step 4: Update docs
Rewrite the README paragraph to drop the XPC sentence, keeping the updater
rule:
> The main app must remain non-sandboxed for AppUpdater to replace its bundle:
> `App/MeetingAssistant.entitlements` is intentionally empty. Do not add App
> Sandbox to the main app without replacing this updater flow with a
> sandbox-compatible installer.
Also mention in README requirements/architecture (if such a section lists
components) that transcription runs in-process. Then
`grep -rni 'xpc' README.md docs AGENTS.md CONTEXT.md .agents/docs .agents/skills`
and fix every live-guidance hit.
**Verify**: that grep → empty; `make guidance-check` passes.

### Step 5: Gates
`make validate`; `make build-release` exit 0.

## Done criteria

- [ ] No `xpc` keys in `Config/AppIdentity.plist`; generator `--check` passes
- [ ] No `xpcServiceName` in Sources/Tests
- [ ] Live docs grep for `xpc` empty; `make guidance-check` passes
- [ ] `make validate` and `make build-release` pass
- [ ] `plans/README.md` row updated

## STOP conditions

- Step 1 grep finds another consumer (e.g. release, notarization, or
  installer scripts).
- `MeetingAssistant.xcodeproj` still references `XPC_*` build settings
  (means plan 139 was incomplete — report it).

## Maintenance notes

- The bundle id `com.mourato.verbi.ai-service` is now free; do not reuse it for
  an unrelated component without considering old installs' launchd caches.
