# UI

Current UI contract for Vozinha (technical project identity: Prisma). Read
this before changing Settings, onboarding, status/recording surfaces, shared
design-system components, or native window/panel chrome. Durable rationale
belongs in ADRs when the project introduces that directory; this file is the
current contract, not a task log.

## Product intent

Vozinha is a local-first macOS meeting capture, transcription, and AI
post-processing app. Its UI should feel native, calm, and trustworthy while
making recording, permissions, configuration, and processing state obvious.

## Sources of truth

- Shared tokens and components: [`AppDesignSystem.swift`](../Packages/MeetingAssistantCore/Sources/UI/components/design-system/AppDesignSystem.swift), [`AppTypography.swift`](../Packages/MeetingAssistantCore/Sources/UI/components/design-system/AppTypography.swift), and the neighboring `DS*` components
- Shared motion: [`AppleMotion.swift`](../Packages/MeetingAssistantCore/Sources/UI/components/design-system/AppleMotion.swift) and [`SettingsMotion.swift`](../Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsMotion.swift)
- Settings surfaces: [`SettingsPage.swift`](../Packages/MeetingAssistantCore/Sources/UI/pages/settings/SettingsPage.swift), [`SettingsFormPage.swift`](../Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsFormPage.swift), and [`SettingsWindowBackground.swift`](../Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsWindowBackground.swift)
- Project UI routing and constraints: [`AGENTS.md`](../AGENTS.md)

When implementation and this document disagree, inspect the code, reconcile
the contract in the same change, and record a durable trade-off in an ADR when
one exists. Do not create a parallel design-system document.

## Principles and invariants

- Prefer macOS-native semantics, materials, controls, and system colors.
- Keep spacing, radii, typography, colors, surfaces, and control sizing in
  `AppDesignSystem`; use shared `DS*` components before local variants.
- The shared layout scale is tokenized from 2 through 24 points. Common radii
  are 4, 6, 8, 12, and 16; standard controls are 34 points high and compact
  controls 30 points high.
- Shortcut recording controls (`DSModifierShortcutEditor` / `ShortcutChipRow`)
  use compact keycap chips (`keyCapSide` 18, `chipCornerRadius` 6, secondary
  fill + primary stroke) without text-field chrome. Empty idle state is an
  accent CTA; recording uses a light accent highlight around the keycap
  control. Do not reintroduce boxed text-field chrome for this control.
  Notes panel, dictation, meeting, assistant, cancel, and integration editors
  all use this shared control — do not reintroduce `KeyboardShortcuts.Recorder`
  for settings surfaces.
- Appearance mode uses `DSAppearanceModePicker`: System / Light / Dark window
  thumbnails with traffic-light chrome, accent selection stroke, and accent
  label. Prefer this over segmented or menu pickers for the theme control.
- Use semantic colors for accent, success, warning, error, neutral, recording,
  and permission states. Do not encode important state only through color.
  Color is reserved for selection, status, and semantic emphasis.
- Settings uses a native window background/material with an opaque fallback for
  Reduce Transparency and a clear title-bar boundary; avoid nested decorative
  plates that compete with the window surface.
- Keep one semantic scroll owner per scrollable surface and preserve the
  existing Settings navigation and form hierarchy.
- Lightness means fewer competing surface layers and a clear first action, not
  lower contrast or less accessible information. Secondary actions belong behind
  disclosure, menu, or detail when they are not required for the primary task.
- User-facing copy stays localized with existing `.localized` keys. Do not copy
  reference-app source, assets, or persistence behavior.

### Surface roles

Each Settings or overlay surface has one owning role. Do not invent a parallel
token namespace or a second design-system document to express these roles.

| Surface role | Owner | Allowed visual weight | Typical content |
|---|---|---|---|
| Window canvas | `SettingsWindowBackground` | Native window material or opaque accessibility fallback | The Settings page background |
| Native settings form | `SettingsFormPage` and `Form`/`Section` | Lowest chrome; native row anatomy | Scalar preferences and drill-down rows |
| Rich collection surface | `SettingsScrollableContent` plus a shared collection/list treatment | One restrained grouping treatment | History, analytics, status blocks, editors |
| Transient editor surface | `SettingsSidePanel` or `ModeEditorDrawer` | Clearly bounded panel with its own header/footer | Mode and advanced editors |
| Status/recording overlay | Existing `AppDesignSystem` recording tokens | High semantic contrast only when state demands it | Recording, processing, error, confirmation |

