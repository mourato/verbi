# ADR 001: Proactive meeting reminders with full-screen overlay

**Status:** Accepted  
**Date:** 2026-08-29  
**Accepted:** 2026-08-29  
**Reference:** [Slapss](https://github.com/theshiver/slapss-app) (`AlertScheduler`, `OverlayWindowController`, `NotificationManager`)

## Context

Verbi already reads the macOS calendar through `CalendarEventService` and uses
that data to enrich recordings (title, attendees, linked event, pre-meeting
notes in the metrics dashboard). Meeting detection today is **reactive**: when a
supported meeting app is running, `MeetingDetector` may offer automatic recording
via the small floating indicator.

That flow helps once a call is already open. It does not solve the product gap
the user described: **useful notification before a meeting starts** — enough
context and actions to join, prepare notes, or start capture without hunting the
Calendar app or the Verbi dashboard.

[Slapss](https://github.com/theshiver/slapss-app) demonstrates a proven pattern
on macOS: poll upcoming calendar events, schedule lead-time local notifications,
fire a full-screen overlay at meeting time, and offer Join / Snooze / Dismiss
with reliability work around App Nap, sleep, and back-to-back meetings.

## Decision

Add a **proactive meeting reminder subsystem** to Verbi, inspired by Slapss
but integrated with existing Verbi capabilities:

1. **`MeetingReminderScheduler`** (Infrastructure/UI boundary) watches upcoming
   calendar events and schedules:
   - a **lead-time local notification** (configurable minutes before start), and
   - a **full-screen overlay** at start time (with optional seconds-before offset).

2. **`MeetingReminderOverlayController`** presents a native full-screen alert
   (AppKit host + SwiftUI content) at `.screenSaver` window level, above
   fullscreen apps and across Spaces.

3. **Primary actions on the overlay** (Verbi-specific):
   - **Join** — open detected meeting URL (reuse `CalendarEventService` link
     heuristics).
   - **Record** — start meeting capture **immediately** (no auto-record
     confirmation countdown) and link the calendar event when authorized.
   - **Notes** — open meeting notes for the linked calendar event (reuse
     `RecordingManager` calendar-event notes persistence).
   - **Snooze** — re-fire after 1 / 5 / 10 / 15 minutes or until event end.
   - **Dismiss** — suppress further reminders for that occurrence.

4. **Settings** live under Meeting settings with persisted keys in
   `AppSettingsStore`. Defaults mirror Slapss where sensible (15-minute lead,
   overlay at start, overlay enabled).

5. **Scope for v1 is EventKit only.** No Microsoft Graph, no Reminders.app
   overlays, no multi-calendar aggregator beyond what EventKit already returns.

6. **Coexistence:** proactive reminders are independent of
   `MeetingDetector` / automatic meeting recording. A user may dismiss the
   overlay and still get reactive auto-record when the meeting app opens. Settings
   may later add “start recording from overlay” but must not silently replace
   existing auto-record behavior in v1.

## Resolved product decisions (2026-08-29)

1. **Visual design:** Slapss wide-hero layout and metric scale (56pt title,
   two-column card, glass treatment, inline snooze). Fixed warm mesh backdrop;
   no user theme picker in v1.
2. **Record action:** immediate `startCapture(purpose: .meeting)` when the user
   taps Record on the overlay — the overlay itself is the confirmation.
3. **Notes action (Plan 126 slice 4b):** minimal decouple — introduce
   `CalendarEventNotesPanelController` bound to `eventIdentifier` only, reusing
   `MeetingNotesMarkdownEditor` and calendar-event persistence. Full Pane-style
   notes UX is Plan 127.

## Rationale

| Alternative | Why not (for v1) |
|-------------|------------------|
| Extend macOS Calendar alerts only | No Join/Record/Notes actions; easy to miss; no Verbi integration |
| Reuse floating recording indicator only | Too small for pre-meeting prep; wrong UX metaphor |
| Dashboard-only upcoming list | Requires user to open Settings; not “in your face” at start time |
| Poll only when dashboard is visible | Misses fires when app is idle (Slapss watchdog/App Nap lessons) |
| Microsoft Graph in v1 | YAGNI; EventKit covers most local-first users; large auth surface |
| UN notifications only (no overlay) | Lead toast helps; start-time moment still lost in focus-heavy work |

Slapss’s `AlertScheduler` is the closest production reference for timer
reliability (`.common` run loop mode, wake observer, missed-fire catch-up,
pending queue for overlapping alerts, presenting mode). Reusing that structure
reduces unknown macOS edge cases.

## Consequences

### Positive

- Calendar permission and `MeetingCalendarEventSnapshot` investment pays off
  outside the metrics dashboard.
- Pre-meeting notes (`loadCalendarEventNotesContent`) become reachable at the
  moment they matter.
- Recording can start from intentional user action on the overlay, improving
  trust vs. silent auto-start.

### Negative / risks

- **High-visibility UI** — overlay must respect Reduce Motion, Reduce
  Transparency, VoiceOver, and keyboard (Esc dismiss, Return primary action).
- **Permission coupling** — feature degrades gracefully when calendar access is
  denied; must not crash or spin.
- **Interaction with menu bar app lifecycle** — overlay must activate app
  briefly to become key (Slapss pattern); document in `docs/ui.md` when
  implemented.
- **Duplicate signals** — lead notification + overlay + reactive auto-record
  may feel noisy; settings must allow disabling each layer independently in a
  follow-up if needed (v1: overlay toggle + lead minutes = 0 off).

### Follow-ups (explicitly out of v1)

- Menu bar countdown for next meeting (Slapss `currentMenuBarMeeting`).
- “Presenting mode” queue (Slapss `presentingModeEnabled`).
- RSVP filter (`onlyAcceptedMeetings`) — requires extending
  `MeetingCalendarEventSnapshot` with participation status from `EKEvent`.
- Microsoft 365 / Graph calendar source.

## Compliance

- User-facing strings: `"key".localized`; remove orphaned keys when deleted.
- No secrets in notifications or overlay copy; do not log full event notes.
- Local-first: EventKit reads stay on device; no new network entitlement.
- `#available` guards if any API requires macOS 26+; macOS 15 remains minimum.

## References

- Verbi: `CalendarEventService`, `MeetingCalendarIntegrationService`,
  `MetricsDashboardViewModel`, `NotificationService`,
  `MeetingNotes` / calendar-event notes, `MeetingDetector`
- Slapss: `slapss/Scheduling/AlertScheduler.swift`,
  `slapss/Alert/OverlayWindowController.swift`,
  `slapss/Scheduling/NotificationManager.swift`
- Implementation plan: [Plan 126](../../plans/126-meeting-reminder-scheduler-slapss.md)
