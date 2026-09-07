---
name: project-standards
description: This skill should be used when the user asks to "update AGENTS.md", "document project policy", "track known limitations", or "align repository standards".
---

# Project Operational Standards

## Role

Use this skill as the canonical owner for project-level guidance governance in Prisma.

- Own AGENTS alignment, documentation policy, and information-routing standards.
- Keep project guidance synchronized with current tools, scripts, and skill ownership.
- Keep skill-authoring mechanics aligned with the current local skill structure.

## Scope Boundary

- Use this skill for AGENTS maintenance, policy updates, and repository standards.
- Keep individual skill structure changes focused and validated with `make guidance-check`.

## When to Use

Use this skill when the user asks to update AGENTS, document project policy, track known limitations, or align repository standards.

## Overview

Guidelines for maintaining consistent project documentation and visibility into technical constraints.

## 1. Limitation Tracking

- **Track in GitHub Issues**: Register known limitations and intentional trade-offs as GitHub issues (use `gh`) with the `known-limitation` label.
- **Avoid markdown backlog files**: Do not maintain a standalone `KNOWN_LIMITATIONS.md` file.
- **Issue quality**: Each issue should include context, impact, and a clear future direction/acceptance criteria.

## 2. Agent Documentation

- **Living Guidance**: Ensure `AGENTS.md` reflects the current state of tools, scripts, and skills.
- **Skill Template Standard**: Prefer a consistent section order in `SKILL.md`: `Role`, `Scope Boundary`, `When to Use`, domain-specific workflow/guidance, `Verification` when relevant, `Related Skills`, and `References`.
- **Workflow Ownership Split**: `agent-ops` owns orchestration/profile selection; `delivery-workflow` owns Prisma risk, lanes, commands, and evidence; domain skills own implementation rules; `thermo-nuclear-code-quality-review` owns review findings, severity framing, semaforo output, and strict structural maintainability.
- **Router Boundaries**: Router skills should route quickly and delegate; they should not duplicate deep implementation rules, merge-gate policy, or review format already owned elsewhere.
<<<<<<< HEAD
- **Global Skill Overlays**: Global skills may load the repository-local companion named by `AGENTS.md` under `.agents/overlays/`. Load the global skill first and the matching overlay second; the overlay is not a same-name replacement and may add only Prisma/Vozinha paths, commands, platform facts, permissions, invariants, or validation. Keep generic workflow and global safety rules in the global skill.
=======
- **Delegation Routing**: Keep `.agents/docs/skill-routing.md` as the project-specific mapping from canonical skills to global custom agents. Do not hardcode model identifiers in project skills; keep model, reasoning, sandbox, and MCP choices in `~/.codex/agents/`.
>>>>>>> chore/agent-orchestration
- **Reusable Blocks Policy**: Keep the `reuse -> extend -> create` rule synchronized between `AGENTS.md` and affected implementation skills.
- **Compact Execution Mode**: When script execution modes change (for example `*-agent` targets), update `AGENTS.md` and relevant skills with command usage, log locations, and output contracts.
- **Design System Guidance**: Keep the UI Design System tokens/components documented (and referenced from `AGENTS.md` / relevant skills).
- **Settings Navigation Pattern**: Keep `SettingsDrillDownListRow` documented as the canonical component for settings rows that open secondary pages; new push-style links should reuse the `EnhancementsSettingsTab` drill-down pattern before introducing a new wrapper.
- **Preview Standard**: Keep preview-related guidance centralized in `macos-app-engineering`.
- **Clean Registry**: Periodically audit `.agents/skills` to remove stale or redundant guidance.
- **Redundancy Audit**: Periodically audit repeated UI/logic guidance and consolidate duplicate instructions into reusable skill sections.
- **B2 Module Awareness**: Keep docs aligned with the current module split (`Common`, `Domain`, `Infrastructure`, `Data`, `Audio`, `AI`, `UI`, compatibility `Core`).
- **Path Validity**: After file moves between modules, update all documentation links and examples to the new canonical paths.
- **Source Layout Standard**: Keep filesystem paths and public module names distinct in docs. Public imports stay `MeetingAssistantCore*`; physical source folders use short PascalCase names under `Packages/MeetingAssistantCore/Sources/`.
- **Split File Naming**: Document and enforce colocated type directories such as `Services/RecordingManager/RecordingManager.swift` plus unique sibling basenames like `RecordingManagerRetry.swift`, `RecordingManagerPermissions.swift`, and similar companions. Do not reintroduce `Type+Concern.swift`.
- **Command Surface Sync**: When Makefile/script targets are renamed or removed, update `AGENTS.md`, README, and affected skills/docs in the same PR to avoid stale guidance.
- **Local Model Residency Coverage**: Keep `modelResidencyTimeout` documented as a mandatory global policy for every local model runtime. When adding a new local transcription model, require explicit residency registration and unload hooks so timeout-based RAM release always applies.

## 3. Information Routing (No Root `docs/`)

Route new knowledge using this order:

1. **Skill absorption** (`.agents/skills/...`) for reusable operational guidance.
2. **GitHub issue** (`gh issue create`) for backlog items, known limitations, and follow-up work.
3. **Deletion** for stale or duplicate files with no current operational value.

Rules:

- Do not create new documentation files under root `docs/`.
- Keep durable project policy in `AGENTS.md` or skills.
- Keep pending work in GitHub issues instead of markdown backlog files.
- For generated report artifacts, prefer `/tmp` or `.agents/reports/`.

## 4. Consistency

- **Commit Messages**: Enforce Conventional Commits consistently to ensure a readable history.
- **Branch Workflow**: Use at most one writer in an explicitly isolated worktree and preserve unrelated worktree changes.
- **UI Quality Gate**: Run `make preview-check` when UI views are added/changed.

## 5. Evolution and Ownership

- Review project guidance at least every 90 days and whenever the Codex model/tooling, Makefile targets, scripts, module boundaries, or skill registry changes.
- When guidance is unclear, report it as `agents-guidance-unclear`; when work or debt is pending, use `known-limitation` or `needs-review` as appropriate.
- When a command, module boundary, skill owner, or validation rule changes, update `AGENTS.md`, the owning skill, and referenced docs in the same change.
- Prefer deleting stale or duplicated guidance over adding another parallel policy. Keep one canonical owner for each rule and record intentional exceptions with scope, impact, rollback, and review date.

## 6. Language

- All documentation must be written in **English**.
- All code comments must be written in **English**.

## Related Skills

- `../documentation/SKILL.md`

## References

- `AGENTS.md`
