---
name: verbi
description: Design contract for Verbi's native macOS interface — Settings, capture surfaces, meeting reminders, and the notes pane.
---

# Design System: verbi

## Overview

Verbi is a native macOS utility that must feel calm and trustworthy while
recording, permissions, configuration, and processing state stay obvious
(product intent: [PRODUCT.md](PRODUCT.md)). The interface prefers macOS
semantics, materials, controls, and system colors; a custom surface exists only
where a native control cannot express the product's job.

Tokens and sources:

- Colors: `AppDesignSystem.Colors`.
- Spacing, radii, sizes, and shadows: `AppDesignSystem.Layout`.
- Typography: `AppTypography`.
- Motion: `AppleMotion` for shared springs, fades, and disclosures;
  `SettingsMotion` for Settings-specific section and side-panel motion.
- Accessibility flags: `AppDesignSystem.Accessibility`.

These Swift types are the single token source. System colors, materials, text
styles, and window behaviors are native references, never tokens: name them in
prose and leave their values to macOS. A literal in a view that these types
already own is a review finding.

Previews that render the real surfaces live in `SettingsPreviewEvidenceCatalog`
and beside each component; they are the visual baseline for this file.

## Colors

Color is reserved for selection, status, and semantic emphasis. Layout, text
hierarchy, and spacing carry the rest of the meaning.

Roles:

- Accent and selection: `Colors.accent` (the system control accent),
  `Colors.secondaryAccent`, `Colors.onAccent`, `Colors.selectionFill`,
  `Colors.selectionStroke`, `Colors.selectedContentForeground`.
- Status: `Colors.success`, `Colors.warning`, `Colors.error`, `Colors.neutral`.
  These map to the system status colors so they follow appearance and contrast
  settings.
- Recording: `Colors.recording` plus the overlay palette
  (`Colors.recordingOverlayBackground`, `Colors.overlayBackground`,
  `Colors.overlayForeground`, `Colors.overlayStatusForeground`,
  `Colors.overlayDivider`, `Colors.overlayForegroundMuted`) and the indicator
  material tint and stroke (`Colors.recordingIndicatorMaterialTint`,
  `Colors.recordingIndicatorStroke`,
  `Colors.recordingIndicatorAuxiliaryBackground`).
- Surfaces and text: `Colors.windowBackground`, `Colors.controlBackground`,
  `Colors.textBackground`, `Colors.separator`, `Colors.subtleFill`,
  `Colors.subtleFill2`, `Colors.secondaryFill`, `Colors.cardBackground`.
- Settings canvas: `Colors.settingsCanvasBackground`,
  `Colors.settingsWindowMaterialOverlay`, `Colors.settingsPanelOverlay`,
  `Colors.settingsMaterialCardFill`, `Colors.settingsMaterialCardStroke`,
  `Colors.settingsTitleBarBottomTreatment`, `Colors.settingsInlineBackground`.
- Emphasis gradients: `Colors.aiGradient` for AI identity and
  `Colors.dashboardHeroGradient` for the Activity hero.

Rules:

- Light and Dark resolve through `AppDesignSystem.Colors.resolveColor` and
  `isDarkAppearance`; never check the appearance in a view to pick a color.
- Increased contrast changes strokes and separators through the accessibility
  variants (`settingsMaterialCardStroke(increaseContrast:)`,
  `settingsTitleBarBottomTreatment(increaseContrast:)`); do not invent a second
  contrast palette.
- Overlay surfaces (recording indicator, meeting reminder) are intentionally
  fixed dark treatments with white foreground. They keep their own palette and
  do not adopt the Settings canvas colors.
- Text on a selected row uses the selected-content foreground helpers
  (`primaryTextStyle(isSelected:)`, `secondaryTextStyle(isSelected:)`) so the
  row stays legible against the selection fill.
- Important state is never encoded by color alone; pair it with an icon,
  label, or opacity change.

