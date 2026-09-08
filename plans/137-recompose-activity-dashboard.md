# Plan 137: Recompose Activity around a clear first-fold story

> **Executor instructions**: Follow this brief step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the STOP conditions section occurs, stop and
> report — do not improvise. When done, update the local status row in
> plans/README.md.
>
> **Drift check (run first)**:
> git diff --stat 51b0ac63..HEAD -- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/MetricsDashboardPages.swift Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/MetricsDashboardComponents.swift Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/MetricsDashboardSupport.swift Packages/MeetingAssistantCore/Sources/UI/ViewModels/MetricsDashboardViewModel.swift Packages/MeetingAssistantCore/Sources/Domain/Utilities/MetricsAggregator.swift
> If any in-scope file changed since this plan was written, compare the
> Current state excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: 133-visual-surface-contract.md, 135-normalize-settings-surfaces.md
- **Category**: direction
- **Planned at**: commit 51b0ac63, 2026-09-04
- **Finding ID**: activity-first-fold-hierarchy
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: isolated worktree → merge to local main only when the operator authorizes it; no push unless requested

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: Medium/Full
- **Parallelizable**: no — Activity root, summary cards, heatmap, upcoming events, and navigation links must share one hierarchy
- **Reviewer required**: yes — metric meaning, permission/empty states, accessibility, and visual order need one review
- **Rationale**: The Activity page already has useful data and a separate summary component, but the root view leads with a heatmap and navigation links instead of the user's most useful current signal.
- **Escalate when**: A new metric source, persistence change, calendar permission flow, analytics query, or route model is required.

## Why this matters

Verbi's Activity implementation is not missing information; it makes the
user assemble the story. The root page starts with a heatmap, then links to
more insights and upcoming calendar, while the existing four-card summary is
only shown in More Insights. VoiceInk feels more finished because the primary
screen establishes one obvious focal hierarchy before exposing secondary
exploration.

This plan reuses the already-computed MetricsDashboardSummary and the existing
MetricStatCard, heatmap, upcoming-calendar, filter, loading, and permission
components. It changes composition and disclosure, not analytics semantics.

## Current state

The route pages currently repeat a broad overview without a focal summary:

- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/MetricsDashboardPages.swift:7-62
  defines MetricsDashboardIndexPage with a heading, subtitle, heatmap, explore
  links, and upcoming calendar.
- MetricsDashboardPages.swift:64-132 defines ActivityDashboardRootPage with
  the same header/subtitle, then heatmap at lines 89-98, explore links at
  lines 100-118, and upcoming calendar at lines 120-129.
- MetricsDashboardPages.swift:134-160 defines More Insights with filters and
  MetricsDashboardSummarySection.

The missing first-fold summary is already implemented:

- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/MetricsDashboardComponents.swift:421-460
  defines MetricStatCard using DSCard and a tinted semantic icon.
- MetricsDashboardPages.swift:365-433 defines MetricsDashboardSummarySection
  with sessions, words, WPM, and keystrokes. It currently appears in More
  Insights at line 153 rather than Activity root.
- MetricsDashboardViewModel publishes summary, events, loading, and permission
  state; MetricsAggregator.MetricsDashboardSummary already includes sessions,
  words, recorded/estimated duration, time saved, keystrokes, and WPM.
- MetricsDashboardSupport.swift:34-67 already formats duration and related
  values.

The rest of the supporting surface is reusable:

- MetricsDashboardComponents.swift:8-63 owns upcoming calendar loading,
  permission, empty, and event rows.
- MetricsDashboardComponents.swift:82-109 owns the heatmap.
- MetricsDashboardComponents.swift:321-334 owns filters.
- MetricsDashboardComponents.swift:336-419 owns upcoming event rows and their
  primary/detail/ignore actions.
- Existing localized keys include metrics.hero.title, metrics.hero.subtitle,
  metrics.summary.time_saved, metrics.summary.sessions_recorded,
  metrics.summary.words_dictated, metrics.summary.wpm, and
  metrics.summary.keystrokes in the current English and Portuguese catalogs.

## Target behavior

After this plan lands:

- Activity opens with one short hero and the existing summary cards as the
  first useful signal, using the same four metrics and meanings already
  exposed in More Insights.
