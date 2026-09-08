# Plan 135: Normalize Settings surfaces and visual density

> **Executor instructions**: Follow this brief step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the STOP conditions section occurs, stop and
> report — do not improvise. When done, update the local status row in
> plans/README.md.
>
> **Drift check (run first)**:
> git diff --stat 51b0ac63..HEAD -- Packages/MeetingAssistantCore/Sources/UI/components/design-system/AppDesignSystem.swift Packages/MeetingAssistantCore/Sources/UI/components/design-system/DSCard.swift Packages/MeetingAssistantCore/Sources/UI/components/design-system/DSGroup.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsListGroup.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsFormPage.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsScrollableContent.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsWindowBackground.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsSidePanel.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/ModeEditorDrawer.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsExpandableSection.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/InstalledAppsSelectionSection.swift
> If any in-scope file changed since this plan was written, compare the
> Current state excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: 133-visual-surface-contract.md, 134-simplify-settings-sidebar.md
- **Category**: tech-debt
- **Planned at**: commit 51b0ac63, 2026-09-04
- **Finding ID**: settings-surface-layering
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: isolated worktree → merge to local main only when the operator authorizes it; no push unless requested

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: High/Full
- **Parallelizable**: no — shared settings components and many call sites must be changed serially
- **Reviewer required**: yes — this is a cross-page visual and accessibility contract with a broad SwiftUI surface
- **Rationale**: The current code has explicit Form, rich ScrollView, card, list-group, and panel owners, but their composition can stack multiple surfaces. Normalizing the shared owners gives the largest reduction in visual entropy per change.
- **Escalate when**: The change requires new settings state, persistence, route changes, removal of a user-visible capability, migration of the window shell, or touching the History/Activity/Recorder surfaces owned by Plans 136–138.

## Why this matters

The current Settings implementation is technically coherent but visually
over-composed. A native Form can contain a section header, a DSGroup title,
and a material DSCard, while rich pages can add their own scroll/background
layers. Each element is individually reasonable; together they make Verbi
feel heavier than VoiceInk. This plan establishes one surface owner per
semantic role and makes exceptions deliberate.

The result should feel more native and lighter without deleting help text,
accessibility labels, error states, or rich editors. It must reuse the
existing components and tokens rather than introduce a new card system.

## Current state

The shared design system already exposes a large enough token vocabulary:

- Packages/MeetingAssistantCore/Sources/UI/components/design-system/AppDesignSystem.swift:12-16
  defines subtle, regular, and strong SettingsSurfaceIntensity values.
- AppDesignSystem.swift:124-159 provides window/panel overlays, material card
  fills, and contrast-aware strokes.
- AppDesignSystem.swift:289-315 provides spacing, radii, card padding, section
  spacing, control heights, and title-bar metrics.

DSCard layers multiple treatments for Settings cards:

- Packages/MeetingAssistantCore/Sources/UI/components/design-system/DSCard.swift:3-30
  accepts a style, surface intensity, corner radius, and padding.
- DSCard.swift:32-40 applies padding, background, clipping, and a full-width
  frame.
- DSCard.swift:53-79 uses regularMaterial plus a semantic fill overlay and a
  stroke for settings cards, with an opaque Reduce Transparency branch.

DSGroup and SettingsListGroup both create titled card-backed collections:

- Packages/MeetingAssistantCore/Sources/UI/components/design-system/DSGroup.swift:3-8
  correctly says scalar settings belong in native Form/Section.
- DSGroup.swift:58-84 nevertheless always renders a title row followed by a
  DSCard.
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsListGroup.swift:30-105
  repeats that title-plus-card structure for row collections.

The native owners are already explicit:

- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsFormPage.swift:3-31
  owns one grouped Form and its vertical scrolling.
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsScrollableContent.swift:15-55
  owns one ScrollView for collection/status/analytics/editor pages and says not
  to embed a Form inside it.

Panels are intentionally different from ordinary content:

- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsSidePanel.swift:33-87
  owns the outside dismissal layer, bounded sidebar material, separators,
  Escape behavior, and reduced-motion transition.
- Packages/MeetingAssistantCore/Sources/UI/components/settings/ModeEditorDrawer.swift:54-160
  owns a three-zone header/content/footer editor with keyboard and focus
  behavior.

A representative nested collection is
Packages/MeetingAssistantCore/Sources/UI/components/settings/InstalledAppsSelectionSection.swift:38-61,
which wraps a custom list in DSGroup even when it is hosted inside a settings
page. SettingsExpandableSection.swift:3-9 and lines 33-67 already provide a
Form-friendly disclosure that should remain a disclosure, not become another
card.

## Target behavior

After this plan lands:

- Scalar preferences use SettingsFormPage, Form, and Section row anatomy.
- Rich collections, analytics, and editors use SettingsScrollableContent or a
  clearly bounded panel; they do not embed a second page-level scroll owner.