Native references: the accent, status, and selection colors are system colors,
and the Settings canvas uses a native material. Their values change with
appearance and accessibility settings by design.

## Typography

`AppTypography` owns the project's fonts:

- Sidebar: `sidebarIcon` and `sidebarLabel`.
- Settings section text: `settingsSectionTitle`,
  `settingsSectionDescription`, `compactControlLabel`.
- Onboarding: `onboardingStatusLabel`, `onboardingStepLabel`,
  `onboardingStepCompletedIcon`, `onboardingPermissionIcon(size:)`.
- Recording indicator: `indicatorCaption`, `indicatorActionFont`,
  `indicatorControlIconFont`, `indicatorFooterIconFont`,
  `indicatorPromptFooterFont`, and `indicatorTimerNSFont`.

Rules:

- Prefer system text styles (`.body`, `.headline`, `.caption`, and relative
  weights) inside forms, lists, and editors so Dynamic Type and accessibility
  sizes work without per-view math.
- Fixed point sizes are reserved for compact overlay chrome, where the panel
  width is measured and must not reflow. The indicator fonts carry that reason
  in their declarations; do not extend the pattern to ordinary surfaces.
- Numeric values that change while visible use monospaced digits
  (`monospacedDigit()`, `indicatorTimerNSFont`) so widths stay stable.
- Typography never substitutes for hierarchy that spacing and grouping can
  express.

## Layout

Space and size come from `AppDesignSystem.Layout`: the spacing scale
(`spacing2` through `spacing24`), the radius set (`tinyCornerRadius`,
`chipCornerRadius`, `smallCornerRadius`, `cardCornerRadius`,
`largeCornerRadius`, `heroCornerRadius`), the control heights (`controlHeight`,
`compactButtonHeight`), the keycap minimum (`keyCapSide`), and the group
padding values (`cardPadding`, `sectionSpacing`, `itemSpacing`,
`indentation`). Use the nearest token instead of a new literal.

Settings shell:

- The window is owned by AppKit through `SettingsWindowConfigurator`: a fixed
  content size (`SettingsWindowConfigurator`'s private `Layout.contentSize`), a
  native unified toolbar whose only item
  is the sidebar tracking separator, an inline leading title synced from the
  selected section, an opaque title bar with no separator hairline, and no drag
  by content background. Frame autosave uses
  `AppIdentity.settingsWindowAutosaveName`.
- `SettingsPage` owns the split layout: one fixed, non-collapsible sidebar
  (`LayoutConstants.sidebarWidth` in that file) and a detail column. There is no
  sidebar toggle.
- The sidebar has two native `List` sections from `SettingsSection`:
  `librarySections` (Activity, History, Dictionary) — content the user browses
  — and `settingsSections` (Dictation Modes, Meetings, Models, Sound, Keyboard
  Controls, General) — configuration, one concept per page. Visible labels come
  from the localized section titles, not from the enum case names. Each
  preference has one home; global keyboard shortcuts live only on the Keyboard
  Controls page. Promote a concept to its own sidebar row instead of hiding it
  in a drill-down.
- Existing settings navigation and form hierarchy stay intact: pages push their
  own child navigation and keep their drill-downs.
- One semantic scroll owner per surface: `SettingsFormPage` owns the single
  grouped `Form` and its scrolling for preference pages;
  `SettingsScrollableContent` owns the single vertical scroll surface for
  collection, status, analytics, and rich-editor pages. Never embed a page
  `Form` inside `SettingsScrollableContent`, and never add a second page-level
  scroll owner.
- `SettingsFormLayoutPolicy` resolves the readable content width from the
  available width; pages use it rather than fixed widths.
- Scalar preference rows are horizontal: label leading, control trailing, with
  optional caption under the label on the leading side. Use a native titled
  `Form` control (`Toggle`, `Picker`, `Stepper`, `LabeledContent`), then a
  shared helper (`DSToggleRow`, `SettingsDrillDownListRow`,
  `DSModifierShortcutEditor`). A label-above-control stack needs an explicit
  request recorded here and in
  [ADR 003](docs/adr/003-settings-preference-row-layout.md). Checkbox rows
  (`SettingsCheckboxRow`) keep the checkbox leading. The appearance picker is
  the documented exception: its section title stays above the thumbnail control.
  Out of scope: multi-line editors, text areas, item lists and collections,
  history and analytics dashboards, status blocks, mode drawers, and sheet field
  stacks that edit rather than set a preference.
- Rich content groups once (`DSGroup` or a `Form`/`Section`) and lays its
  children out as flat cells. Nested plates are a regression, not a polish
  choice.

Capture and reminder surfaces:

- `AppDesignSystem.Layout` carries the recording indicator metrics (heights,
  panel width, prompt sizes, wave counts, bar geometry, dot sizes, padding,
  shadows, hover springs). New indicator geometry belongs there.
- `MeetingReminderAlertMetrics` owns the reminder card metrics (outer padding,
  card width, corner radii, paddings, column spacing, snooze dropdown width).
- `MeetingNotesPaneController` owns the notes panel frame constants
  (initial, minimum, maximum size, screen-height ratio) and the autosave name
  prefix; the pane positions itself on the active display.
- Dashboards use `Layout.chartHeight` and the metric cells described under
  Components; grids stay inside one owning surface.

## Elevation & Depth

Depth comes from native materials and a small number of surface roles, not from
stacked decorative plates.

Each surface has one owning role: the window canvas belongs to
`SettingsWindowBackground`, the native settings form to `SettingsFormPage` and
`Form`/`Section`, a rich collection surface to `SettingsScrollableContent` plus
one restrained list or group treatment, a transient editor to `SettingsSidePanel`
or `ModeEditorDrawer`, and a status or recording overlay to the recording
tokens. Sidebar and navigation chrome stay native
`NavigationSplitView`/`List` selection; they are not card roles.

- Window canvas: `SettingsWindowBackground` draws the native sidebar material
  with `Colors.settingsWindowMaterialOverlay` above it, and falls back to the
  opaque `Colors.windowBackground` under Reduce Transparency. The title-bar band
  is `SettingsTitleBarMaterialBackground`.
- Grouping surfaces: `DSCard` and `DSGroup`, with
  `AppDesignSystem.SettingsSurfaceIntensity` (`.subtle`, `.regular`, `.strong`)
  and `.settings` intensity so the window canvas stays visible. Prefer
  `.settings` intensity over `.standard` opaque fills when the canvas must stay
  visible. `DSCard`/`DSGroup` may back a rich collection treatment, but never a
  second decorative plate on the canvas or a second page-level scroll owner.
  One surface owns a group; children are flat cells, rows, or charts.
- Status blocks and callouts: `SettingsStateBlock`, `DSCallout`, `DSBadge` use
  tinted icon wells, hairlines, and semantic tints as accents, never as a second
  plate on top of the canvas.
- Shadows: `Layout.shadowRadius`, `shadowX`, `shadowY`, and the small variants
  (`shadowRadiusSmall`, `shadowYSmall`) plus the indicator shadow tokens.
  Elevation steps are few and intentional; a new shadow level needs a token.
- Recording indicator: the main and confirmation pills keep their material;
  auxiliary prompt and language chips reuse the indicator tint and stroke tokens
  instead of introducing a second backdrop material.
- Meeting reminder overlay: a full-screen mesh backdrop under a glass card
  (`MeetingReminderAlertView`), with an opaque backdrop and card when Reduce
  Transparency is on.
- Notes pane: `MeetingNotesPanePanel` is borderless and transparent; its content
  uses `SettingsWindowBackground` when translucency is enabled and the opaque
  window color otherwise.

## Shapes

- Corner radii come from the radius tokens; corners use the continuous style
  where the view draws its own shape.
- Component-specific radii are symbols, not view literals:
  `MeetingNotesPanePanel.cornerRadius` for the notes panel,
  `MeetingReminderAlertMetrics.cardCornerRadius` and its primary/secondary
  radii for the reminder overlay, and `RecordingWaveMetrics.barCornerRadius`
  for waveform bars.
- Keyboard keycaps and shortcut chips use `keyCapSide` as the minimum side and
  `chipCornerRadius` for the chip shape; the appearance thumbnails use
  `smallCornerRadius`.
- Shape stays quiet: no decorative outlines beyond one border per surface and no
  capsule treatment outside compact controls, chips, and the recording pill.

## Components

Settings shell:

| Component | Role |
|---|---|
| `SettingsWindowConfigurator` | AppKit-owned window chrome contract (toolbar, title, opacity, frame autosave) |
| `SettingsPage` / `SettingsSidebarView` | Split layout and the two-section native sidebar |
| `SettingsSection` | Sidebar destinations, icons, localized titles, and legacy deep-link destinations |
| `SettingsWindowBackground` / `SettingsTitleBarMaterialBackground` | Canvas and title-bar material with opaque fallbacks |
| `SettingsFormPage` / `SettingsFormLayoutPolicy` | Single grouped `Form`, scrolling, and readable content width |
| `SettingsScrollableContent` | Single scroll owner for collection, status, and editor pages |
| `SettingsSidePanel` / `ModeEditorDrawer` | Transient editor surfaces with their own header and footer |
| `SettingsExpandableSection` | In-place disclosure for infrequent options |

Settings building blocks:

| Component | Role |
|---|---|
| `DSToggleRow`, `SettingsDrillDownListRow`, `SettingsCheckboxRow` | Standard preference rows |
| `DSModifierShortcutEditor`, `ShortcutChipRow` | The one shortcut recorder for every settings surface |
| `DSAppearanceModePicker` | System / Light / Dark window thumbnails with traffic-light chrome, accent selection stroke, and accent label |
| `DSMenuPicker`, `DSGlassSegmentedControl` | Compact non-`Form` pickers and segmented controls |
| `DSCard`, `DSGroup`, `SettingsListGroup`, `SettingsInlineList` | Grouping surfaces |
| `DSCallout`, `DSBadge`, `SettingsStateBlock`, `DSInfoPopoverButton` | Status, callout, and help affordances |
| `DSShortcutControlsRow`, `SettingsChildPageBackButton` | Composite rows and child-page navigation |

`DSModifierShortcutEditor` is the shared recorder for the notes panel,
dictation, meeting, assistant, cancel, and integration editors; do not
reintroduce a third-party shortcut recorder for settings surfaces.

Content surfaces:

- Activity and More Insights: `MetricsDashboardSummarySection` inside a
  `Form`/`Section` or one `DSGroup`, with flat `MetricStatCard` cells (icon
  well, title, value, detail). No card inside a card.
- History and transcription review: `SettingsScrollableContent` plus a list or
  collection treatment; detail pages push their own navigation.
- Dictation modes: `SettingsSidePanel`/`ModeEditorDrawer` editors with their own
  header and footer; the mode list stays the owning surface.

Capture surfaces:

- Recording indicator: `FloatingRecordingIndicatorView` renders one pill style
  through `FloatingRecordingIndicatorController`; secondary controls in
  [`FloatingRecordingIndicatorControls.swift`](Packages/VerbiCore/Sources/UI/components/recording/FloatingRecordingIndicatorView/FloatingRecordingIndicatorControls.swift)
  appear on hover, keyboard focus, or an accessibility reveal. The waveform is `AudioVisualizer`; the processing
  state uses `ProcessingSweepWave`.
- Meeting reminder: `MeetingReminderOverlayController` hosts
  `MeetingReminderAlertView` — a wide hero layout with a metadata column and an
  actions column, the fixed warm palette of `MeetingReminderMeshBackdrop`,
  `MeetingReminderPulsingDot`, and an inline snooze dropdown from
  `MeetingReminderAlertActionsColumn`.
- Meeting notes: `MeetingNotesPaneController` hosts `MeetingNotesPanePanel`
  with `MeetingNotesEditorWebView` (the default) or
  `MeetingNotesMarkdownEditor`; one controller serves calendar-event, meeting
  session, and transcription-review scopes through `NotesScope`. Persistence
  stays in `MeetingNotesMarkdownDocumentStore`.

## Do's and Don'ts

Do:

- Reuse `AppDesignSystem`, `AppTypography`, `AppleMotion`, and an existing
  `DS*` component before adding local styling.
- Keep one owning surface per group and one scroll owner per surface.
- Define lightness as fewer competing surface layers and a clear first action —
  never as lower contrast or hidden information. Secondary actions belong behind
  disclosure, a menu, or detail when the primary task does not need them.
- Let native materials and system colors carry elevation and status.
- Route every user-visible string through `.localized`.
- Verify Light, Dark, increased contrast, Reduce Transparency, Reduce Motion,
  and keyboard or VoiceOver use for the surface you change.

Don't:

- Don't nest `DSCard`/`DSGroup` inside another card, group, or `Form` section
  plate.
- Don't add a second page-level scroll owner or a manual title-bar clearance
  spacer.
- Don't stack a scalar preference label above its control without a recorded
  exception.
- Don't re-encode state as color-only, and don't add a color token for a
  one-off.
- Don't reintroduce boxed text-field chrome or a third-party shortcut recorder
  for Settings.
- Don't copy reference-app source, assets, or persistence behavior.
- Don't let a menu-bar title or an indicator carry transcript, prompt, or other
  content.

## Interaction & States

States: every affected control covers idle, hover, pressed, focused, selected,
disabled, loading, empty, permission, and error where those apply. Labels,
values, selection, keyboard behavior, and VoiceOver are part of the contract.

State precedence: a blocking permission or error state outranks loading, which
outranks empty, which outranks populated content. Within a control, the current
recording or processing state outranks hover emphasis.

Shell state: the activation policy follows Show in Dock, and opening or closing
Settings never changes it. Status item visibility follows the Show in Menu Bar
preference, whose default is visible; hiding it never disables the app lifecycle
or global shortcuts.

Focus and hit areas:

- The Settings sidebar is a native `List` selection; rows keep a full-row hit
  area and dim their icon when the window is inactive.
- Scalar preferences keep native focus rings and keyboard traversal; a custom
  row must not swallow Tab.
- The recording indicator reveals its secondary controls on hover, keyboard
  focus, or an accessibility reveal, and collapses after a short hover exit
  delay. Hover motion uses the interactive spring, or no motion under Reduce
  Motion.
- The reminder overlay becomes key so Esc triggers the cancel action and Return
  the default action. Its snooze control opens an inline dropdown; a system menu
  is not reliable at that window level.
- The notes pane becomes key for editing, autosaves its frame, and dismisses
  through the toggle, the hotkey, or the stop-recording cleanup. It is summoned
  by its global hotkey, the recording indicator's notes button, or a meeting
  reminder, and one controller resolves the scope for all three.

Keyboard:

- Global shortcuts are configurable and live only on the Keyboard Controls
  page. Their defaults are owned by
  `AppSettingsStore.defaultDictationShortcutDefinition`,
  `defaultAssistantShortcutDefinition`, `defaultMeetingShortcutDefinition`,
  `defaultMeetingNotesShortcutDefinition`).