- Heatmap remains the visual trend context immediately after the summary; it
  does not compete with the hero or become a decorative full-screen graphic.
- Explore links and upcoming calendar remain discoverable but are visually
  secondary and appear after the current-state summary/trend.
- Loading, no-data, calendar permission, empty, and error states explain what
  is unavailable without showing a misleading zero or empty hero.
- More Insights keeps filters and its filtered summary behavior. Do not remove
  a route or duplicate a second analytics data source just to change order.
- One SettingsScrollableContent remains the semantic scroll owner. Reuse
  MetricStatCard, existing spacing, and existing semantic colors; do not add a
  dashboard-specific card system.
- Metrics retain labels, localized copy, dynamic type, contrast, focus, and
  VoiceOver value/label semantics.

The executor may choose whether the summary is a compact horizontal strip,
adaptive grid, or a single-column stack at narrow widths. The invariant is
that the first fold states the current Activity story before secondary
navigation.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | git diff --stat 51b0ac63..HEAD -- Packages/MeetingAssistantCore/Sources/UI/pages/settings/MetricsDashboardPages.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/MetricsDashboardComponents.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/MetricsDashboardSupport.swift Packages/MeetingAssistantCore/Sources/UI/viewmodels/MetricsDashboardViewModel.swift Packages/MeetingAssistantCore/Sources/UI/viewmodels/MetricsAggregator.swift | Empty, or reviewed as an explicit STOP condition |
| Activity behavior | ./scripts/run-tests.sh --suite dev --file MetricsDashboardViewModelTests --file MetricsDashboardNavigationTests | Selected dashboard and navigation tests pass |
| Preview declarations | make preview-check | Preview declaration coverage PASS |
| Swift lint | make lint | Exit 0 or the documented unchanged baseline |
| Localization integrity | make localization-check | Required only when user-facing keys change; otherwise record not needed |
| Technical lane | make validate-agent ARGS="--lane auto" | PASS or an exact baseline failure is recorded |

## Suggested executor toolkit

- apple-design for native macOS hierarchy, spacing, material, and appearance.
- swiftui-expert-skill for adaptive layout, scroll ownership, and state
  composition.
- swiftui-accessibility-audit for metric semantics, focus, dynamic type, and
  loading/empty announcements.
- swift-conventions for Swift organization and formatting.
- testing-xctest and test-hygiene for focused dashboard and UI-state checks.

## Scope

**In scope** (the only files this plan should modify):

- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/MetricsDashboardPages.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/MetricsDashboardComponents.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/MetricsDashboardSupport.swift
- Packages/MeetingAssistantCore/Sources/UI/ViewModels/MetricsDashboardViewModel.swift
- Packages/MeetingAssistantCore/Sources/Domain/Utilities/MetricsAggregator.swift
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/MetricsDashboardViewModelTests.swift
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/MetricsDashboardNavigationTests.swift

**Out of scope**:

- New analytics fields, database queries, calendar providers, or persistence.
- Changing metric definitions, time windows, permission semantics, or event
  action behavior.
- Settings sidebar, generic design-system, transcription history, recorder,
  onboarding, or third-party chart changes owned by Plans 134, 135, 136, and
  138.
- New localization keys unless a missing accessibility or state label is
  demonstrated; reuse existing metrics keys first.
- Copying VoiceInk source, assets, or CloudKit behavior.

## Git workflow

- Branch: recompose-activity-dashboard
- Commit style: refactor(ui): recompose Activity dashboard hierarchy
- Implementation worktrees follow core/policies/worktrees.md.
- Do not push or open a PR unless the operator instructs it.

## Steps

### Step 1: Inventory the existing summary and state contract

Trace ActivityDashboardRootPage, MetricsDashboardIndexPage, More Insights,
MetricsDashboardSummarySection, MetricStatCard, the view model state, and
navigation callbacks. Confirm which summary values are available during
loading, no-data, permission, and error states. Do not invent a metric or
reinterpret an existing one.

**Verify**: rg -n "ActivityDashboardRootPage|MetricsDashboardIndexPage|MetricsDashboardSummarySection|MetricStatCard|summary|upcoming|heatmap" Packages/MeetingAssistantCore/Sources/UI Packages/MeetingAssistantCore/Sources/Domain Packages/MeetingAssistantCore/Tests → every displayed value has an existing owner and test seam.

