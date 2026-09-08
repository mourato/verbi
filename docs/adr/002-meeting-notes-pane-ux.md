# ADR 002: Raycast-style meeting notes panel (Pane-inspired)

**Status:** Accepted  
**Date:** 2026-08-29  
**Reference:** [Pane](https://github.com/ColeMei/pane) (`PaneController`, `EditorWebView`, `PanePanel`)

## Context

Verbi meeting notes work today but feel secondary:

- Panel opens only during active meeting capture (`isRecording &&
  capturePurpose == .meeting`).
- Editor uses `MarkdownEngine` + AppKit (`MeetingNotesMarkdownEditor`); no
  Typora-style live preview or CSS theming.
- Chrome is a standard titled `NSPanel`, not a summonable glass sheet.
- Persistence is strong (calendar event, meeting session, transcription) but
  opaque to the user compared with Pane’s plain `.md` files.

Plan 126 adds `CalendarEventNotesPanelController` for pre-meeting notes from
the reminder overlay. Plan 127 completes the notes **experience** the user asked
for: solid, Raycast/Pane-inspired, without breaking Verbi’s AI context pipeline.

## Decision

Evolve meeting notes in **two layers**, serially after Plan 126 slice 4b:

### Layer A — Panel chrome (Swift/AppKit, no editor rewrite)

Replace the primary notes surface with **`MeetingNotesPaneController`**
(Pane-inspired shell):

- Global hotkey summon/dismiss (configurable; default distinct from dictation).
- Borderless floating panel: `NSVisualEffectView` material, corner radius 14,
  auto-height from content, frame autosave per display.
- **Does not activate the app** on summon when possible; returns focus on
  dismiss.
- `collectionBehavior`: all Spaces + fullScreenAuxiliary; optional pin.
- `sharingType = .none` when “hide from screen capture” is enabled.
- Modes: **calendar event**, **active meeting session**, **transcription
  review** — one controller, scope enum; reuse existing stores.

Keep `MeetingNotesFloatingPanelController` as a thin adapter during migration,
then remove.

### Layer B — Web editor (WKWebView + bundled CodeMirror)

Replace `MeetingNotesMarkdownEditor` in the **floating panel path** with a
bundled web editor derived from Pane’s architecture:

- **CodeMirror 6** with live markdown preview (caret line raw, rest rendered).
- CSS tokens + optional user theme files (contents passed Swift → JS; no extra
  sandbox read scope).
- Swift ↔ JS bridge via typed messages (mirror Pane’s `PaneMessage` pattern).
- Markdown on disk remains internal (`MeetingNotesMarkdownDocumentStore`); no
  requirement to expose a user-facing vault folder in v1 (unlike Pane’s flat
  `~/Documents/Pane`).

**Do not** remove `MarkdownEngine` from transcription review / settings surfaces
in v1; migrate the hot-path panel first.

### Verbi-specific invariants (non-negotiable)

- Notes content still flows to AI as `TranscriptionContextItem(source: .meetingNotes)`.
- Calendar ↔ meeting ↔ transcription linking and merge rules in
  `MeetingNotes.swift` stay authoritative.
- No cloud account, no telemetry, no network for editor runtime.
- User-facing strings via `"key".localized`.

## Rationale

| Alternative | Why not (for v1 of Plan 127) |
|-------------|------------------------------|
| Keep improving AppKit `MarkdownEngine` editor only | Live preview + CSS theming fight AppKit; Pane’s quality is in the web layer |
| Full Pane port including file vault | Verbi’s multi-scope persistence is richer; vault UX is follow-up |
| Single big-bang replace all note surfaces | High risk; panel chrome delivers summon UX before WebKit lands |
| Electron / separate process | Violates local-first, lightweight menu-bar app model |

Phased delivery: **chrome first** (usable hotkey panel with existing editor),
then **WebKit editor** (Pane parity on writing feel).

## Consequences

### Positive

- Notes usable before, during, and after meetings via one summon habit.
- Editor UX matches user expectation (Pane/Raycast Notes).
- Plan 126 overlay “Notes” action can later open the unified pane.

### Negative / risks

- **Build complexity:** Node bundle step for `Editor/` (copy Pane’s `build.mjs`
  pattern into `Scripts/`).
- **WKWebView in menu-bar app:** memory, focus, hover without activation — Pane
  documents many edge cases; budget time for parity fixes.
- **Dual editor maintenance** until transcription review migrates.

### Out of scope (Plan 127)

- Note switcher (`⌘P`) and full action panel (`⌘K`) — Plan 127b or slice 6+
  if time; not required for MVP.
- Export to HTML, recently deleted, iCloud download banners.
- Replacing dashboard metrics notes editor (can share component later).

## References

- Verbi: `MeetingNotesFloatingPanelController`, `MeetingNotesMarkdownEditor`,
  `MeetingNotesMarkdownDocumentStore`, `MeetingNotes.swift`
- Pane: `Sources/Pane/PaneController.swift`, `Sources/Pane/EditorWebView.swift`,
  `Editor/src/main.ts`
- Plan 126 slice 4b: `CalendarEventNotesPanelController`
- Implementation plan: [Plan 127](../../plans/127-meeting-notes-pane-ux.md)