`DSCard` and `DSGroup` may back a rich collection treatment, but they must not
stack a second decorative plate on top of the window canvas or nest a second
page-level scroll owner. Sidebar/navigation chrome stays native
`NavigationSplitView`/`List` selection; it is not a card role.

## States, accessibility, and motion

Affected controls must cover idle, hover, pressed, focused, selected, disabled,
loading, empty, permission, and error states as applicable. Labels, values,
selection, keyboard behavior, and VoiceOver are part of the contract.

Use `AppleMotion`/`SettingsMotion`. Default, interactive, and press springs are
shared; disclosure is 0.2 seconds and Reduce Motion uses a short fade or no
motion. Respect Reduce Transparency and increased contrast, preserving content
hierarchy and feedback in every fallback.

## Meeting reminder overlay

- Full-screen meeting reminders use an AppKit-hosted SwiftUI overlay at
  `.screenSaver` level with `fullScreenAuxiliary` collection behavior so the
  alert appears above fullscreen apps and across Spaces.
- The overlay window must become key (`canBecomeKey`) so Esc dismisses and
  Return triggers the primary action; the app activates briefly when presenting
  and restores the previous frontmost app on dismiss.
- Optional mirror-all-screens mode builds one overlay window per connected
  display; dismissing on any screen dismisses all instances.
- Visual treatment uses a Slapss-inspired wide-hero layout: animated mesh
  backdrop (fixed warm palette), glass card at 880pt max width, 56pt title,
  two-column metadata/actions, and inline snooze dropdown (not a system menu,
  which is unreliable at `.screenSaver` level). Primary CTAs use 16pt semibold
  labels with 20×18pt padding; secondary actions use 14pt medium with 16×14pt
  padding. Reduce Transparency falls back to opaque backdrop/card surfaces;
  Reduce Motion freezes mesh animation and pulsing status dots.

## Meeting notes pane

- The summonable notes surface is `MeetingNotesPaneController` with a
  borderless glass `MeetingNotesPanePanel` (14pt corner radius, optional
  translucency via `SettingsWindowBackground`).
- Summon via global hotkey (`⌃⌥N` default), recording-indicator notes button,
  or Plan 126 reminder overlay; one controller handles calendar, session, and
  transcription scopes via `NotesScope`.
- The pane becomes key for editing but must not call `NSApp.activate` on
  summon; dismiss flushes pending saves and deactivates the app only if it
  became active.
- Frame position autosaves per display; optional `sharingType = .none` hides the
  panel from screen capture when enabled in Meeting settings.
- Phase A embeds `MeetingNotesMarkdownEditor`; Phase B swaps the panel path to
  `MeetingNotesEditorWebView` (WKWebView + bundled editor) without changing
  persistence (`MeetingNotesMarkdownDocumentStore`).

## Review checklist

- [ ] Reuse `AppDesignSystem`, `AppTypography`, `AppleMotion`, and existing
      `DS*` components before adding local styling.
- [ ] Preserve native window/material behavior and accessibility fallbacks.
- [ ] Match the surface-role table: one owner per role, no nested decorative
      plates or competing scroll owners, progressive disclosure for secondary
      actions, and lightness without lowering contrast.
- [ ] Verify relevant states, keyboard/VoiceOver, Light/Dark, increased
      contrast, Reduce Transparency, and Reduce Motion.
- [ ] Update this file when a reusable UI rule or invariant changes.
- [ ] Add or update an ADR for a meaningful alternative, risk, ownership
      decision, or external reference; do not record one-off polish.

## Lifecycle

Create or update this file when a rule applies across surfaces, constrains
future implementation, or explains a product-level trade-off. Retire rules
when their implementation and references disappear; preserve historical
rationale in an ADR when it remains useful.
