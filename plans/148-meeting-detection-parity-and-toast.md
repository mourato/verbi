# Plan 148: Meeting detection parity — app-level signals, one policy, and a non-blocking detection toast

**Status:** DONE (`d8df5148`, `63aee331`, `baefd6f1`, `275465e7`, `56f71f8c`, `72482abd`, `971379d4`, `7e0260d3`; manual gates pending; final review waived by user)
**Priority:** P1
**Effort:** L
**Depends on:** 126 (DONE — reminder scheduler, overlay, notification surface reused as-is)
**ADR:** `docs/adr/006-meeting-detection-policy-and-toast.md` (authored in Slice B)
**Risk:** High (always-on CoreAudio property listeners; a new persistent non-activating panel; Accessibility-dependent end detection; a UserDefaults policy migration that touches existing users)

## Objective

Close the *detection-signal* gap against superwhisper 3.0.0 while keeping Verbi's
superior calendar, scheduling, and overlay behavior:

1. Know **which** application owns the microphone, not merely that some app uses it.
2. React to call start/end as **events**, with the existing 10 s poll demoted to a safety net.
3. Collapse the three fragmented detection knobs into one `meetingDetectionMode`
   (`off` / `notify` / `auto`), with the calendar treated as a *source*, not a policy.
4. Present detection in a **non-blocking toast** instead of the fullscreen overlay,
   following the reference visual captured from the feature presentation.

## Non-goals (v1)

- Replacing or restyling the Plan 126 fullscreen calendar overlay (it stays exactly
  as shipped; it is the right surface for "your event is starting").
- System-audio capture via ScreenCaptureKit, `AudioHardwareCreateProcessTap`, or
  aggregate devices. The capture pipeline is untouched by this plan.
- Rebuilding `MeetingReminderScheduler` (timers, watchdog, wake, catch-up) — reused.
- superwhisper onboarding/demo/wordmark surfaces (`MeetingsOnboardingDemo`,
  `MeetingsWordmark`).
- Reading dialog content or transcripts out of other apps through AX. The AX use
  here is limited to call-control presence.
- Retiring the legacy `autoStartRecording` / `meetingRemindersEnabled` keys
  (migrated and written once, deleted in a later cleanup plan).
- Any change to transcription, post-processing, or summary prompts.

## Parity reference (read-only evidence)

Target: installed superwhisper 3.0.0, bundle `com.superduper.superwhisper`,
notarized universal app; thin arm64 slice sha256
`1c0397d27153a321857370423af56a6edb8371a7440d73c90078627d25ab7f17`.

| Observation | Evidence | Consequence for Verbi |
|---|---|---|
| Mic ownership is a first-class signal | log strings `took the mic -- arming`, `took the mic mid-session -- turning system audio on` | Slice A: resolve the owning bundle identifier |
| CoreAudio process enumeration | process-list / per-process running-input reads; domain `com.superwhisper.meetingPresence` | Slice A: `kAudioHardwarePropertyProcessObjectList` + `kAudioProcessPropertyIsRunningInput` |
| Call-control inspection with an explicit inconclusive state | `no call controls`, `confirmed call end`, `accessibility unavailable or inconclusive` | Slice D: three-valued result, never a hard dependency |
| Non-blocking toast family | `MeetingToastModel`, `MeetingToastWindowController`, `MeetingToastSurface`, `MeetingToastMaterialView`, `MeetingToastBlendingModeKey`, `MeetingToastSplitButton`, `MeetingToastRecordActions`, `MeetingToastCloseButton`, `MeetingDetectedToast`, `MeetingStartedToast`, `MeetingScheduledToast`, `MeetingEndedToast`, `MeetingEndedCountdown`, `InstalledAppIcon` | Slice C: panel host + view family |
| One detection policy | single `meetingDetectionMode` key (this machine: `prompt`) | Slice B: `off` / `notify` / `auto` |
| Calendar nudge uses its own lead | `calendarNudgeLeadSeconds`, `calendarSignalEnabled`, `nudgedEventIDs` | Keep Verbi's `meetingReminderLeadMinutes` + eligibility rules |

