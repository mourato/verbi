# ADR 006: Meeting detection policy consolidation and non-blocking toast

**Status:** Accepted  
**Date:** 2026-10-15  
**Accepted:** 2026-10-15  
**Reference:** Plan 148, superwhisper 3.0.0 parity  

## Context

Prior to this change, meeting detection in Verbi was controlled across three fragmented settings:
- `autoStartRecording` (under General / Meetings)
- `isMeetingTranscriptionEnabled` (under Meeting capability flags)
- `meetingRemindersEnabled` (under Meeting reminders)

This fragmentation caused several undesirable behaviors:
1. **Contradictory configurations:** Users could configure `autoStartRecording = true` while `isMeetingTranscriptionEnabled = false`, resulting in silent failures or half-active listeners.
2. **Policy vs Source confusion:** Calendar reminders were treated as a completely separate toggle from audio/app meeting detection, when in reality calendar, running meeting apps, and microphone ownership are all signal *sources* feeding into one meeting detection policy.
3. **Disruptive notifications:** Full-screen alerts or modal overlays steal key focus and interrupt presentations when a call starts.

In superwhisper 3.0.0, detection policy is unified into a single triad (`off`, `notify`, `auto`) and detection events surface via a non-blocking toast panel that never steals focus.

## Decision

### 1. Unified Detection Policy (`MeetingDetectionMode`)
Collapse meeting detection settings into a single canonical enum:
```swift
public enum MeetingDetectionMode: String, CaseIterable, Codable, Sendable {
    case off
    case notify
    case auto
}
```

Behavior matrix:

| Mode | Detection Monitoring | Toast | Calendar Reminders | Auto-Record |
| :--- | :--- | :--- | :--- | :--- |
| `off` | Disabled | Disabled | Disabled | Disabled |
| `notify` | Enabled | Enabled | Enabled | Disabled |
| `auto` | Enabled | Enabled | Enabled | Enabled |

Calendar is a detection and context source. Mode is authoritative for monitoring, toast, and auto-record; legacy keys are one-way mirrors. The existing `isMeetingTranscriptionEnabled` capability remains the outer precondition for detection and automatic recording (D3).

### 2. Migration Rule
To ensure existing users preserve their intended behavior without data loss, a one-time migration runs on startup, guarded by `meetingDetectionModeMigrated`:
- If `meetingDetectionModeMigrated` is true: read existing `meetingDetectionMode` (or `.notify` fallback).
- If legacy keys exist:
  - If `autoStartRecording && isMeetingTranscriptionEnabled`: migrate to `.auto`.
  - Else if `meetingRemindersEnabled`: migrate to `.notify`.
  - Else: migrate to `.off`.
- Fresh install (no legacy keys written): default to `.notify`.
- Write `meetingDetectionMode` and set `meetingDetectionModeMigrated = true`.
- Legacy keys are preserved for backward compatibility and retired in a future cleanup plan.
- `resetToDefaults()` and `resetMeetingReminderDefaults()` reset `meetingDetectionMode` to `.notify` and clear the migration flag.

### 3. Non-Blocking Detection Toast
Detection presentations utilize a dedicated `NSPanel` (`MeetingDetectionToastController`):
- Non-activating panel (`.nonactivatingPanel`, window level `.statusBar`).
- Never steals key focus or first responder status, preventing typing interruptions.
- Positioned in the top-right margin of the active display.
- States: `.detected` (Record split button) and `.recording` (app name, elapsed time, single Stop action).
- Q7 amended: the split menu offers only “Record without summary”; template selection is deferred.

### 4. Slice D deferred
Slice D hit the plan STOP rule: AX cannot distinguish ended from inconclusive without reading dialog content. No AX end detection or countdown ships. The existing silent 30-second lost-activity grace and stop eligibility gate remain unchanged.

## Consequences

- Zero contradictory settings states between auto-record, transcription capability, and reminders.
- Backward compatibility preserved for all existing installations.
- Polished, non-intrusive macOS user experience matching superwhisper 3.0.0 parity.
