# Shortcuts and Deep Links

Primary ways to invoke Verbi actions from outside the UI.

## Deep links

Scheme: `verbi://`

Register as `CFBundleURLSchemes` in the app target. Opening a link launches
Verbi if needed, then runs the same action as the matching menu / command
router entry.

| Action | URL | Behavior |
| --- | --- | --- |
| Dictation | `verbi://dictation` | Same as **Dictation** in the menu bar (start/stop mic capture) |
| Meeting | `verbi://meeting` | Same as **Meeting** in the menu bar (system + mic capture when meeting transcription is enabled) |
| Assistant | `verbi://assistant` | Same as **Assistant** in the menu bar (start/stop assistant capture when Assistant is enabled) |
| History | `verbi://history` | Opens Settings on the History section |
| Settings | `verbi://settings` | Opens Settings |

Path-style forms such as `verbi:///dictation` are also accepted. Scheme and
action are case-insensitive. Unknown actions are ignored.

### Examples

```sh
open 'verbi://dictation'
open 'verbi://meeting'
open 'verbi://assistant'
open 'verbi://history'
open 'verbi://settings'
```

### Implementation

- Parser: `AppDeepLink` in MeetingAssistantCoreCommon
- Dispatch: `AppDelegate/DeepLinks.swift` → `AppCommandRouter`

## Keyboard shortcuts

Configurable keyboard shortcuts for dictation, meeting, assistant, and related
actions live in **Settings**. Defaults and custom bindings are not duplicated
here; treat Settings as the source of truth for key chords.