- DSGroup and SettingsListGroup remain available for collection semantics, but
  their default treatment is quiet and does not compete with the Settings
  window canvas.
- A settings card has one visible surface treatment per role. Do not stack
  regularMaterial, an opaque fill, a second card, and a decorative shadow for
  ordinary content.
- SettingsWindowBackground owns the canvas. Ordinary page content does not
  repaint the same canvas unless it is a separate surface with a documented
  reason.
- SettingsSidePanel and ModeEditorDrawer retain their panel boundary because
  they are transient editors, not ordinary content cards.
- SettingsExpandableSection remains an in-place disclosure with a visible
  expanded/collapsed cue, SettingsMotion timing, and accessible state.
- Reduce Transparency, increased contrast, Light/Dark, dynamic type, focus,
  VoiceOver, loading, empty, and error states remain supported.

The executor may choose whether the quiet treatment is a native material, a
semantic control background, or a separator-only group after previewing the
live surface. The invariant is one restrained treatment per role, not a
particular hardcoded color.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | git diff --stat 51b0ac63..HEAD -- Packages/MeetingAssistantCore/Sources/UI/components/design-system/AppDesignSystem.swift Packages/MeetingAssistantCore/Sources/UI/components/design-system/DSCard.swift Packages/MeetingAssistantCore/Sources/UI/components/design-system/DSGroup.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsListGroup.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsFormPage.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsScrollableContent.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsWindowBackground.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsSidePanel.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/ModeEditorDrawer.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsExpandableSection.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/InstalledAppsSelectionSection.swift | Empty, or reviewed as an explicit STOP condition |
| Preview declarations | make preview-check | Preview declaration coverage PASS |
| Swift lint | make lint | Exit 0 or the documented unchanged baseline |
| Focused localization integrity | make localization-check | Exit 0 when user-facing keys are changed |
| Technical lane | make validate-agent ARGS="--lane auto" | PASS or an exact baseline failure is recorded |

## Suggested executor toolkit

- apple-design for native materials, spacing, radii, hierarchy, and reduced
  transparency behavior.
- swiftui-expert-skill for Form/List/ScrollView composition and invalidation.
- swiftui-accessibility-audit for focus, VoiceOver, state, and contrast.
- swift-conventions for Swift formatting and file organization.

## Scope

**In scope** (the only files this plan should modify):

- Packages/MeetingAssistantCore/Sources/UI/components/design-system/AppDesignSystem.swift
- Packages/MeetingAssistantCore/Sources/UI/components/design-system/DSCard.swift
- Packages/MeetingAssistantCore/Sources/UI/components/design-system/DSGroup.swift
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsListGroup.swift
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsFormPage.swift
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsScrollableContent.swift
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsWindowBackground.swift
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsSidePanel.swift
- Packages/MeetingAssistantCore/Sources/UI/components/settings/ModeEditorDrawer.swift
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsExpandableSection.swift
- Packages/MeetingAssistantCore/Sources/UI/components/settings/InstalledAppsSelectionSection.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/AudioSettingsTab.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/DictionarySettingsTab.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/EnhancementsSettingsTab.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/GeneralSettingsTab.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/MeetingSettingsTab.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/ModelsSettingsTab.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/PermissionsSettingsTab.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/StylesSettingsTab.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/MetricsDashboardPerformanceComponents.swift

**Out of scope**:

- SettingsSidebarView.swift and SettingsSection.swift after Plan 134.
- TranscriptionsSettingsTab.swift and TranscriptionCardView.swift; Plan 136.
- MetricsDashboardPages.swift and MetricsDashboardComponents.swift; Plan 137.
- FloatingRecordingIndicator*; Plan 138.
- New persistence/configuration, route changes, or user-visible feature removal.
- Replacing the native Form/List/ScrollView stack with a third-party library.
- Copying VoiceInk source, assets, or CloudKit behavior.

## Git workflow

- Branch: normalize-settings-surfaces
- Commit style: refactor(ui): normalize Settings surface hierarchy
- Implementation worktrees follow core/policies/worktrees.md.
- Do not push or open a PR unless the operator instructs it.

## Steps

### Step 1: Inventory every surface owner and call site

Search for DSCard, DSGroup, SettingsListGroup, SettingsFormPage,
SettingsScrollableContent, SettingsWindowBackground, SettingsSidePanel, and
SettingsExpandableSection across the Settings UI. Classify each call site as
scalar Form content, rich collection, editor panel, or an exception.

Do not change the History or Activity call sites owned by Plans 136 and 137.
Record any call site not covered by the in-scope list and stop before editing
it.

**Verify**: rg -n "DSCard|DSGroup|SettingsListGroup|SettingsFormPage|SettingsScrollableContent|SettingsWindowBackground|SettingsSidePanel|SettingsExpandableSection" Packages/MeetingAssistantCore/Sources/UI → every in-scope call site has an explicit role.

