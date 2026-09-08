# Plan 136: Lighten transcription history with progressive disclosure

> **Executor instructions**: Follow this brief step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the STOP conditions section occurs, stop and
> report — do not improvise. When done, update the local status row in
> plans/README.md.
>
> **Drift check (run first)**:
> git diff --stat 51b0ac63..HEAD -- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/TranscriptionsSettingsTab.swift Packages/MeetingAssistantCore/Sources/UI/components/transcription/TranscriptionCardView.swift Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/TranscriptionConversationPage.swift Packages/MeetingAssistantCore/Sources/UI/Models/TranscriptionsNavigationHistory.swift
> If any in-scope file changed since this plan was written, compare the
> Current state excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH
- **Depends on**: 133-visual-surface-contract.md, 135-normalize-settings-surfaces.md
- **Category**: direction
- **Planned at**: commit 51b0ac63, 2026-09-04
- **Finding ID**: transcription-history-visual-density
- **Publication**: local
- **Parent issue**: none
- **Issue**: none
- **Integration**: isolated worktree → merge to local main only when the operator authorizes it; no push unless requested

## Execution profile

- **Recommended profile**: implementer
- **Risk/lane**: High/Full
- **Parallelizable**: no — list, card, detail route, and action handling form one stateful surface
- **Reviewer required**: yes — expansion, navigation, destructive actions, accessibility, and list performance must be reviewed together
- **Rationale**: History is the densest recurring surface in Verbi. Its current behavior is valuable, but the list exposes too many card treatments and secondary actions at once.
- **Escalate when**: The change requires a new persistence schema, a different transcription route model, deletion semantics, sync behavior, or a replacement for the existing conversation detail page.

## Why this matters

The current history page has the right capabilities but presents them with
high visual entropy: filters, date groups, cards, audio controls, title and
purpose editing, QA, prompt inspection, export, retry, reprocess, and delete
can all appear in the same expanded item. VoiceInk feels lighter because the
default list is a compact scan surface and secondary work appears only after
the user chooses an item.

This plan keeps the existing history behavior and makes the default state a
fast, quiet list. It reuses the current card, conversation page, action enum,
sync, localization, and performance coverage. It does not remove access to
transcript text, audio, QA, prompts, export, retry, reprocess, or deletion.

## Current state

The page already separates list and detail concerns, but the list is still
visually dense:

- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/TranscriptionsSettingsTab.swift:97-154
  renders the page header, description, search, source segmented control,
  date/app filters, and loading/error/empty states.
- TranscriptionsSettingsTab.swift:211-270 renders one List grouped by date,
  with a time column and TranscriptionCardView; selectedId drives expansion
  and AppleMotion controls disclosure.
- TranscriptionsSettingsTab.swift:272-287 already exposes
  TranscriptionConversationPage as a deeper detail route.
- TranscriptionsSettingsTab.swift:292-370 centralizes open, sync, title,
  purpose, copy, QA, reprocess, retry, delete, and export actions.

TranscriptionCardView currently supports the necessary progressive states, but
its expanded state exposes many controls at once:

- Packages/MeetingAssistantCore/Sources/UI/components/transcription/TranscriptionCardView.swift:9-51
  defines the expandable card model.
- TranscriptionCardView.swift:53-78 owns the expansion state and
  TranscriptionAction cases.
- TranscriptionCardView.swift:100-127 switches between a collapsed button and
  an expanded DSCard.
- TranscriptionCardView.swift:129-313 places audio, tab selection, title,
  transcript text, QA/info/prompt buttons, and an overflow menu in the expanded
  body.
- TranscriptionCardView.swift:390-407 already limits collapsed text and
  provides Show All/Show Less.
- TranscriptionCardView.swift:643-681 defines the compact row anatomy and
  TranscriptionCardView.swift:695-706 keeps the accessible collapse action.

The existing full detail surface is the correct place for deep reading:

- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/TranscriptionConversationPage.swift:42-121
  owns the conversation detail presentation and its route-level actions.
- Packages/MeetingAssistantCore/Sources/UI/Models/TranscriptionsNavigationHistory.swift:3-87
  models list/conversation navigation and has focused tests.
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/TranscriptionsNavigationHistoryTests.swift
  verifies the navigation history contract.
- TranscriptionHistoryPerformanceTests.swift already covers 50, 250, and
  1000-item datasets and should remain the regression baseline.

## Target behavior

After this plan lands:

- The first fold is a readable history scan: date/time, app or source,
  title/preview, and the primary status are visually obvious.
