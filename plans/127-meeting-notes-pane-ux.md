# Plan 127: Meeting notes Pane-style UX

**Status:** IN PROGRESS (worktree `plan-127-meeting-notes-pane`)  
**Priority:** P1  
**Effort:** L  
**Depends on:** Plan 126 slice 4b (calendar-event notes panel scaffold) recommended, not blocking slice 0  
**ADR:** [docs/adr/002-meeting-notes-pane-ux.md](../docs/adr/002-meeting-notes-pane-ux.md)  
**Reference:** [Pane](https://github.com/ColeMei/pane)  
**Risk:** High (WKWebView editor, global hotkey, focus model, build pipeline)

## Objective

Deliver a Raycast/Pane-quality meeting notes experience: hotkey-summoned glass
panel, live markdown editing, and CSS-capable rendering — while preserving
Verbi’s calendar/meeting/transcription note model and AI context integration.

## Resolved decisions (2026-08-29)

| Topic | Decision |
|-------|----------|
| Delivery order | Layer A (panel chrome) before Layer B (WebKit editor) |
| Persistence | Keep `MeetingNotesMarkdownDocumentStore`; no user vault folder in v1 |
| Editor technology | CodeMirror 6 in `WKWebView`, bundled HTML (Pane pattern) |
| MarkdownEngine | Remain in settings/transcription review until follow-up |
| Hotkey default | New shortcut in Meeting settings; suggest `⌃⌥N` (avoid dictation conflicts) |
| Activate app on summon | No — match Pane: panel only becomes key; do not `NSApp.activate` unless required for save panel |
| Plan 126 integration | Overlay Notes opens same pane in `.calendarEvent` scope |

## Non-goals (v1)

- Flat `.md` vault exposed in Finder (Pane’s `~/Documents/Pane`)
- Full `⌘P` switcher + `⌘K` action panel (14 actions)
- Pin / note history / duplicate / recently deleted
- iCloud evicted-file download UX
- Replacing every `MeetingNotesMarkdownEditor` call site in one release

## Current state → target

| Today | Target |
|-------|--------|
| Notes panel only while recording | Hotkey anytime; scopes: calendar / session / idle→last |
| Titled `NSPanel` 420×400 | Borderless `MeetingNotesPanePanel`, auto-height, glass |
| `MarkdownEngine` + AppKit | CodeMirror live preview in WKWebView (panel path) |
| Toggle via recording indicator | Global shortcut + indicator button + Plan 126 overlay |
| `NSApp.activate` on show | Focus pane without stealing app activation |

## Architecture

```
GlobalShortcut / overlay / indicator
        │
        ▼
MeetingNotesPaneController (@MainActor)
    ├── MeetingNotesPanePanel (PanePanel-inspired)
    ├── MeetingNotesEditorHost
    │       ├── Phase A: MeetingNotesMarkdownEditor (existing)
    │       └── Phase B: MeetingNotesEditorWebView (WKWebView + bundle)
    ├── scope: NotesScope { calendarEvent(id), meetingSession(id), transcription(id)? }
    └── persistence adapters
            ├── calendar → RecordingManager.updateCalendarEventNotes
            ├── session  → RecordingManager.updateMeetingNotes
            └── store    → MeetingNotesMarkdownDocumentStore (unchanged)
```

### New types

| Type | Path |
|------|------|
| `MeetingNotesPaneController` | `UI/Presentation/` |
| `MeetingNotesPanePanel` | `UI/Presentation/` |
| `NotesScope` | `UI/Services/` or `Domain/Models/` |
| `MeetingNotesEditorWebView` | `UI/components/meeting-notes/` |
| `MeetingNotesEditorBridge` | `UI/components/meeting-notes/` (Swift ↔ JS messages) |
| `Editor/` web bundle | repo root or `Packages/MeetingAssistantCore/Resources/MeetingNotesEditor/` |
| `scripts/build-meeting-notes-editor.sh` | build CM6 bundle into Resources |

## Settings (v1)

| Key | Type | Default |
|-----|------|---------|
| `meetingNotesHotkeyEnabled` | Bool | `true` |
| `meetingNotesShortcut` | KeyboardShortcuts | `⌃⌥N` |
| `meetingNotesTranslucentPanel` | Bool | `true` |
| `meetingNotesShowOnAllSpaces` | Bool | `true` |
| `meetingNotesHideFromScreenCapture` | Bool | `false` |
| `meetingNotesAutoSizeHeight` | Bool | `true` |
| `meetingNotesEditorTheme` | String | `""` (built-in CSS) |
| `meetingNotesTextSize` | Int | 15 |

Theme CSS: optional files in Application Support
`MeetingNotes/Themes/*.css` (Pane decision 19 pattern).

## Execution slices

Run **serially** in one isolated worktree. Plan 126 may land 4b first in parallel
only if **different files** — prefer serial to avoid panel controller conflicts.

### Slice 0 — Scope model + settings (S)

- [x] ADR 002 accepted (lands with this plan).
- [x] `NotesScope` enum + resolution rules (which note to open on summon).
- [x] Settings keys + Meeting tab section “Notes panel”.
- [x] Register hotkey via existing `KeyboardShortcuts` infrastructure.

**Gate:** `make lint`; settings unit tests.

### Slice 1 — Panel chrome Phase A (L)

- [x] `MeetingNotesPanePanel`: borderless, material, radius 14, drag regions,
      frame autosave per display (`PanePanel` / `PanelGeometry` ideas).
- [x] `MeetingNotesPaneController.summon()` / `dismiss()`:
      - Summon on screen under mouse pointer.
      - Do not activate app; `makeKeyAndOrderFront` + editor focus async fix
        (Pane menu-bar summon bug).
      - Dismiss: flush pending save, `NSApp.deactivate()` if we became active.
- [x] Embed **existing** `MeetingNotesMarkdownEditor` initially.
- [x] Wire hotkey toggle; deprecate direct use of
      `MeetingNotesFloatingPanelController` from `RecordingUI` (adapter calls
      pane controller with `.meetingSession` scope).
- [x] Auto-height: measure SwiftUI editor height or fixed min until WebKit reports
      height in slice 4.

**Gate:** manual — summon over fullscreen app, type without app switch, dismiss
returns focus; `MeetingNotesFloatingPanelControllerTests` updated or replaced.

### Slice 2 — Decouple visibility from recording (M)

- [x] `updateMeetingNotesPanel` logic: show pane for `.meetingSession` when
      recording **or** when user toggled panel open.
- [x] On summon with no session: open `.calendarEvent` for imminent linked event
      (next 30 min from `CalendarEventService`) or last edited calendar notes.
- [x] Merge Plan 126 `CalendarEventNotesPanelController` into pane controller if
      126 already shipped; else implement calendar scope here.

**Gate:** manual pre-meeting notes without recording; tests for scope resolution.

### Slice 3 — Editor bundle scaffold (M)

- [x] Add `Editor/` package (TypeScript + CodeMirror 6) — fork minimal subset
      from Pane: `main.ts`, `live-preview.ts`, `markdown.css`, `tokens.css`,
      `pane.css` (rename to `meeting-notes.css`).
- [x] `scripts/build-meeting-notes-editor.sh` → copy to
      `MeetingNotesEditor/dist/index.html` in app bundle Resources.
- [x] `make build-meeting-notes-editor` rebuilds bundle outside Xcode when `Editor/` changed.
- [x] `MeetingNotesEditorWebView`: nonPersistent store, message handler
      `verbiNotes`, load file URL from bundle.

**Gate:** CI builds bundle; smoke test loads web view in debug harness or unit
test with injected bundle URL.

### Slice 4 — Editor bridge + swap (L)

- [x] Typed `MeetingNotesEditorMessage` enum (edited, ready, contentHeight,
      caret, close) — mirror Pane `PaneMessage` subset.
- [x] Load note: `loadNote(documentId, markdown, caretOffset)`.
- [x] Debounced save: 500 ms after typing stop + immediate on dismiss/blur
      (Pane decision 10).
- [ ] Replace editor host content from SwiftUI markdown editor to WebView in
      `MeetingNotesPaneController`.
- [x] Pass theme CSS + text size from settings via `applySettings` bridge.

**Gate:** round-trip persistence through `MeetingNotesMarkdownDocumentStore`;
manual live preview typing; special chars in markdown do not break bridge JSON.

### Slice 5 — Verbi integration hardening (M)

- [x] Session scope: sync pane buffer ↔ `RecordingManager.currentMeetingNotes*`
      on recording start/stop.
- [x] Transcription context: unchanged path via `meetingNotesContextItem`.
- [x] Hide from screen capture (`sharingType = .none`).
- [x] Plan 126 overlay Notes → `MeetingNotesPaneController.summon(scope: .calendarEvent)`.
- [x] Recording indicator notes button → same controller.

**Gate:** end-to-end recording with notes in AI summary; screen capture hide manual test.

### Slice 6 — Closeout (S)

- [x] Update `docs/ui.md` (pane invariants, non-activating summon, editor host).
- [x] Remove or thin `MeetingNotesFloatingPanelController` if fully migrated.
- [ ] Review + `make validate`.

## Acceptance criteria

1. User presses configured hotkey → glass notes panel appears on active display,
   caret ready, **without** switching menu bar / frontmost app.
2. User edits markdown → live preview on non-caret lines; content persists across
   dismiss and app relaunch for calendar and session scopes.
3. During meeting recording, notes sync to transcription context after stop.
4. Optional: panel hidden from screen capture when setting enabled.
5. Plan 126 reminder “Notes” opens the same panel for that calendar event.

## Validation

```bash
make build-meeting-notes-editor   # when Editor/ changed
make lint
swift test --filter MeetingNotes
make validate-agent MODULE=MeetingAssistantCore
make validate
```

Manual (test-hygiene): no visible panel in CI unit tests unless gated; manual
checklist for hotkey, fullscreen overlay, hide-from-capture.

## STOP conditions

- Hotkey requires Accessibility permission → STOP, document and offer menu-bar
  fallback only (Pane avoids this; verify KeyboardShortcuts behavior).
- WebKit bundle adds >5 MB or breaks sandbox → STOP, reassess inline bundle size.
- Live preview breaks markdown sanitizer assumptions → STOP, run
  `MeetingNotesMarkdownSanitizer` audit on round-trip.
- Scope merge conflicts with in-flight Plan 126 → serialize workstreams.

## Follow-up (Plan 127b — optional)

- `⌘P` note switcher (calendar events + recent transcriptions as rows).
- `⌘K` minimal action panel (copy markdown, reveal in app support, export HTML).
- User-visible export `.md` per transcription.
- Retire `MarkdownEngine` from dashboard event detail editor (share web host).

## Effort summary

| Slice | Size |
|-------|------|
| 0 | S |
| 1 | L |
| 2 | M |
| 3 | M |
| 4 | L |
| 5 | M |
| 6 | S |

**Total: L** (~8–12 dev days serial, including web bundle iteration).

## Dependency graph

```
Plan 126 (reminders)
    └── slice 4b CalendarEventNotesPanel ──merge──► Plan 127 slice 2

Plan 127 slice 0–1 (chrome + hotkey) ──can start independently──►
Plan 127 slice 3–4 (WebKit editor) ──depends on slice 1──►
Plan 127 slice 5 (126 overlay wire) ──depends on 126 done──►
```

Recommended execution order for one team: **126 complete → 127 slices 0–6**.