- The shortcut recorder (`DSModifierShortcutEditor`) shows an accent placeholder
  when empty, records in a popover, reports success, conflict, or invalid
  chords, and clears through its trailing button.
- The quick correction shortcut has no default. When assigned, it uses the same
  conflict validation as every other global shortcut.
- `verbi://` deep links run the same actions as the menu bar and command
  router; the scheme and action are case-insensitive, path-style forms are
  accepted, and unknown actions are ignored.

Feedback:

- Loading uses `SettingsStateBlock` or an in-place progress treatment, never a
  blank surface.
- Empty states name the next useful action.
- Errors pair the semantic color with a message and, when available, a retry or
  recovery action.
- Permission states explain which macOS permission is needed and why, and
  degrade gracefully when it is denied.

Motion:

- Shared springs: `AppleMotion.defaultSpring`, `interactiveSpring`, and
  `pressSpring`. Settings sections use `SettingsMotion.sectionAnimation`;
  disclosure uses `SettingsMotion.expandableAnimation`, which maps to
  `AppleMotion.disclosureAnimation`; side panels use
  `SettingsMotion.sidePanelAnimation`.
- Reduce Motion replaces springs with `AppleMotion.reduceMotionFade` or removes
  the transition (`AppleMotion.transition(reduceMotion:edge:)`), pauses the
  setup waveform, and freezes the processing sweep mid-course.

