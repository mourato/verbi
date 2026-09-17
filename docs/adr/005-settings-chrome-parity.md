# ADR 005: Settings chrome parity (900x700, fixed 215 sidebar, native toolbar)

Date: 2026-09-17
Status: Accepted

## Context

Verbi's Settings window used a SwiftUI `hiddenTitleBar` scene patched
post-hoc from AppKit: transparent titlebar, hidden title and toolbar
background, draggable content background, manual 40pt traffic-light clearance
with an animated detail spacer, collapsible 200–280pt sidebar with persisted
visibility and a View-menu toggle, and a 900x640 default size. The reference
implementation in Gugu (ADR 0022/0023) converges on a native chrome: titled
window, visible inline leading pane title, unified toolbar with only the
sidebar tracking separator, no separator hairline, opaque titlebar, no content
drag, fixed 215pt non-collapsible sidebar, 900x700 content, frame autosave,
and accessory-policy restore on close.

## Decision

Adopt the shared chrome contract for Verbi's Settings window while keeping
SwiftUI window ownership (Verbi has no primary panel window; a zero-scene app
is invalid, so the Gugu coordinator/manual-menu ownership split does not
transfer):

- Content 900x700; sidebar fixed 215pt, non-collapsible, always visible.
- Native unified toolbar (`SettingsToolbarMinimal`) with only
  `.sidebarTrackingSeparator`; `window.title` syncs from the selected section.
- `titlebarSeparatorStyle = .none`, `titlebarAppearsTransparent = false`,
  `isMovableByWindowBackground = false`, opaque window background.
- Frame autosave `MeetingAssistantSettingsWindow` preserved; existing user
  frames clamp to the new minimum via `minSize`/`contentMinSize`.
- Closing Settings restores accessory activation when no other key-capable
  window is visible (observed via `willCloseNotification`; no delegate
  override so SwiftUI behavior is preserved).
- Sidebar toggle UI removed (`⌃⌘S`, View-menu group, `commands.view.*`
  strings); a one-time heal forces persisted visibility to true.
- Deep-link section routing, updates/badge injection, detail sub-navigation
  states, and the `Form(.grouped)` preference-row contract are unchanged.

## Consequences

- Settings reads as one native surface; no manual clearance spacer or second
  scroll owner competes with the toolbar.
- `NavigationService` sidebar-toggle APIs become inert but are retained so the
  app-delegate wiring and existing tests keep compiling.
- A persisted hidden-sidebar state from before this change is healed on next
  open; the defaults key is retained for that migration only.

## Rejected

- Full AppKit window ownership (coordinator + manual menu, Gugu-style):
  correct for Gugu's panel/settings split, but for Verbi it would remove the
  only SwiftUI scene and require reworking launch, onboarding recovery, and
  updater flows for no additional visual delta.
- Keeping the collapsible sidebar as a documented exception: rejected after
  the 900x700 + fixed-215 confirmation; the toggle, persistence writes, and
  clearance animation are deleted rather than kept dormant.