**Reference still** (user-supplied frame from the feature presentation, state
`detected`): app icon ≈ 55% of toast height inside a dark rounded-square
container; corner radius ≈ 30% of height (rounded, *not* a capsule); ghost split
button with a 1 pt border and a chevron section; title "Meeting detected";
**subtitle is the detected app name, not the event title**; no close button in
that state.

**Deliberate divergences to preserve:** Verbi's calendar eligibility/ignore
rules, `MeetingReminderScheduler` watchdog + wake + catch-up, calendar context
block in the summary prompt, and overlay snooze/notes/join actions.

## Reuse → extend → create

| Layer | Reuse | Extend | Create |
|-------|-------|--------|--------|
| CoreAudio | `AudioDeviceManager` selector-list + `AudioObjectAddPropertyListenerBlock` pattern | Process-list selector, per-process running-input listener | `CoreAudioMeetingProcessProvider` |
| Media activity | `MeetingMediaActivity`, `MeetingMediaActivityProviding`, `SystemMeetingMediaActivityProvider` | Owner attribution alongside `isActive` | `MeetingDetectionSignals` |
| Detection loop | `MeetingDetector` (timer, `@Published` state, `NSWorkspace` notifications) | Signal-driven `checkForMeetings` trigger; keep 10 s poll as fallback | — |
| Accessibility | `AccessibilityPermissionService`, `AXTextContextProvider` messaging-timeout pattern, `PermissionViewModel` | Call-control probe | `AccessibilityCallControlProvider` |
| Toast host | `FloatingRecordingIndicatorController`, `ShortcutLayerFeedbackController` (`.borderless, .nonactivatingPanel`) | — | `MeetingDetectionToastController` |
| Toast UI | `VisualEffectView`, `AppDesignSystem`, `AppIconView` | Split-button style | `MeetingDetectionToastView` + subviews |
| Auto-record | `RecordingManagerAutomaticMeetingRecording` (confirmation, stop grace) | Mode gating, countdown cancel | — |
| Settings | `MeetingSettingsRemindersSection`, `AppSettingsStore` keys, `resetToDefaults` | Mode picker replaces the master toggle | — |

## Architecture

```
NSWorkspace notifications ─┐
CoreAudio process listener ─┼─► MeetingDetectionSignals ──► MeetingDetector
10 s poll (safety net) ─────┘        │                          │
                                     │                          ▼
                                     │              detectedContext (unchanged shape)
                                     │                          │
                    ┌────────────────┴──────────────┐           │
                    ▼                               ▼           ▼
      DetectionToastController            AutomaticMeetingRecording
      (NSPanel, non-activating)           (mode == .auto only)
                    │                               │
                    │                     end ladder ──► AX call controls
                    ▼                               │      + 30 s media grace
        MeetingDetectionToastView                   ▼
        detected / recording / ended          stopRecording()
                    │
                    ▼
        MeetingReminderOverlayController  ◄── unchanged, calendar-driven only
```

### New types (target locations)

| Type | Module path |
|------|-------------|
| `MeetingDetectionSignals` (Domain value type) | `Domain/Models/` |
| `MeetingAudioProcessProviding` + `CoreAudioMeetingProcessProvider` | `Infrastructure/Services/` |
| `MeetingDetectionMode` | `Infrastructure/Models/AppSettingsStore/` |
| `MeetingDetectionToastController` | `UI/Presentation/` |
| `MeetingDetectionToastView` (+ state subviews) | `UI/components/meeting-detection-toast/` |
| `CallControlSignalProviding` + `AccessibilityCallControlProvider` | `Infrastructure/Services/` |
| Settings keys + migration | `Infrastructure/Models/AppSettingsStore/` |

## Slice A — App-level audio ownership signals (M)

- `MeetingDetectionSignals`:

  ```swift
  public struct MeetingDetectionSignals: Equatable, Sendable {
      public let microphoneOwnerBundleIdentifier: String?
      public let microphoneOwnerDisplayName: String?
      public let attribution: Attribution   // .resolved / .unattributed / .unavailable
      public let activeCallBundleIdentifiers: [String]
  }
  ```