### Step 2: Normalize shared surface defaults

Adjust the shared components so ordinary Settings content has one quiet
surface treatment. Reuse existing AppDesignSystem tokens and keep the opaque
Reduce Transparency and increased-contrast branches. Remove redundant visual
layers before adding any new token.

Keep SettingsSurfaceIntensity only where a real semantic exception needs it.
Do not delete a public case until all callers have been inventoried and the
replacement compiles. Prefer changing defaults/call sites over adding another
intensity or card style.

**Verify**: make preview-check && make lint → both pass after the shared component change.

### Step 3: Align Form and rich-content composition

For the in-scope settings tabs:

- keep scalar toggles, pickers, shortcuts, and drill-down rows inside the
  owning native Form/Section;
- keep collection rows, installed-app lists, analytics, and editors in the
  rich-content/list contract;
- remove title-plus-card nesting where the surrounding Form section already
  supplies the hierarchy;
- keep explanatory copy and error/loading/empty states, but reduce duplicate
  headings and decorative containers;
- preserve one semantic scroll owner per page.

InstalledAppsSelectionSection must remain readable in empty, populated,
protected, add, and remove states. SettingsExpandableSection must keep its
disclosure cue and reduced-motion behavior. Do not flatten ModeEditorDrawer or
SettingsSidePanel into ordinary Form rows.

**Verify**: rg -n "Form.*ScrollView|ScrollView.*Form|DSGroup|SettingsListGroup" Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs Packages/MeetingAssistantCore/Sources/UI/components/settings → every remaining combination is an intentional, documented exception.

### Step 4: Recheck appearance and accessibility fallbacks

Inspect representative pages at 600, 900, and 1200 points:

- scalar Form page with long help text;
- rich collection/list page with empty and populated states;
- installed-app collection with protected and removable rows;
- mode editor drawer with header/content/footer;
- reduced transparency and increased contrast.

Check Light/Dark appearance, keyboard focus, VoiceOver labels and values,
dynamic type, loading/error states, and reduced motion. A visually quieter
surface is not accepted if it removes a visible focus cue or makes a state
ambiguous.

**Verify**: make preview-check → declarations pass, followed by documented manual evidence.

### Step 5: Run the final technical lane

Run localization-check if copy or localization keys changed. Then run lint and
the automatic validation lane. Keep any pre-existing baseline failure separate
from failures introduced by this plan.

**Verify**: make lint && make validate-agent ARGS="--lane auto" → both pass or the exact baseline is recorded.

## Test plan

- This is primarily a view-composition change; preserve existing view-model and
  domain tests.
- Use the per-file SwiftUI previews in the changed component and settings tab
  sources as the structural visual test surface.
- Run make preview-check to prevent preview coverage regressions.
- Manually test Form, rich collection, installed-app, disclosure, and drawer
  states across appearance/accessibility variants.
- If a shared component's public behavior changes, add the smallest focused
  contract test or preview fixture rather than a snapshot suite.

## Done criteria

- [ ] Ordinary scalar settings use native Form/Section anatomy.
- [ ] Rich collection and editor surfaces have one semantic scroll owner.
- [ ] Ordinary Settings content no longer stacks multiple decorative card or
      material layers without a semantic reason.
- [ ] Reduce Transparency and increased contrast retain visible boundaries and
      state feedback.
- [ ] Panels/drawers remain bounded, dismissible, focusable, and distinct from
      ordinary content.
- [ ] make preview-check, make lint, and make validate-agent ARGS="--lane auto"
      pass or have exact baseline failures recorded.
- [ ] Manual evidence covers the required widths, states, and accessibility
      settings.
- [ ] No files outside the in-scope list are modified.
- [ ] plans/README.md records implementation, review, integration, and main
      validation separately when this plan is executed.

## STOP conditions

Stop and report if:

- The live shared component behavior differs from the cited excerpts.
- Simplifying a surface requires removing user-visible controls, help, error,
  permission, empty, or loading states.
- A page has no clear owner for scrolling after composition changes.
- The only way to make a page lighter is to introduce a new local card,
  material, spacing scale, or typography variant.
- The change affects persistence, settings routing, or external data.
- A Plan 136 or 137 surface must be modified to compile; reclassify the
  overlap instead of editing it opportunistically.
- The same validation failure occurs twice after a reasonable fix.

## Maintenance notes

- Reviewers should inspect the hierarchy of the whole page, not only each card
  in isolation.
- New scalar settings should default to native Form rows.
- New collections should reuse SettingsScrollableContent plus the existing
  collection/list treatment; do not add another scroll owner.
- Keep the panel exception explicit so future contributors do not flatten
  transient editors or reintroduce decorative plates everywhere.
