# ADR 003: Flat metric cells — no nested cards in Settings

**Status:** Accepted  
**Date:** 2026-09-06  
**Accepted:** 2026-09-06

## Context

Activity’s first-fold summary rendered four `MetricStatCard` tiles, each wrapped
in `DSCard` (`.standard` opaque fill), inside a native `Form`/`Section` plate.
That produced card-inside-card chrome and solid fills that competed with
`SettingsWindowBackground` materials.

`docs/ui.md` already required one owning surface role and forbade stacking
decorative plates on the window canvas. The Activity grid was a concrete
regression against that rule.

## Decision

1. **One owning surface** groups a metric summary: either a native
   `Form`/`Section` (Activity first fold) or a single `DSGroup` (More Insights
   on `SettingsScrollableContent`).
2. **Children are flat cells** (`MetricStatCard` without `DSCard`): icon well +
   title / value / detail, separated by grid spacing only.
3. **Document the invariant** in `docs/ui.md` so future analytics and status
   grids reuse the same composition instead of reintroducing nested plates.

## Consequences

- Activity and More Insights keep a readable 2×2 (or 1×4 wide) summary without
  opaque tile plates.
- More Insights wraps the shared summary section once in `DSGroup` so the grid
  still has a grouping surface when it is not inside a Form section.
- Designers and agents treat nested `DSCard`/`DSGroup` inside another plate as a
  contract violation, not a polish option.

## Rejected or deferred

- **Material tiles inside the section** — still nested plates; only softens the
  opacity problem.
- **Hero metric + secondary row** — valid hierarchy alternative; deferred unless
  product wants stronger emphasis on one number.
- **Hairline cell dividers** — optional later if spacing alone feels too loose;
  not required for the invariant.

## Affected surfaces

- `MetricStatCard` / `MetricsDashboardSummarySection` (Activity, More Insights)
- Settings analytics or status grids that might copy this pattern
- `docs/ui.md` nested-cards invariant
