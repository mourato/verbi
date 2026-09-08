# Plan 134: Simplify the Settings shell and sidebar

> **Executor instructions**: Follow this brief step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the STOP conditions section occurs, stop and
> report — do not improvise. When done, update the local status row in
> plans/README.md.
>
> **Drift check (run first)**:
> git diff --stat 51b0ac63..HEAD -- Packages/MeetingAssistantCore/Sources/UI/pages/settings/SettingsSidebarView.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsSection.swift Packages/MeetingAssistantCore/Sources/UI/pages/settings/SettingsPage.swift Packages/MeetingAssistantCore/Sources/UI/components/design-system/AppTypography.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsSearchField.swift
> If any in-scope file changed since this plan was written, compare the
> Current state excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: 133-visual-surface-contract.md
- **Category**: direction
- **Planned at**: commit 51b0ac63, 2026-09-04
- **Finding ID**: settings-sidebar-visual-entropy
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: isolated worktree → merge to local main only when the operator authorizes it; no push unless requested

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: Medium/Full
- **Parallelizable**: no — it changes the primary Settings navigation surface
- **Reviewer required**: yes — routing, search, update state, keyboard access, and visual hierarchy must be reviewed together
- **Rationale**: The change is UI-local but touches the first surface every Settings user sees and can affect legacy route destinations.
- **Escalate when**: Search behavior, navigation persistence, SettingsSection destinations, or window/sidebar sizing must change; those are behavior or shell changes beyond visual simplification.

## Why this matters

Verbi's sidebar exposes more visual semantics than the native macOS sidebar
needs: every row gets a colored rounded badge and a gradient, while search is a
permanent top block. VoiceInk feels calmer because the sidebar is mostly native
navigation with direct labels and monochrome system symbols. The goal is to
preserve Verbi's richer search and update discoverability while reducing
decorative chrome.

This plan changes presentation only. It must not remove sections, legacy
redirects, search results, update state, sidebar persistence, or keyboard and
VoiceOver semantics.

## Current state

The shell already uses the correct native container:

- Packages/MeetingAssistantCore/Sources/UI/pages/settings/SettingsPage.swift:21-68
  uses NavigationSplitView with a native sidebar, a 220-point ideal sidebar,
  a 900 × 640 minimum window, and SettingsWindowBackground.
- SettingsPage.swift:69-90 synchronizes sidebar visibility with the existing
  settings store and NavigationService.
- SettingsPage.swift:177-212 keeps all route destinations in the detail switch.

The sidebar gives search equal prominence to navigation:

- Packages/MeetingAssistantCore/Sources/UI/pages/settings/SettingsSidebarView.swift:15-37
  always renders SettingsSearchField before the section list.
- SettingsSidebarView.swift:39-55 renders the primary sections and System in a
  native List(selection:) with sidebar style.
- SettingsSidebarView.swift:111-145 renders each row with a 22-point custom
  rounded rectangle, a section-specific gradient, a white icon, and a filled
  icon only for selection.
- SettingsSidebarView.swift:147-180 repeats the colored badge treatment for
  search results.
- SettingsSidebarView.swift:119-125 correctly retains a small semantic update
  dot and includes the update message in the accessibility label at lines 63-68.

SettingsSection.swift contains more route cases than the visible sidebar:

- SettingsSection.swift:28-47 has legacy and visible cases.
- SettingsSection.swift:53-73 intentionally exposes only Activity, Modes,
  Meetings, History, Dictionary, and System.
- SettingsSection.swift:76-131 preserves legacy redirects.
- SettingsSection.swift:156-220 supplies icons, selected icon variants, badge
  colors, and gradients.

The search field is already compact at 30 points but its sidebar style adds a
filled background and rounded container:

- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsSearchField.swift:3-45.

Use AppTypography.sidebarLabel and the existing native List selection behavior.
Do not replace this with a new navigation model.

## Target behavior

After this plan lands:

- The sidebar remains a native NavigationSplitView/List with the same six
  visible routes and all existing legacy redirects.
- Normal rows use direct SF Symbols and text, with no per-section colored
  gradient badge.