## Accessibility

How the needs recorded in [PRODUCT.md](PRODUCT.md) are met:

- Keyboard: every command has a menu or shortcut path; the reminder overlay
  binds Return and Esc; Settings keeps native Tab order; sheets and drawers
  dismiss through a visible control.
- VoiceOver: rows and cells combine their children
  (`.accessibilityElement(children: .combine)`) or expose a label and hint;
  icon-only buttons carry an `.accessibilityLabel`; the reminder title is
  marked as a header; the appearance picker exposes selection traits; sidebar
  rows expose their title; team avatars expose the attendee name rather than
  initials.
- Contrast: semantic tokens follow the system status colors, and increased
  contrast strengthens strokes and separators through the accessibility
  variants. Information never depends on color alone.
- Reduce Transparency: `SettingsWindowBackground`,
  `SettingsTitleBarMaterialBackground`, `DSCard`, `DSGlassSegmentedControl`,
  the reminder overlay, and the notes pane each swap to an opaque surface that
  preserves hierarchy.
- Reduce Motion: `AppleMotion.animation(reduceMotion:kind:)`,
  `AppleMotion.transition(reduceMotion:edge:)`, and the paused `TimelineView`
  in `AudioVisualizer` replace motion with fades or stills.
- Appearance: colors resolve per appearance, so Light and Dark both keep text
  contrast; previews in `SettingsPreviewEvidenceCatalog` cover both.
