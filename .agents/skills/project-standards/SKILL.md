---
name: project-standards
description: This skill should be used when the user asks to "update AGENTS.md", "document project policy", "track known limitations", or "align repository standards".
---

# Project Operational Standards

## Role

Canonical owner for AGENTS alignment and project guidance governance in Verbi.

## Scope Boundary

Use for AGENTS maintenance, policy updates, and repository standards. Delegate agent-facing prose mechanics to global `writing-for-agents`.

## When to Use

Use for AGENTS maintenance, project policy updates, and repository guidance governance in Verbi.

## Project specifics

Limitations: register known limitations and intentional trade-offs as GitHub issues with `gh` and the `known-limitation` label; no `KNOWN_LIMITATIONS.md`; each issue states context, impact, and acceptance criteria.

Ownership: `agent-ops` owns orchestration and profiles; `delivery-workflow` owns risk, lanes, commands, and evidence; domain skills own implementation rules; `thermo-nuclear-code-quality-review` owns findings, severity, semáforo, and the strict structural bar. Routers route and do not duplicate deep rules or merge-gate policy.

Routing: keep `.agents/docs/skill-routing.md` as the canonical skill-to-agent map; keep model, reasoning, sandbox, and MCP choices in `~/.codex/agents/`, not project skills.

Keep synchronized: `reuse -> extend -> create` between `AGENTS.md` and affected skills; compact-mode commands, logs, and output contracts when scripts change; design tokens and components in `AGENTS.md`/skills; `SettingsDrillDownListRow` and the `EnhancementsSettingsPage` drill-down pattern for secondary settings pages; preview guidance in `macos-ui`; the `Common`, `Domain`, `Infrastructure`, `Data`, `Audio`, `AI`, `UI`, `Core` module split; path validity after moves; `VerbiCore*` imports vs PascalCase source folders; colocated type directories with unique basenames instead of `Type+Concern.swift`; Makefile/script renames in `AGENTS.md`, README, and skills in the same PR; `modelResidencyTimeout` with a registry entry and unload hook for every local model.

Information routing: absorb reusable guidance into `.agents/skills/`; file backlog and limitations as GitHub issues; delete stale duplicates. Do not create root `docs/` files; keep durable policy in `AGENTS.md`/skills, pending work in issues, and generated reports in `/tmp` or `.agents/reports/`.

Evolution: review guidance every 90 days and when tooling, targets, scripts, boundaries, or the skill registry change. Report unclear guidance as `agents-guidance-unclear`; use `known-limitation` or `needs-review` for pending work. Update `AGENTS.md`, the owning skill, and referenced docs in the same change.

Language: documentation and code comments are English.

## Follows global writing-for-agents

Agent-facing prose rules, pointer design, and skill mechanics come from global `writing-for-agents`.

Related: `../documentation/SKILL.md`, `../delivery-workflow/SKILL.md`.