- Selection is communicated by native List selection plus the existing filled
  symbol variant where useful; do not add a second colored selection plate.
- The update-available dot and its accessible text remain.
- Search remains available and fully functional, but its visual weight is
  secondary to the route list. A native compact placement is preferred only if
  it preserves the current result detail and destination callbacks.
- Search-result rows use the same quiet icon/text anatomy as normal rows.
- Inactive-window treatment remains legible and uses system opacity, not a
  second custom color system.
- The sidebar still works when collapsed/reopened, in Light/Dark appearance,
  with increased contrast, dynamic type, and VoiceOver.

Do not remove search merely to match VoiceInk. Verbi has enough routes and
legacy aliases that search is a legitimate product affordance.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | git diff --stat 51b0ac63..HEAD -- Packages/MeetingAssistantCore/Sources/UI/pages/settings/SettingsSidebarView.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsSection.swift Packages/MeetingAssistantCore/Sources/UI/pages/settings/SettingsPage.swift Packages/MeetingAssistantCore/Sources/UI/components/design-system/AppTypography.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsSearchField.swift | Empty, or reviewed as an explicit STOP condition |
| Search/routing tests | ./scripts/run-tests.sh --suite dev --file SettingsSearchIndexTests --file NavigationServiceTests | All selected tests pass |
| Preview declarations | make preview-check | Preview declaration coverage PASS |
| Swift lint | make lint | Exit 0 or the documented unchanged baseline |
| Technical lane | make validate-agent ARGS="--lane auto" | PASS or an exact baseline failure is recorded |

## Suggested executor toolkit

- apple-design for native sidebar hierarchy and system symbol treatment.
- swiftui-expert-skill for List(selection:), focus, and platform behavior.
- swiftui-accessibility-audit for labels, selected state, keyboard access, and
  increased-contrast review.
- swift-conventions for Swift source organization and formatting.

## Scope

**In scope** (the only files this plan should modify):

- Packages/MeetingAssistantCore/Sources/UI/pages/settings/SettingsSidebarView.swift
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsSection.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/SettingsPage.swift
- Packages/MeetingAssistantCore/Sources/UI/components/design-system/AppTypography.swift
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsSearchField.swift
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/SettingsSearchIndexTests.swift
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/NavigationServiceTests.swift

**Out of scope**:

- Changing visible route membership or legacy destination mapping.
- Changing persisted sidebar visibility keys or NavigationService behavior.
- Settings page content, Form/card composition, or material implementation;
  Plan 135 owns those changes.
- History, Activity, recorder, onboarding, or new settings features.
- Removing search or replacing it with a third-party navigation library.
- New localization keys unless an accessibility label is genuinely missing;
  reuse existing localized keys first.
- VoiceInk source/assets or a full VoiceInk sidebar copy.

## Git workflow

- Branch: simplify-settings-sidebar
- Commit style: refactor(ui): simplify Settings sidebar chrome
- Implementation worktrees follow core/policies/worktrees.md.
- Do not push or open a PR unless the operator instructs it.

## Steps

### Step 1: Inventory route and search invariants

Confirm the six visible sections, every legacy destination, the search index
result callback, update badge behavior, and persisted sidebar toggle path.
Search all callers of SettingsSection.badgeColor, badgeGradient,
selectedSidebarIcon, and sidebarIconBadge before deleting or renaming anything.

**Verify**: ./scripts/run-tests.sh --suite dev --file SettingsSearchIndexTests --file NavigationServiceTests → all selected tests pass before the visual change.

### Step 2: Replace decorative row badges with native icon anatomy

Update SettingsSidebarView so normal and search-result rows use the existing
AppTypography and a direct Image(systemName:) or Label-style layout. Remove
the per-row rounded gradient container and any now-unused ScaledMetric badge
state. Keep the row hit target, line limit, inactive opacity, selected
symbol behavior, update dot, accessibility label, and result detail.

If SettingsSection.badgeColor or badgeGradient has no remaining callers after
the change, remove those presentation-only properties. Keep route and title
properties even when a route is a legacy redirect.