- Sizing: pages stay readable at accessibility text sizes
  (`SettingsFormLayoutPolicy`), and the evidence catalog previews the
  accessibility size explicitly.

## Invariants

Each rule names the code that implements it; changing that code without
revisiting this file is a regression.

- One owning surface per group; never a `DSCard`/`DSGroup` inside another plate
  or a `Form` section plate (`DSCard`, `DSGroup`, `MetricStatCard`).
- One semantic scroll owner per surface (`SettingsFormPage`,
  `SettingsScrollableContent`).
- Settings keeps the shared chrome contract: fixed content size, fixed
  non-collapsible sidebar, unified toolbar with only the sidebar tracking
  separator, opaque title bar, no content drag, frame autosave
  (`SettingsWindowConfigurator`, `SettingsPage`).
- The activation policy follows Show in Dock only; opening or closing Settings
  never changes it (`AppDelegate`).
- Scalar preference rows are horizontal unless an exception is recorded
  (ADR 003; `DSToggleRow`, `SettingsDrillDownListRow`).
- One shortcut recorder serves every settings surface, with keycap chips and no
  text-field chrome (`DSModifierShortcutEditor`, `ShortcutChipRow`).
- Appearance is chosen with `DSAppearanceModePicker`, not a segmented control or
  menu.