### Step 2: Move the focal summary into Activity composition

Compose Activity with the existing summary section before heatmap and
secondary exploration. Keep the hero title/subtitle concise and localized.
Reuse MetricStatCard and AppDesignSystem spacing; do not add a new dashboard
container, gradient, chart, or data request.

Adapt the summary layout for narrow, normal, and wide widths using the least
complex existing SwiftUI layout that preserves readable labels and values.
Avoid a horizontal strip that truncates under dynamic type.

**Verify**: make preview-check && make lint → both pass after composition changes.

### Step 3: Keep trends and secondary actions progressive

Retain the heatmap as trend context, followed by existing Explore links and
upcoming calendar content. Preserve all More Insights filters and route
destinations. If the summary appears in both root and filtered insights, make
the distinction explicit through existing headings/state rather than adding
duplicated explanatory copy.

Keep calendar loading, permission, empty, and event actions intact. Do not
show a misleading upcoming section or metric card when its source state is
unavailable.

**Verify**: ./scripts/run-tests.sh --suite dev --file MetricsDashboardViewModelTests --file MetricsDashboardNavigationTests → summary, loading, permissions, routes, and navigation tests pass.

### Step 4: Validate visual and accessibility states

Inspect Activity at 600, 900, and 1200 points in Light/Dark appearance,
dynamic type, increased contrast, Reduce Transparency, and reduced motion when
available. Check loading, no recorded sessions, populated summary, no calendar
permission, empty calendar, and populated calendar. Confirm every metric is
readable and VoiceOver exposes label, value, and unit without relying on color.

**Verify**: make preview-check → declarations pass, followed by documented manual evidence.

### Step 5: Run the final technical lane

Run focused dashboard tests, then lint and the technical lane. Run
localization-check if copy or keys changed. Record any unchanged baseline
failure separately from a plan regression.

**Verify**: make validate-agent ARGS="--lane auto" → PASS or an exact documented baseline failure.

## Test plan

- Preserve MetricsDashboardViewModelTests coverage for summary, loading,
  calendar permission, empty, and event states.
- Preserve MetricsDashboardNavigationTests coverage for Activity, More
  Insights, Explore links, and existing route destinations.
- Add only a focused composition/state test if a new invariant cannot be
  covered through current view-model or navigation seams.
- Run localization-check when user-visible copy changes.
- Manual evidence must cover widths, appearance, dynamic type, increased
  contrast, Reduce Transparency, reduced motion, loading, no-data, permission,
  empty calendar, populated calendar, and VoiceOver metric semantics.

## Done criteria

- [ ] Activity leads with the existing summary metrics and one clear current
      story before heatmap/exploration.
- [ ] Heatmap, Explore links, upcoming calendar, and More Insights remain
      reachable and behaviorally unchanged.
- [ ] No new metric source, chart library, persistence, or dashboard card
      system was introduced.
- [ ] Loading, no-data, permission, empty, and error states are honest and
      readable.
- [ ] Focused dashboard and navigation tests pass.
- [ ] make preview-check, make lint, and make validate-agent ARGS="--lane auto"
      pass or have exact baseline failures recorded.
- [ ] Manual inspection covers the required appearance and accessibility states.
- [ ] No files outside the in-scope list are modified.
- [ ] plans/README.md records implementation, review, integration, and main
      validation separately when this plan is executed.

## STOP conditions

Stop and report if:

- The live summary fields, route graph, or state model differs from the
  excerpts above.
- A first-fold hierarchy requires new analytics, persistence, calendar, or
  permission behavior.
- A metric cannot be shown without changing its existing definition or making
  a loading/no-data state misleading.
- The adaptive summary truncates labels/values or loses keyboard/VoiceOver
  semantics at supported sizes.
- The change would require replacing the existing heatmap or chart library.
- A required visual/accessibility state cannot be inspected or represented.
- The command fails twice after a reasonable, changed-hypothesis fix attempt.
- Any product source outside this plan's allowlist appears necessary.

## Maintenance notes

- Keep Activity's first fold about current recording value; keep deeper
  filtering and exploration in More Insights.
- Reuse MetricStatCard for future summary additions until a real semantic role
  requires a different component.
- Do not solve a hierarchy problem by adding gradients, shadows, or another
  dashboard card layer.
