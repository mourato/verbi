# Plan 133: Establish the shared visual surface contract

> **Executor instructions**: Follow this brief step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the STOP conditions section occurs, stop and
> report — do not improvise. When done, update the local status row in
> plans/README.md.
>
> **Drift check (run first)**:
> git diff --stat 51b0ac63..HEAD -- docs/ui.md Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsPreviewEvidenceCatalog.swift
> If any in-scope file changed since this plan was written, compare the
> Current state excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit 51b0ac63, 2026-09-04
- **Finding ID**: shared-ui-surface-contract
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: isolated worktree → merge to local main only when the operator authorizes it; no push unless requested

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: Medium/Full
- **Parallelizable**: no — this is the contract and evidence prerequisite for Plans 134–138
- **Reviewer required**: yes — the contract controls every later visual change
- **Rationale**: The code change is limited to documentation and deterministic previews, but it establishes reusable platform and accessibility rules that later implementers must not reinterpret.
- **Escalate when**: The work requires changing production surfaces, adding a second design-system document, introducing new persistence/configuration, or resolving a product choice that is not covered by the current UI contract.

## Why this matters

VoiceInk feels lighter primarily because its surfaces follow a small number of
clear roles and reveal secondary detail progressively. Verbi already has
shared tokens and components, but the existing implementation can present
window chrome, material cards, grouped sections, drawers, and local overlays
with equal visual weight. This plan makes the roles and acceptance evidence
explicit before the surface-specific plans change code.

This is not a design-system rewrite and it does not attempt to copy VoiceInk.
The reference supplies a visual benchmark only; Verbi remains a native,
localized, accessible macOS application.

## Current state

The current UI contract already gives the correct direction:

- docs/ui.md:11-13 says the product should feel native, calm, and trustworthy
  while keeping recording, permissions, configuration, and processing state
  obvious.
- docs/ui.md:28-40 requires native semantics/materials, centralized
  AppDesignSystem tokens, semantic colors, an opaque Reduce Transparency
  fallback, no nested decorative plates, one semantic scroll owner, and the
  existing Settings hierarchy.
- docs/ui.md:42-51 makes focus, VoiceOver, Light/Dark, increased contrast,
  Reduce Transparency, and Reduce Motion part of the UI contract.
- docs/ui.md:88-97 requires reuse of shared components and visual inspection
  across the relevant accessibility states.

The existing deterministic evidence catalog is currently a route/state list,
not a surface-role matrix:

- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsPreviewEvidenceCatalog.swift:3-7
  describes synthetic routes that avoid production view models.
- The catalog at lines 18-47 lists Activity, Dictation, Modes, Meetings,
  Assistant, Integrations, and System states.
- Its previews at lines 73-90 cover 600-point light, 900-point dark, and
  1200-point accessibility/reduced-transparency settings content, but do not
  explicitly label the native Form, rich collection surface, sidebar, or
  transient drawer roles.

The project already has two intended scroll owners:

- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsFormPage.swift:3-30
  owns one native grouped Form and its vertical scrolling.
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsScrollableContent.swift:10-55
  owns one ScrollView for rich collection/status/analytics/editor pages and
  explicitly prohibits embedding a page Form inside it.

Use these existing patterns. Do not add a new token namespace or a parallel
DESIGN.md.

## Target behavior

After this plan lands, the contract and evidence catalog must make these roles
unambiguous:

| Surface role | Owner | Allowed visual weight | Typical content |
|---|---|---|---|
| Window canvas | SettingsWindowBackground | Native window material or opaque accessibility fallback | The Settings page background |
| Native settings form | SettingsFormPage and Form/Section | Lowest chrome; native row anatomy | Scalar preferences and drill-down rows |
| Rich collection surface | SettingsScrollableContent plus a shared collection/list treatment | One restrained grouping treatment | History, analytics, status blocks, editors |
| Transient editor surface | SettingsSidePanel or ModeEditorDrawer | Clearly bounded panel with its own header/footer | Mode and advanced editors |
| Status/recording overlay | Existing AppDesignSystem recording tokens | High semantic contrast only when state demands it | Recording, processing, error, confirmation |

The contract must also state:

- lightness means fewer competing surface layers and a clear first action, not
  lower contrast or less accessible information;
- color is reserved for selection, status, and semantic emphasis;
- secondary actions belong behind disclosure/menu/detail when they are not
  required for the primary task;
- all user-facing copy remains localized with existing .localized keys;
- no reference-app source, assets, or persistence behavior is copied.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | git diff --stat 51b0ac63..HEAD -- docs/ui.md Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsPreviewEvidenceCatalog.swift | Empty, or reviewed as an explicit STOP condition |
| Preview declarations | make preview-check | Preview declaration coverage PASS |
| Swift lint | make lint | Exit 0 or the repository's documented unchanged baseline |
| Guidance and localization | make guidance-check | Exit 0 when docs or localized preview copy changes |
| Technical lane | make validate-agent ARGS="--lane auto" | PASS for the changed preview source, or a documented baseline failure |

Rendered preview inspection is manual. The preview checker verifies declarations
only; it does not compile or render previews.

## Suggested executor toolkit

- apple-design for native macOS materials, hierarchy, appearance, and motion.
- swiftui-expert-skill for SwiftUI preview composition and view invalidation.
- swiftui-accessibility-audit for the state/accessibility matrix.
- swift-conventions for Swift formatting and source organization.

## Scope

**In scope** (the only files this plan should modify):

- docs/ui.md
- Packages/MeetingAssistantCore/Sources/UI/components/settings/SettingsPreviewEvidenceCatalog.swift

