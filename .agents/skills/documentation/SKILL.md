---
name: documentation
description: This skill should be used when the user asks to "write/update documentation", "add DocC comments", "improve MARK organization", or "research API docs".
---

# Documentation Standards

## Role

Canonical owner for DocC, code-comment conventions, and documentation research order in Verbi.

## Scope Boundary

Use for documentation and DocC work. Delegate project policy and AGENTS maintenance to `../project-standards/SKILL.md`.

## When to Use

Use for writing or refining Verbi documentation, DocC comments, and code-comment organization.

## Project specifics

- Source code carries no comments, including `///` doc comments and `// MARK:` labels; the `no_comments` lint rule enforces this. Let names, types, and file structure explain the code.
- Record a non-obvious constraint in [docs/CODE_CONSTRAINTS.md](../../../docs/CODE_CONSTRAINTS.md) and a workaround in a GitHub issue.
- Keep repository docs and `AGENTS.md` current as architecture evolves.
- Track known limitations and technical debt in GitHub issues with the `known-limitation` label, not in root `docs/` files.
- Research order: official vendor docs, repository-local guidance, official SDK source, then web lookup.
- Keep documentation in English.

Reference example: `Packages/VerbiCore/Sources/Domain/Models/CaptureSession.swift`.

## Follows global technical-writing

Human-doc structure, clarity, audience, and revision method come from global `technical-writing`. Keep Verbi DocC conventions and issue-tracking policy.

Related: `../project-standards/SKILL.md`.