- `CoreAudioMeetingProcessProvider` reads the process object list and, per
  process, the running-input flag and bundle identifier. Follow the existing
  `AudioDeviceManager` selector-table and listener-block pattern; do not
  introduce a second CoreAudio abstraction.
- Event-driven: property listener on the process object list plus per-process
  running-input changes, feeding `MeetingDetector.checkForMeetings`. Apply a
  **1.5 s edge debounce** so a mic handoff between apps does not double-fire.
- `MeetingDetector` keeps its 10 s timer as a safety net in this slice. Removing
  the poll is explicitly out of scope.
- **Degraded mode is a first-class case.** When the microphone is in use but the
  process list resolves no owner, `attribution == .unattributed`: the toast and
  auto-record must still work through the existing context + media gate. This is
  a known macOS 26 behavior (reported externally by a third-party superwhisper
  integration project whose recorder keeps the running-input bit set with an
  empty owner list), and it is not evidence about superwhisper's internals. It is
  covered by a dedicated test.
- `MeetingMediaActivity.isActive` semantics must not change; owner information is
  additive. Existing `AutomaticMeetingRecordingConfirmationPolicyTests` keep passing.

**Gate:** `make lint`; new unit tests with a fake provider — owner resolved,
owner change with debounce, `.unattributed`, `.unavailable`, no double-fire.

## Slice B — One detection policy (M)

- `MeetingDetectionMode: String { case off, notify, auto }`, persisted as
  `meetingDetectionMode`.
- Behavior:

  | Mode | Detection monitoring | Toast | Calendar reminders | Auto-record |
  |---|---|---|---|---|
  | `off` | no | no | no | no |
  | `notify` | yes | yes | yes | no |
  | `auto` | yes | yes | yes | yes |

- One-time migration, guarded by a `meetingDetectionModeMigrated` flag, reading
  the legacy keys and writing `meetingDetectionMode`:
  - `autoStartRecording && isMeetingTranscriptionEnabled` → `auto`
  - else `meetingRemindersEnabled` → `notify`
  - else `off`
  - Legacy keys are left in place (retired by a later cleanup plan).
- Presentation settings stay separate and keep driving only presentation:
  `meetingReminderLeadMinutes`, `meetingReminderOverlayLeadSeconds`,
  `meetingReminderAlertSoundEnabled`, `meetingReminderMirrorAllScreens`,
  `automaticAutomaticMeetingRecordingConfirmationDelay`.
- `monitoredMeetingBundleIdentifiers` and `webMeetingTargets` remain *sources*
  (which apps count as meetings), not policy.
- Settings: the master toggle in `MeetingSettingsRemindersSection` becomes the
  mode picker; `autoStartRecording` moves under it as a derived, read-only note
  (or is hidden) so no two controls can disagree.
- `resetToDefaults` resets `meetingDetectionMode` and clears the migration flag.
- ADR 006 records the policy/source split and the migration rule.

**Gate:** `make lint`; migration tests from every legacy combination, including
"no legacy values written" (fresh install → default `notify`); settings
round-trip; `AppSettingsStoreMeetingReminderTests` updated.

## Slice C — Non-blocking detection toast (L)