**Verify**: rg -n "badgeGradient|badgeColor|sidebarIconBadge|sidebarBadgeSize|searchResultBadgeSize" Packages/MeetingAssistantCore/Sources/UI → only intentional compatibility references remain, or none remain.

### Step 3: Reduce search chrome without losing discoverability

Keep SettingsSearchField and the current SettingsSearchIndex behavior. Make its
sidebar presentation visually subordinate to the native List, using the
existing compact dimensions and shared surface contract from Plan 133. Do not
introduce a new search data flow. If a native searchable placement is tested,
preserve custom result titles, details, route selection, clearing behavior, and
the empty state; otherwise keep the compact field and reduce only its
container treatment.

**Verify**: ./scripts/run-tests.sh --suite dev --file SettingsSearchIndexTests → all search normalization, route, and destination tests pass.

### Step 4: Preserve shell geometry and accessibility states

Touch SettingsPage.swift only if the lighter sidebar requires a small native
spacing or column-width adjustment. Preserve the 900 × 640 minimum, titlebar
clearance, sidebar persistence, collapsed toggle, and detail switch. Do not
use a custom background or selection overlay to compensate for the removed
badges.

Inspect the sidebar in:

- selected and unselected rows;
- inactive app window;
- update-available System row;
- empty and populated search results;
- keyboard navigation and VoiceOver;
- Light/Dark, increased contrast, and dynamic type.

**Verify**: make preview-check && make lint → both pass.

### Step 5: Run the full changed-surface proof

Run the focused tests, then the technical lane. If user-facing copy or
localization keys changed, also run localization-check and confirm both
existing locales contain the key.

**Verify**: make validate-agent ARGS="--lane auto" → PASS or an exact
documented baseline failure.

## Test plan

- Reuse SettingsSearchIndexTests.swift as the structural pattern for route and
  search invariants.
- Keep coverage for normalization, every searchable-key route, legacy
  exceptions, history, metrics, permissions, and system subroutes.
- Keep NavigationServiceTests.swift coverage for history/updates requests and
  sidebar visibility/toggle state.
- Add a test only if a changed route or search behavior needs a new invariant;
  visual row anatomy is verified through previews/manual inspection.
- Manual acceptance must cover selected/unselected, update dot, inactive state,
  search empty/results, keyboard navigation, VoiceOver, Light/Dark, increased
  contrast, and dynamic type.

## Done criteria

- [ ] The six visible Settings routes and every legacy redirect are unchanged.
- [ ] Sidebar rows no longer use per-section gradient badge backgrounds.
- [ ] Search remains discoverable and its result/destination behavior is intact.
- [ ] Update availability remains visible and announced accessibly.
- [ ] Focused SettingsSearchIndexTests and NavigationServiceTests pass.
- [ ] make preview-check, make lint, and make validate-agent ARGS="--lane auto"
      pass or have exact baseline failures recorded.
- [ ] Manual inspection covers the required appearance and accessibility states.
- [ ] No files outside the in-scope list are modified.
- [ ] plans/README.md records implementation, review, integration, and main
      validation separately when this plan is executed.

## STOP conditions

Stop and report if:

- The live route inventory differs from SettingsSection.swift:53-131.
- Removing a badge requires changing route identity, localization keys, or
  persisted settings state.
- Native List selection cannot provide a visible/focusable selected state after
  the custom treatment is removed.
- Search results lose their detail, clear action, keyboard route, or accessible
  destination label.
- SettingsPage geometry must change by more than the existing sidebar width or
  titlebar clearance to make the result usable.
- A verification command fails twice after a reasonable, changed-hypothesis fix.
- The implementation requires touching settings content or shared surfaces
  owned by Plan 135.

## Maintenance notes

- Keep sidebar semantics native even if future sections are added.
- If a new status indicator is needed, prefer a semantic dot plus accessible
  text over another per-row color system.
- Do not reintroduce gradient badges to compensate for reduced visual weight;
  use selection, hierarchy, and spacing first.
- Plan 135 may change Settings page surface composition, but it must preserve
  this sidebar's routing and search contract.