**Out of scope**:

- AppDesignSystem.swift and shared component implementation; Plan 135 owns
  the implementation normalization after this contract is accepted.
- SettingsSidebarView.swift; Plan 134 owns navigation chrome.
- TranscriptionsSettingsTab.swift and TranscriptionCardView.swift; Plan 136
  owns history density and disclosure.
- MetricsDashboardPages.swift and MetricsDashboardComponents.swift; Plan 137
  owns Activity hierarchy.
- FloatingRecordingIndicator*; Plan 138 owns recorder hierarchy.
- New localization keys, settings preferences, persistence, or telemetry.
- VoiceInk source, assets, CloudKit behavior, or visual copying.

## Git workflow

- Branch: establish-ui-surface-contract
- Commit style: docs(ui): establish shared visual surface contract
- Implementation worktrees follow core/policies/worktrees.md.
- Do not push or open a PR unless the operator instructs it.

## Steps

### Step 1: Reconfirm the existing surface inventory

Read docs/ui.md, SettingsFormPage.swift, SettingsScrollableContent.swift,
SettingsWindowBackground.swift, SettingsSidePanel.swift, ModeEditorDrawer.swift,
and the current SettingsPreviewEvidenceCatalog.swift. Classify each surface
role using the target contract above. Record any mismatch in the plan's
implementation notes or report it as a STOP condition; do not silently create a
new role.

**Verify**: rg -n "SettingsFormPage|SettingsScrollableContent|SettingsWindowBackground|SettingsSidePanel|ModeEditorDrawer|DSCard|DSGroup" Packages/MeetingAssistantCore/Sources/UI → every existing owner is classified.

### Step 2: Reconcile docs/ui.md with the reusable contract

Update the existing Principles and invariants and Review checklist sections
only where necessary to express the surface-role table and the definition of
lightness. Keep the existing product intent, accessibility, motion, reminder
overlay, and meeting-notes rules intact. Do not create a second design-system
document or turn docs/ui.md into a task log.

If the code and the contract disagree, document the live behavior and the
smallest next implementation seam; do not claim the contract is already
implemented.

**Verify**: rg -n "surface|scroll owner|nested|progressive|VoiceInk|Reduce Transparency|Reduce Motion" docs/ui.md → the reusable rules are present and no source-copy instruction is added.

### Step 3: Extend deterministic preview evidence

Update SettingsPreviewEvidenceCatalog.swift so its synthetic catalog explicitly
covers the surface roles: native Form, rich collection/list, transient drawer,
sidebar/navigation chrome, and accessibility/reduced-transparency states. Keep
the catalog view-model-free and deterministic. Reuse localized keys or static
labels that do not create product copy dependencies.

Every new visual example must remain a preview fixture, not a production
component. Preserve the existing 600, 900, and 1200-point previews and add only
the smallest missing role/state examples.

**Verify**: make preview-check → Preview declaration coverage PASS.

### Step 4: Inspect the evidence matrix and close out

Manually inspect the available previews at:

- 600 × 640 light appearance;
- 900 × 640 dark appearance;
- 1200 × 720 with accessibility dynamic type and Reduce Transparency;
- at least one reduced-motion/increased-contrast environment when the preview
  host supports it.

Confirm that the catalog makes the first content hierarchy legible without
using color alone. Record unavailable manual checks rather than inferring
rendered behavior from source.

**Verify**: make lint && make guidance-check && make validate-agent ARGS="--lane auto" → all applicable gates pass, with any baseline failure recorded separately.

## Test plan

- No new domain behavior or persistence tests are required.
- Preview declaration coverage must remain complete for the changed SwiftUI
  catalog.
- Manual evidence must cover Light/Dark, 600/900/1200 widths, dynamic type,
  Reduce Transparency, increased contrast, and reduced motion when available.
- If the preview catalog introduces a localized key, run localization-check
  and add the key in both existing locales in a separate, explicitly reviewed
  scope; prefer avoiding new keys in this plan.

## Done criteria

- [ ] docs/ui.md contains one surface-role contract and the lightness definition.
- [ ] SettingsPreviewEvidenceCatalog.swift covers the five surface roles and
      the existing accessibility states without production view-model coupling.
- [ ] make preview-check passes.
- [ ] make lint and make guidance-check pass, or unchanged baseline failures are
      recorded.
- [ ] make validate-agent ARGS="--lane auto" passes or its exact baseline failure
      is documented.
- [ ] Manual preview evidence records inspected widths, appearance, and
      accessibility settings.
- [ ] No files outside the in-scope list are modified.
- [ ] plans/README.md records implementation, review, integration, and main
      validation separately when this plan is executed.

## STOP conditions

Stop and report if:

- docs/ui.md or the preview catalog has drifted from the excerpts above.
- The requested contract requires a new design-system document or a broad token
  rewrite.
- A surface role cannot be expressed using the existing Form, ScrollView,
  List, material, or panel owners without changing product behavior.
- The preview host cannot render a required state and no source-independent
  evidence path exists; record it instead of claiming visual validation.
- The command fails twice after a reasonable, changed-hypothesis fix attempt.
- Any product source outside this plan's allowlist appears necessary.

## Maintenance notes

- Plans 134–138 must consume this contract instead of adding per-screen surface
  variants.
- The reviewer should reject a visually lighter result that removes labels,
  keyboard access, VoiceOver information, or state feedback.
- Keep the reference-app comparison as design rationale only; do not introduce
  a runtime dependency on the local VoiceInk checkout.
- If the project later introduces a new modal/panel role, update this contract
  and add evidence before adding another visual treatment.