- Sidebar grouping stays two native `List` sections with one concept per
  configuration page (`SettingsSection.librarySections`,
  `settingsSections`).
- The recording indicator renders one pill style; secondary controls are
  revealed, not always visible (`FloatingRecordingIndicatorView`,
  `FloatingRecordingIndicatorControls.swift`).
- The recording waveform renders the worker's log spectrum through
  `AudioVisualizer`, with geometry from `RecordingWaveMetrics` and
  `AppDesignSystem.Layout`. `AudioLevelMonitor` smooths the bands and
  `AudioVisualizerMath` supplies edge taper, opacity emphasis, and the
  synthetic pre-snapshot fallback. Audio-rate reads stay in the waveform leaf
  view.
- Processing replaces activity dots with the traveling sweep owned by
  `ProcessingSweepWave`, frozen under Reduce Motion.
- The reminder overlay stays above fullscreen apps across Spaces, becomes key
  for Esc and Return, activates the app only while presenting, restores the
  previous frontmost app on dismiss, and mirrors one window per display when
  enabled (`MeetingReminderOverlayController`).
- The quick correction editor reuses the dictionary entry fields and canonical
  validation, activates the app only while presenting, restores the previous
  frontmost app on dismiss, binds Return to Save and Esc to Cancel, and keeps a
  conflict move in the draft until Save (`VocabularyQuickTeachController`,
  `VocabularyEntryEditorFields`).
- Reminder actions remain Join, Record, Notes, Snooze (inline dropdown), and
  Dismiss; Record starts meeting capture immediately with the overlay as the
  confirmation (`MeetingReminderAlertActionsColumn`,
  `MeetingReminderActionHandler`).
- Notes panel visibility has one source of truth,
  `RecordingManager.isMeetingNotesPanelVisible`. Toggle-off, hotkey dismiss, and
  stop-recording cleanup must dismiss; never OR a sticky reopen flag
  (`RecordingManager.isMeetingNotesPanelVisible`, `AppDelegate`).
- The notes pane becomes key for editing but does not explicitly activate the
  app on summon; dismiss flushes pending saves and deactivates the app when it
  is active (`MeetingNotesPaneController`).
- The notes panel keeps its per-display frame autosave and its optional
  exclusion from screen capture (`MeetingNotesPaneController`,
  `MeetingNotesPanePanel`).
- Materials, semantic colors, and native controls stay native references; a
  system value is never frozen into a product token
  (`AppDesignSystem.Colors`, `AppTypography`).

## Review & Update Triggers

Checks that catch drift:

- `make preview-check` for Settings preview coverage, plus the visual inspection
  of `SettingsPreviewEvidenceCatalog` at both widths, dark mode, and the
  accessibility size.
- `make build` and `make test` for the compiled surfaces and their layout,
  motion, navigation, and presentation tests.
- `make guidance-check` when this file, `AGENTS.md`, or the agent docs change.
- `npx -y @google/design.md@0.4.0 lint DESIGN.md` for the document format.
- Manual pass in Light and Dark, with Reduce Motion, Reduce Transparency,
  increased contrast, and VoiceOver enabled, before shipping a visual change.

Revisit this file when:

- a new reusable component, state, motion, material, or token appears;
- a token type (`AppDesignSystem`, `AppTypography`, `AppleMotion`,
  `SettingsMotion`) gains, loses, or renames a value;
- a surface role, owning surface, or scroll owner changes;
- an ADR changes a durable decision this file cites;
- the product intent or an accessibility need in `PRODUCT.md` changes.

When implementation and this file disagree, the code is current: reconcile this
file in the same change. Record a durable trade-off in
[`docs/adr/`](docs/adr/) when it has meaningful alternatives, risk, an
ownership decision, or an external reference; one-off polish stays out. Retire a
rule when its implementation and references disappear, keeping the historical
rationale in an ADR when it still matters. Do not create a parallel
design-system document.
