# Plan 126: Meeting reminder scheduler (Slapss-inspired)

**Status:** DONE (`ea44eeb7`, `350fe349`, `c186e626`)  
**Priority:** P1  
**Effort:** L  
**Depends on:** — (reuses existing calendar + recording surfaces)  
**ADR:** [docs/adr/001-meeting-reminder-overlay.md](../docs/adr/001-meeting-reminder-overlay.md)  
**Risk:** High (calendar permissions, AppKit window level, scheduling reliability, user-visible takeover UI)

## Objective

Ship proactive meeting reminders in Verbi: lead-time notification + full-screen
overlay at meeting start, with Join, Record, Notes, Snooze, and Dismiss — aligned
with [Slapss](https://github.com/theshiver/slapss-app) behavior and wired into
existing calendar and recording infrastructure.

## Non-goals (v1)

- Microsoft Graph / Outlook calendars
- Reminders.app (`EKReminder`) overlays
- Menu bar live countdown title
- Presenting-mode alert queue
- RSVP / “only accepted meetings” filter
- Replacing or removing reactive `MeetingDetector` auto-record

## Reuse → extend → create

| Layer | Reuse | Extend | Create |
|-------|-------|--------|--------|
| Calendar read | `CalendarEventService.fetchUpcomingEvents`, link detection, ignore list | Optional `EKEventStoreChanged` refresh hook | — |
| Notifications | `NotificationService.requestAuthorization` | Scheduled requests, categories, delegate actions | `MeetingReminderNotificationCoordinator` |
| Overlay host | Patterns from `MeetingNotesFloatingPanelController`, `FloatingRecordingIndicatorController` | — | `MeetingReminderOverlayController`, `MeetingReminderAlertView` |
| Actions | `RecordingManager.startCapture`, `linkCurrentMeeting`, calendar notes APIs | Thin coordinator protocol | `MeetingReminderActionHandler` |
| Settings | `MeetingSettingsTab`, `AppSettingsStore` persistence | New keys + section | — |
| Dashboard | `MetricsDashboardViewModel` upcoming events | Share scheduler refresh optional | — |

## Architecture

```
App launch
    │
    ▼
MeetingReminderCoordinator (@MainActor, attach once)
    ├── polls CalendarEventService (30s) + EKEventStoreChanged
    ├── MeetingReminderScheduler.reschedule(events)
    │       ├── UN lead notification (NotificationService)
    │       └── Timer → fire overlay (RunLoop.common)
    └── MeetingReminderOverlayController.show(...)
            └── MeetingReminderActionHandler
                    ├── Join → NSWorkspace.open(url)
                    ├── Record → RecordingManager.startCapture(.meeting) + link event
                    ├── Notes → open notes surface for eventIdentifier
                    ├── Snooze / Dismiss → scheduler state
```

### New types (target locations)

| Type | Module path |
|------|-------------|
| `MeetingReminderScheduler` | `Infrastructure/Services/` |
| `MeetingReminderCoordinator` | `UI/Services/` |
| `MeetingReminderOverlayController` | `UI/Presentation/` |
| `MeetingReminderAlertView` | `UI/components/meeting-reminder/` |
| `MeetingReminderActionHandling` | `UI/Services/` (protocol + default impl) |
| Settings keys | `Infrastructure/Models/AppSettingsStore/` |

### Domain extension (minimal)

Add to `MeetingCalendarEventSnapshot` (or adjacent helper):

- `joinURL: URL?` — computed from location/notes/url using existing
  `CalendarEventService.containsKnownMeetingLink` logic (extract shared helper
  if not already callable from snapshot).

Keep snapshot Sendable; do not hold `EKEvent` in UI state.

## Settings (v1)

| Key | Type | Default | Slapss equivalent |
|-----|------|---------|-------------------|
| `meetingRemindersEnabled` | Bool | `true` | feature master switch |
| `meetingReminderLeadMinutes` | Int | `15` | `leadTimeMinutes` (0 = off) |
| `meetingReminderOverlayLeadSeconds` | Int | `0` | `overlayLeadTimeSeconds` |
| `meetingReminderOverlayEnabled` | Bool | `true` | implicit |
| `meetingReminderAlertSoundEnabled` | Bool | `false` | `alertSoundEnabled` |
| `meetingReminderMirrorAllScreens` | Bool | `false` | `showAlertOnAllScreens` |

Persist dismissed occurrence IDs in UserDefaults (session + cross-launch):
`meetingReminderDismissedEventKeys` — store stable key
`"\(eventIdentifier)-\(startDate.timeIntervalSince1970)"` so recurring events
can fire again on a new occurrence.

Snooze state stays in-memory + rescheduled effective start (Slapss pattern).

## UI contract (overlay)

Follow [docs/ui.md](../docs/ui.md) and Slapss `AlertView` **layout**, adapted to
Verbi tokens (**decision: no Slapss mesh themes in v1**):

- Full-screen backdrop using `AppDesignSystem` semantic colors + native material
  (document overlay invariants in `docs/ui.md`).
- Glass card: title, time range, location, attendee count (not full avatar stack
  in v1 unless cheap).
- Status pill with live countdown (1s timer, `.common` mode).
- Primary button: **Record** when meeting transcription enabled; else **Join**
  when URL exists.
- Secondary: Join (if Record primary), Notes, Snooze menu, Dismiss.
- Keyboard: Esc → dismiss, Return → primary action.
- Window: `.screenSaver`, `canBecomeKey`, `fullScreenAuxiliary`, optional
  mirror all screens.
- Accessibility: VoiceOver labels, Reduce Motion (no pulse), Reduce Transparency
  (opaque card fallback).

**Notes action v1 (decision: minimal decouple):** add
`CalendarEventNotesPanelController` — borderless/floating panel bound to
`eventIdentifier` only, reusing `MeetingNotesMarkdownEditor` +
`loadCalendarEventNotesContent` / `updateCalendarEventNotes`. Do **not** require
`isRecording`. Keep `MeetingNotesFloatingPanelController` for in-session notes
during capture; Plan 127 unifies chrome later.

## Execution slices

Implement **serially** in one isolated worktree. One slice per commit unit;
validate each slice before the next.

### Slice 0 — Scaffold + settings (S)

- [x] Add ADR 001 (this plan assumes it lands together).
- [x] Add settings keys, defaults, localization keys (en + pt-BR if project
      convention requires both for new UI).
- [x] Add Meeting settings section “Reminders” with toggles/steppers.
- [x] Unit tests: settings round-trip defaults.

**Gate:** `make guidance-check` if guidance-only; else `make lint` on touched
Swift files.

### Slice 1 — Scheduler core (M)

- [x] `MeetingReminderScheduler` with:
  - `reschedule(events:now:)` from Slapss `AlertScheduler` (timers, cache, dropped
    event cleanup, missed-fire catch-up, pending queue skeleton).
  - App Nap token `ProcessInfo.beginActivity(.userInitiated)`.
  - Watchdog 20s on `RunLoop.main` `.common`.
  - `NSWorkspace.didWakeNotification` cache bust.
- [x] `MeetingReminderCoordinator` polls `CalendarEventService` every 30s when
  enabled + authorized.
- [x] Respect `ignoredCalendarEventIdentifiers` and master enable flag.
- [x] No overlay yet — log `fireMeetingStart` at debug level.

**Gate:** unit tests with injected clock/fake events for schedule, snooze,
dismiss, missed-fire catch-up.

### Slice 2 — Lead notifications (M)

- [x] Extend `NotificationService`:
  - Register categories: plain + join action.
  - `scheduleMeetingLeadNotification(identifier:at:title:body:joinURL:)`.
  - `cancelMeetingLeadNotification(identifier:)`.
  - `UNUserNotificationCenterDelegate` handling join action → open URL.
- [x] Wire scheduler lead path; cancel on dismiss/snooze/event drop.
- [x] Request authorization on first enable (reuse existing request path).

**Gate:** unit tests for identifier namespacing; manual: notification fires at
lead time in Debug app bundle.

### Slice 3 — Overlay UI (L)

- [x] `MeetingReminderOverlayController` (multi-screen optional).
- [x] `MeetingReminderAlertView` SwiftUI + countdown states.
- [x] Wire scheduler `fireMeetingStart` → overlay; queue if already visible.
- [x] Snooze/dismiss callbacks back into scheduler.
- [x] Sound: `NSSound.beep()` when setting enabled.

**Gate:** manual test-hygiene checklist — overlay above fullscreen browser,
Esc/Return, Reduce Motion/Transparency; no test launches visible window in CI
without hygiene guards.

### Slice 4a — Join + Record actions (M)

- [x] `MeetingReminderActionHandler`:
  - Join: `NSWorkspace.shared.open(url)`.
  - Record: **immediate** `RecordingManager.startCapture(purpose: .meeting)` +
    `linkCurrentMeeting(to: event)` when not already recording — skip
    `AutomaticMeetingRecordingConfirmation` countdown.
- [x] Dismiss overlay after action (Slapss behavior).

**Gate:** `RecordingManagerTests` or focused handler tests with mocks; manual
join + record from overlay.

### Slice 4b — Notes action (M)

- [x] Add `CalendarEventNotesPanelController` (calendar-event scope only).
- [x] Notes button on overlay opens panel for `event.eventIdentifier`; load via
      `loadCalendarEventNotesContent`, persist via `updateCalendarEventNotes`.
- [x] Panel summonable without active recording; no change to in-session
      `MeetingNotesFloatingPanelController` behavior yet.

**Gate:** existing `MeetingNotes*` tests updated; manual pre-meeting edit
survives app restart.

### Slice 5 — Lifecycle integration (S)

- [x] Attach coordinator in `AppDelegate` / app launch (idempotent `.attach()`).
- [x] Stop scheduler when calendar permission revoked.
- [x] Settings changes bust scheduler cache (lead minutes / overlay offset).

**Gate:** `make validate` changed-surface lane for UI + Infrastructure modules.

### Slice 6 — Closeout (S)

- [x] Update `docs/ui.md` with overlay invariants (window level, activation).
- [x] Update plan ledger status → DONE with commit SHAs and validation output.
- [x] Review: defect-first pass on scheduling + permission paths.

## Acceptance criteria

1. With calendar access granted and reminders enabled, a meeting with a call
   link in location/notes appearing in the next 24h schedules a lead
   notification at `meetingReminderLeadMinutes` before start.
2. At meeting start (± overlay lead seconds), a full-screen overlay appears
   with correct title and time; Esc dismisses; Return triggers primary action.
3. **Join** opens the detected URL; **Record** starts meeting capture and links
   the calendar event; **Notes** opens editor bound to that event’s notes.
4. **Snooze** re-fires after selected interval; **Dismiss** suppresses further
   reminders for that occurrence.
5. Ignored events (dashboard ignore) never schedule.
6. After sleep/wake during an in-progress meeting window, missed overlay still
   surfaces (catch-up within 10-minute staleness grace — Slapss default).
7. Feature off or calendar denied → no timers, no overlay, no crash.

## Validation commands

Per slice, smallest deterministic gate:

```bash
make lint                                    # any Swift delta
swift test --filter MeetingReminder          # after slice 1+
make validate-agent MODULE=MeetingAssistantCore   # behavior slices
make validate                                # final closeout
```

Record manual gates in closeout:

- Lead notification delivery (app bundle, not xctest).
- Overlay above fullscreen app.
- Record + linked event visible in metrics dashboard during capture.

## STOP conditions

- Unexpected changed paths outside scope → STOP, report, preserve.
- Calendar entitlement or sandbox mismatch blocks EventKit in Release → STOP,
  document required entitlement diff before proceeding.
- Overlay cannot become key without breaking menu-bar-only lifecycle → STOP,
  escalate to macOS-app-engineering review.
- Slice 4b expands into WebKit/CodeMirror editor work → STOP, defer editor to
  Plan 127; ship Join/Record/Snooze/Dismiss without Notes.

## Resolved decisions

| Question | Decision |
|----------|----------|
| Visual design | `AppDesignSystem` + Slapss wide-hero metrics; fixed warm mesh backdrop (no theme picker in v1) |
| Record action | Immediate capture; overlay is the confirmation |
| Notes (4b) | `CalendarEventNotesPanelController` for calendar events only; Plan 127 unifies UX |

## Effort summary

| Slice | Size | Cumulative |
|-------|------|------------|
| 0 | S | S |
| 1 | M | M |
| 2 | M | L |
| 3 | L | L |
| 4a | M | L |
| 4b | M | L |
| 5–6 | S | L |

Total: **L** (one serial workstream, ~6–10 focused dev days with review/remediation).

## Closeout

**Commits**

- `ea44eeb7` — feature: scheduler, overlay, notifications, settings, tests
- `350fe349` — fix: `@Published` properties must live in `AppSettingsStore` body
- `c186e626` — polish: Slapss wide-hero overlay layout + Plan 126 closeout

**Validation**

- `make build-release` — pass
- `MeetingReminder*` unit tests — 9/9 pass (prior slices)
- Manual gates — lead notification, overlay above fullscreen, Record + linked event (user-owned)

**Deferred follow-ups**

- Optional `EKEventStoreChanged` refresh hook (30s poll + wake/watchdog cover most cases)
- Slapss theme picker / mesh palette variants
- Plan 127 notes pane UX unification