- One selected item can reveal useful inline context, but audio, QA, prompt,
  export, retry, reprocess, purpose, and delete remain behind the smallest
  appropriate disclosure or existing overflow menu.
- The existing conversation detail route remains the destination for deep
  transcript reading and review; the list does not duplicate the whole detail
  page.
- Search, source/date/app filters, date grouping, loading, error, empty, sync,
  failed transcription, processing, and selected states remain available and
  understandable.
- The existing DSCard and AppDesignSystem tokens are reused. Do not create a
  second history card style, a new navigation model, or decorative nested
  plates.
- Primary selection and focus remain visible without color alone. VoiceOver
  announces the item identity, expanded/collapsed state, and available primary
  action.
- List identity and lazy rendering remain stable for large datasets.
- User-facing text remains localized through existing keys. If a genuinely new
  label is needed, add both locale entries in the same scoped change and run
  localization-check.

The executor may choose whether the compact row opens inline or routes to the
existing conversation page first, provided the choice preserves current action
callbacks and does not make deep reading slower.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Drift | git diff --stat 51b0ac63..HEAD -- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/TranscriptionsSettingsTab.swift Packages/MeetingAssistantCore/Sources/UI/components/settings/TranscriptionCardView.swift Packages/MeetingAssistantCore/Sources/UI/pages/settings/TranscriptionConversationPage.swift Packages/MeetingAssistantCore/Sources/UI/pages/settings/TranscriptionsNavigationHistory.swift | Empty, or reviewed as an explicit STOP condition |
| History behavior | ./scripts/run-tests.sh --suite dev --file TranscriptionsNavigationHistoryTests --file TranscriptionHistoryPerformanceTests | Selected navigation and performance tests pass |
| Preview declarations | make preview-check | Preview declaration coverage PASS |
| Swift lint | make lint | Exit 0 or the documented unchanged baseline |
| Localization integrity | make localization-check | Required only when user-facing keys change; otherwise record not needed |
| Technical lane | make validate-agent ARGS="--lane auto" | PASS or an exact baseline failure is recorded |

## Suggested executor toolkit

- apple-design for native list hierarchy, disclosure, material, spacing, and
  macOS interaction behavior.
- swiftui-expert-skill for List identity, state ownership, navigation, and
  view invalidation.
- swiftui-accessibility-audit for expanded state, focus, labels, and keyboard
  access.
- swift-conventions for Swift organization and file size.
- testing-xctest and test-hygiene for focused state/performance verification.

## Scope

**In scope** (the only files this plan should modify):

- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/TranscriptionsSettingsTab.swift
- Packages/MeetingAssistantCore/Sources/UI/components/transcription/TranscriptionCardView.swift
- Packages/MeetingAssistantCore/Sources/UI/pages/settings/tabs/TranscriptionConversationPage.swift
- Packages/MeetingAssistantCore/Sources/UI/Models/TranscriptionsNavigationHistory.swift
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/TranscriptionsNavigationHistoryTests.swift
- Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/TranscriptionHistoryPerformanceTests.swift

**Out of scope**:

- New persistence fields, sync protocols, transcription processing behavior, or
  deletion semantics.
- Replacing the existing conversation detail route or navigation history model.
- Activity, Settings sidebar, recorder, onboarding, or shared design-system
  changes owned by Plans 134, 135, 137, and 138.
- A new search/filter architecture or a third-party list component.
- Removing QA, prompt, export, retry, reprocess, title, purpose, audio, or
  delete capabilities.
- VoiceInk source, assets, CloudKit behavior, or copied interaction code.

## Git workflow

- Branch: lighten-transcription-history
- Commit style: refactor(ui): lighten transcription history disclosure
- Implementation worktrees follow core/policies/worktrees.md.
- Do not push or open a PR unless the operator instructs it.

## Steps

### Step 1: Inventory history state and action reachability

Trace every TranscriptionAction case from TranscriptionCardView through the
TranscriptionsSettingsTab handler and into the conversation route. Record which
controls are available in collapsed, expanded, failed, processing, and detail
states. Confirm stable List identity and the current selectedId/openConversation
behavior before editing.

**Verify**: rg -n "TranscriptionAction|selectedId|openConversation|delete|reprocess|retry|export|viewPrompt|qa" Packages/MeetingAssistantCore/Sources/UI/pages/settings Packages/MeetingAssistantCore/Sources/UI/components/transcription → every existing action has one reachable destination.

