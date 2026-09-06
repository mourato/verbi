# ADR 003: Settings preference row layout

**Status:** Accepted  
**Date:** 2026-09-06  
**Accepted:** 2026-09-06

## Context

Vozinha Settings already prefers native macOS form semantics
(`SettingsFormPage`, grouped `Form`, shared `DS*` row helpers). Most scalar
preferences already place the label on the leading edge and the control on the
trailing edge.

Without an explicit contract, new settings items still drift into custom
`VStack` stacks (label above control) or full-width unlabeled controls. That
breaks the System Settings expectation users bring to macOS preference panes
and makes Settings feel inconsistent across tabs.

## Decision

1. **Default:** every scalar Settings preference row is horizontal — label
   leading (start of the row), control trailing (end of the row).
2. **Exceptions:** a non-horizontal layout is allowed only when explicitly
   requested for that item (product owner / task acceptance) and recorded in
   `docs/ui.md` and/or this ADR when the exception is durable.
3. **Implementation preference:** native titled Form controls, then
   `LabeledContent`, then existing shared helpers (`DSToggleRow`,
   `SettingsDrillDown*`, `DSModifierShortcutEditor`). Do not add a parallel
   generic row wrapper for ordinary scalars.
4. **Not covered:** rich collection surfaces, multi-line editors, sheets that
   edit structured content, dashboards/filters, and checkbox HIG rows where the
   checkbox remains leading.

## Consequences

- Future Settings work treats label-above-control stacks for scalars as
  regressions unless an explicit exception exists.
- Reviewers can reject preference UI that invents vertical anatomy without a
  documented request.
- Existing outliers (below) should be remediated in follow-up implementation
  units; this ADR documents the contract and does not itself change UI code.

## Rejected or deferred

- **Vertical-first custom cards for all preferences** — rejected; fights
  native Form anatomy and increases chrome.
- **Mandatory new shared `SettingsPreferenceRow` type** — deferred; native
  Form / `LabeledContent` / existing helpers already cover the default.
- **Immediate UI remediation of all outliers** — deferred to separate scoped
  implementation units after this documentation lands.

## Known outliers at acceptance (audit 2026-09-06)

Clear violations to remediate:

| Surface | Location | Pattern today |
|---|---|---|
| Enhancements model picker | `EnhancementsModelSelectionControl.swift` (`EnhancementsModelPicker`) | Title + subtitle above bordered selection button |
| Audio ducking level | `AudioSettingsTab.swift` (ducking block) | Full-width slider with percent/notes stacked under; no leading preference label |

Borderline / decide case-by-case:

| Surface | Location | Notes |
|---|---|---|
| Audio input / power-source segmenteds | `AudioSettingsDeviceSelection.swift` | Untitled full-width segmenteds acting as composite mode tabs inside a device chooser |
| Form `.segmented` pickers with titles | General recording-indicator, Assistant border style, transcription provider sections | Native Form may stay horizontal; wrap risk at narrow widths |
| `Toggle` wrapping `LabeledContent` | `GeneralSettingsTab` (`showInDock`, recording indicator enabled) | Switch remains trailing; description competes in the value slot |

Intentional exception:

| Surface | Location | Reason |
|---|---|---|
| Appearance theme | `GeneralSettingsTab` + `DSAppearanceModePicker` | Rich thumbnail control; section title above the picker matches System Settings / Cue-style appearance chrome |

Out of preference-row scope (do not treat as violations of this ADR): history
filters, metrics dashboard chrome, multi-line editors, list/collection rows,
mode drawers, and editor sheets.

## References and license

- Project contract: [`docs/ui.md`](../ui.md) (Settings preference row layout)
- Apple Human Interface Guidelines: macOS settings / form controls (platform
  convention; inspiration only — no third-party code)

## Affected surfaces

- Settings preference tabs under
  `Packages/MeetingAssistantCore/Sources/UI/pages/settings/`
- Shared settings row helpers under
  `Packages/MeetingAssistantCore/Sources/UI/components/settings/`
- Design-system row helpers used by Settings (`DSToggleRow`,
  `DSModifierShortcutEditor`, `DSAppearanceModePicker`)