- `MeetingDetectionToastController` — `NSPanel`:
  - `styleMask: [.borderless, .nonactivatingPanel]`, following
    `FloatingRecordingIndicatorController`.
  - `becomesKeyOnlyIfNeeded = true`, `isFloatingPanel = true`, level
    `.statusBar` (below the reminder overlay's `.screenSaver`).
  - `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`.
  - Presented with `orderFrontRegardless()`. **Never** `makeKeyAndOrderFront`,
    never `NSApp.activate`, never touches the previously active app. This is the
    single most important behavioral difference from the Plan 126 overlay.
  - Anchor: top-right of the active screen, ~12 pt below the menu bar, stacking
    downward; re-anchors on screen-parameter change.
- `MeetingDetectionToastView` — measured targets taken from the reference still
  (targets, not law; the design system owns final numbers):

  | Property | Target |
  |---|---|
  | Height | ≈ 88 pt |
  | Corner radius | ≈ 26 pt (rounded, not capsule) |
  | App icon | 48 × 48 pt, radius 14 pt, dark container |
  | Title | ≈ 15.5 pt semibold, primary |
  | Subtitle | ≈ 13 pt secondary — **detected app name** |
  | Button | ghost, height ≈ 46 pt, radius 13 pt, 1 pt border |
  | Split | label + divider + chevron in one surface |

- States shipped: `detected`, `recording`, `ended` (Slice D). `scheduled` stays in
  the Plan 126 overlay — duplicating a calendar reminder in a toast would produce
  two alerts for one event.
  - `detected`: icon, "Meeting detected", app name, split button, auto-dismiss 12 s.
  - `recording`: pulsing dot, "Recording meeting", elapsed time, single "Stop".
  - `ended`: countdown ring, "Meeting ending", "Continue" (Slice D).
- Split-button menu: "Choose template…" and "Record without summary", routed
  through the existing capture/prompt configuration seam. No live settings reads.
- Accessibility: VoiceOver labels on icon/title/actions; Reduce Transparency →
  opaque fallback; Reduce Motion → no pulse. Verify against `better-accessibility`
  during the slice review.
- Settings: toast placement and auto-dismiss duration are **not** exposed in v1.

**Gate:** `make lint`; view-state tests for the three states; manual gate — toast
appears above a fullscreen app, does **not** steal focus from the foreground
app, and survives a rapid detected→recording transition.

## Slice D — Meeting end + countdown (M)

- `CallControlSignalProviding` with `AccessibilityCallControlProvider`, producing
  three values: `.inCall`, `.ended`, `.inconclusive`.
  - Reuse `AccessibilityPermissionService` (`AXIsProcessTrusted`) and the
    `AXTextContextProvider` messaging-timeout discipline. Search the detected
    app's window for hang-up / leave controls; absence of a recognized control is
    `.inconclusive`, never `.ended`.
  - Missing Accessibility permission → `.inconclusive` and no prompt. The app
    already surfaces this permission in `PermissionStatusPage` /
    `PermissionViewModel`; this plan does not add a new permission prompt.
- End ladder, replacing the silent stop only when a real signal exists:
  1. AX `.ended` (or `detectedContext == nil`) → start a countdown (default 10 s).
  2. Toast `ended` with the countdown ring and a "Continue" action.
  3. "Continue" cancels the pending stop and suppresses the prompt for that session.
  4. Countdown expiry → `stopRecording()` (existing path, reused).
  5. The existing 30 s `lostActivityGracePeriod` remains the fallback net and is
     **not** removed or shortened by this plan.
- `isAutomaticMeetingRecordingStopEligible` stays the authoritative stop gate;
  the countdown feeds it rather than bypassing it.
- STOP-safety: if AX is `.inconclusive` the behavior is exactly today's (silent
  stop after grace). No new way to stop a recording early is introduced.

**Gate:** `make lint`; fake-provider tests for `.inCall` / `.ended` /
`.inconclusive`; countdown cancel; grace fallback still stops when AX is
unavailable; `AutomaticMeetingRecordingConfirmationPolicyTests` unchanged.

## Acceptance criteria

1. With a meeting app holding the microphone, `MeetingDetectionSignals.attribution`
   is `.resolved` with that app's bundle identifier, within the debounce window.
2. With the microphone in use and no process owner resolved, `attribution` is
   `.unattributed` and detection still fires through the existing context +
   media gate (no regression versus today).
3. `meetingDetectionMode` alone determines monitoring, toast, and auto-record;
   migrating from any legacy combination yields the documented mode, once.
4. In `notify`, `autoStartRecording == true` does **not** auto-start recording.
5. The detection toast appears above a fullscreen app **without** taking focus
   from the foreground application, and never activates Verbi.
6. The toast renders `detected`, `recording`, and `ended`; the subtitle in
   `detected` is the detected app name, not the calendar event title.
7. Accessibility unavailable → end detection is `.inconclusive`; recording stops
   exactly as today after the 30 s grace, with no countdown prompt.
8. The Plan 126 overlay, scheduler, notifications, and summary calendar context
   are behaviorally unchanged.