### Step 2: Establish the compact scan hierarchy

Use the existing collapsed row as the default visual contract. Reduce competing
card treatment, title repetition, and always-visible secondary affordances while
keeping date grouping, time, app/source, title/preview, failure state, and
selection. Prefer existing DSCard/list tokens and delete redundant layers
before adding any new styling.

Do not hide the primary status or the action that opens the selected item.
Keep the hit target, keyboard focus, hover affordance, and accessible value
clear in both Light and Dark appearance.

**Verify**: make preview-check && make lint → both pass after the compact-row change.

### Step 3: Move secondary work behind progressive disclosure

Keep the existing expanded state or route boundary, but make it a deliberate
user choice. Place only the next useful context in the first reveal; keep the
existing overflow menu for copy, export, reprocess, retry, purpose, and delete
unless an action is currently required to recover a visible error. Preserve
audio playback, transcript text, Show All/Show Less, QA, prompt, and title
editing through the existing callbacks.

If the executor changes the default from inline expansion to the conversation
route, update TranscriptionsNavigationHistoryTests and retain the back/list
behavior. Do not introduce a second navigation stack.

**Verify**: ./scripts/run-tests.sh --suite dev --file TranscriptionsNavigationHistoryTests → route, back-navigation, and action reachability tests pass.

### Step 4: Recheck data states and large-list behavior

Inspect loading, empty, error, processing, failed, selected, and populated
states. Confirm date headers and filter results remain readable. Run the
existing 50/250/1000-item performance tests and verify that expansion does not
eagerly render every transcript or destabilize row identity.

**Verify**: ./scripts/run-tests.sh --suite dev --file TranscriptionHistoryPerformanceTests → all existing size tiers pass.

### Step 5: Validate accessibility and appearance

Manually inspect the list and detail route at 600, 900, and 1200 points in
Light/Dark appearance, dynamic type, increased contrast, Reduce Transparency,
and reduced motion when available. Check keyboard focus, VoiceOver expanded
state, menu labels, selection without color, and the destructive delete
confirmation. Record unavailable manual states instead of inferring them from
source.

**Verify**: make preview-check && make lint && make validate-agent ARGS="--lane auto" → applicable gates pass, with any baseline failure recorded separately.

## Test plan

- Preserve and extend TranscriptionsNavigationHistoryTests only for changed
  route/expansion invariants.
- Preserve the existing 50/250/1000 dataset performance coverage; do not
  replace it with a screenshot-only assertion.
- Add a focused test only if a state transition or action reachability rule is
  otherwise unprotected.
- Run localization-check when user-facing copy or localization keys change.
- Manual evidence must cover compact, expanded/detail, processing, failed,
  empty, error, selection, keyboard, VoiceOver, Light/Dark, dynamic type,
  increased contrast, Reduce Transparency, and reduced motion.

## Done criteria

- [ ] The history first fold is a compact scan surface with one clear primary
      action.
- [ ] Deep transcript reading and secondary actions remain reachable through
      the existing inline/detail and overflow paths.
- [ ] Search, filters, date groups, loading, empty, error, processing, failed,
      sync, and deletion behavior are unchanged.
- [ ] Navigation history and List identity remain correct.
- [ ] Navigation and performance tests pass.
- [ ] make preview-check, make lint, and make validate-agent ARGS="--lane auto"
      pass or have exact baseline failures recorded.
- [ ] Manual inspection covers the required appearance and accessibility states.
- [ ] No files outside the in-scope list are modified.
- [ ] plans/README.md records implementation, review, integration, and main
      validation separately when this plan is executed.

## STOP conditions

Stop and report if:

- The live history action graph or navigation model differs from the excerpts
  above.
- A proposed visual simplification removes or makes unreachable a current
  transcription, audio, QA, prompt, export, retry, reprocess, title, purpose,
  or delete capability.
- The compact treatment requires a new persistence field, sync contract, or
  destructive-action policy.
- Performance tests regress because every row begins rendering expanded detail.
- The existing List/route boundary cannot express the target without a new
  navigation stack.
- A required accessibility state cannot be inspected or represented.
- The command fails twice after a reasonable, changed-hypothesis fix attempt.
- Any product source outside this plan's allowlist appears necessary.

## Maintenance notes

- Keep the list as the scan surface and the conversation page as the deep
  reading surface.
- When adding a future history action, decide its disclosure level before
  placing it in the collapsed row.
- Do not add another card layer to solve a hierarchy problem; adjust the
  existing row, disclosure, or route.