9. `make validate` changed-surface lane passes for UI + Infrastructure.

## Validation commands

Per slice, smallest deterministic gate:

```bash
make lint                                  # any Swift delta
make test                                  # suite dev (filtered per slice while iterating)
make scope-check                           # changed paths are in scope
make validate-lane                         # changed-surface lane, behavior slices
make validate                              # final closeout
```

Manual gates recorded in closeout:

- Toast above a fullscreen app without focus theft (Debug build).
- `unattributed` degraded mode reproduced deliberately (owner list forced empty).
- Countdown cancel, and silent-stop fallback with Accessibility revoked.
- Migration performed against a copy of a real preferences domain.

## STOP conditions

- Unexpected changed paths outside scope → STOP, report, preserve.
- CoreAudio process APIs unavailable or unstable on the deployment target
  (macOS 15+) → STOP, ship Slice B + C without Slice A owner attribution and
  report the signal as `.unavailable`.
- The toast cannot be presented without stealing focus → STOP; do not fall back
  to the overlay, escalate to a macOS-app review.
- Slice A requires removing or re-tuning the 10 s poll to be useful → STOP; the
  poll is the documented fallback for degraded mode.
- Slice D cannot distinguish `.ended` from `.inconclusive` without reading
  user-facing dialog content → STOP, ship without Slice D.
- The migration cannot determine a mode for an existing user → STOP and default
  to the most conservative reading (`off` if no legacy value is set), reporting
  the undecidable case rather than guessing.

## Resolved decisions

| Question | Decision |
|---|---|
| Q1 — breadth of start signals | (b) mic owner by app + CoreAudio process enumeration |
| Q2 — end of meeting | (b) keep the 30 s grace as the net **and** add AX call-control end detection with a confirm countdown |
| Q3 — policy | (b) one `meetingDetectionMode` (`off`/`notify`/`auto`); calendar is a source, not a policy |
| Q4 — alert surface | (b) overlay stays for calendar reminders; compact non-blocking toast for "meeting detected" |
| Q5 — toast anchor | (b) top-right of the active screen, below the menu bar, stacking downward (declared assumption — the reference still is a crop) |
| Q6 — states in the first release | (b) `detected`, `recording`, `ended`; `scheduled` remains in the overlay |
| Q7 — split-button menu | (a) "Choose template…" and "Record without summary" |

## Open items (not blocking, to close during the slices)

- Toast anchor is a declared assumption: the reference still is a crop and does
  not show screen position.
- `recording` and `ended` appearances and the entry/exit animation are Verbi's
  design, coherent with the measured targets; no reference frame exists for them.
- Whether the reference surface is real vibrancy or a solid fill under video
  compression is undetermined; `reduceTransparency` fallback is needed either way.
- Final type scale, tracking, and radius are owned by `AppDesignSystem`, with the
  reference attached for comparison.

## Effort summary

| Slice | Size | Cumulative |
|-------|------|------------|
| A — audio ownership signals | M | M |
| B — one detection policy | M | L |
| C — detection toast | L | L |
| D — end detection + countdown | M | L |

Total: **L** (one serial workstream; A and B are independent of C, D depends on A
and C).

## Closeout

- Slices A (audio owner signals), B (`meetingDetectionMode` tri-state + migration, ADR 006), and C (non-activating detection toast) shipped.
- Slice D deferred per its STOP rule: `.ended` needs dialog content, which AX may not read. No AX end detection, countdown, or Continue. Silent 30 s grace unchanged.
- Q7 amended: toast menu offers only "Record without summary", scoped to one recording (D4). No persisted setting written from the toast.
- `isMeetingTranscriptionEnabled` remains the outer precondition (D3).
- Final review of the integrated candidate waived by the user. Last formal review: Opus PASS and Sol BLOCKED on `971379d4`; the Sol cancel finding was fixed in `7e0260d3`, not re-reviewed.
- Manual gates pending: toast focus over fullscreen apps, live AX, live CoreAudio owner attribution, real-preferences migration, VoiceOver and Reduce Transparency/Motion rendering.
