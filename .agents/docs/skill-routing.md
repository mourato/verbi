# Skill Routing Guide

When working on Prisma, multiple skills may be relevant to a task. This guide provides routing logic that keeps one canonical owner per domain and avoids instruction overlap.

## General Routing Priority

When uncertain which skill to use, apply this priority order:

1. **Global `agent-ops`** — orchestration and custom-agent profile selection
2. **`delivery-workflow`** — Prisma risk lane, validation, Git, and delivery evidence
3. **`macos-app-engineering`** — canonical macOS UI/app implementation guidance (includes SwiftUI review appendix)
4. **`apple-design` / `swiftui-accessibility-audit` / `localization`** — specialist UI escalation when their scope is primary
5. **`swift-concurrency-expert`** — Swift 6.2 concurrency remediation
6. **`debugging-diagnostics`** — cross-cutting investigation and diagnostic signal design when the failing subsystem is not yet proven

## External Project Code Lookup Priority

When inspecting code outside this repository, use this source order:

1. `MCP grep`
2. `gh` CLI
3. `deepwiki`
4. Web search

<<<<<<< HEAD
## Workflow Ownership

- Global `agent-ops` owns orchestration and custom-agent selection.
- `delivery-workflow` owns Prisma risk/lanes, validation commands, Git, and
  delivery evidence.
- This guide maps problem domains to project skills, which own implementation
  rules inside their boundaries.
- Prisma requires at most one writer in an explicitly isolated worktree.

## Planning and Review Skills

- Use global `improve` for read-only codebase surveys, prioritized findings,
  roadmap analysis, and self-contained implementation plans.
- Every plan must declare an `Execution profile`; reclassify it against the
  live scope through `agent-ops` before implementation.
- Use global `thermo-nuclear-code-quality-review` for strict review findings,
  semaforo severity, and approval framing.
- Load [`prisma-review-profile.md`](./prisma-review-profile.md) with the global
  thermo skill for Swift, macOS, privacy, architecture, and Prisma-specific
  maintainability rules.
- Keep `delivery-workflow` as the owner of lanes, validation commands, Git
  mechanics, and delivery evidence.
=======
## Delegated Agent Routing

The root Codex session is the orchestrator. It chooses the canonical skill first, then delegates only bounded work to the global custom agents documented in `~/.codex/agents/README.md`. Skills provide domain rules; agent files provide model, reasoning, sandbox, and MCP configuration.

| Work shape | Primary agent | Optional companion | Write policy |
|---|---|---|---|
| Simple search, explanation, or serial task | Root session | None | Root only |
| Broad codebase exploration | `explorer` | Domain specialist | Read-only |
| Unknown bug, crash, or flaky behavior | `diagnostician` | `explorer` or confirmed subsystem specialist | Read-only |
| Architecture, concurrency, persistence, audio, or security | Canonical domain skill + `diagnostician` | `reviewer` | Read-only until implementation |
| Scoped implementation | `implementer` | `explorer` before and `reviewer` after | One writer in isolated worktree |
| Code review | `reviewer` | Independent domain specialists | Read-only |
| Current external documentation or repository research | `researcher` | Canonical domain skill | Read-only; external MCP only |
| Figma or visual interaction inspection | `design-reviewer` | `macos-app-engineering`, `swiftui-pro`, or `accessibility-audit` | Read-only; Figma MCP only |
| Broad planning or audit | `explorer` children with non-overlapping questions | `reviewer` to vet findings | Read-only |

Delegation rules:

- Do not spawn children for trivial or strictly serial work.
- Give each child one purpose, the absolute project path, the primary skill path, and the expected compact handoff format.
- Prefer read-heavy parallelism. Do not run multiple write agents against the same checkout.
- Keep one nesting level and at most four concurrent children.
- An implementation child must stop as `blocked` if it is not in an isolated worktree.
- Child summaries must contain status, role, skill, inspected files or symbols, evidence, risks, and next action; never raw transcripts, secrets, or full logs.

### Domain-to-agent hints

| Canonical skill | Agent hint |
|---|---|
| `architecture`, `swift-concurrency-expert`, `audio-realtime`, `data-persistence`, `keychain-security` | `diagnostician` for uncertainty; `reviewer` before merge |
| `debugging-diagnostics` | `diagnostician`, then the confirmed subsystem specialist |
| `macos-app-engineering`, `swiftui-pro`, `apple-design`, `menubar`, `accessibility-audit` | `explorer` for code paths; `design-reviewer` for source/render comparison |
| `delivery-workflow`, `thermo-nuclear-code-quality-review` | `reviewer`; never parallelize write remediation |
| `improve` | Parallel `explorer` children for read-only categories; root advisor vets every finding |
| `documentation` or external API research | `researcher` with authoritative sources |
| `project-standards` | Root session or `explorer`; documentation changes stay in a dedicated worktree |
>>>>>>> chore/agent-orchestration

---

## Problem-Specific Routing

### Architecture and Boundaries

**Primary:** `architecture`
- Clean Architecture boundaries
- Dependency injection
- Cross-module ownership

**Complementary:** `macos-app-engineering` when architecture changes affect UI/app implementation details

**Example:** "Refactor meeting post-processing into a separate module" → `architecture`

---

### UI/UX and Interaction Work

**Start here:** `macos-app-engineering`
- Define UX acceptance criteria
- Implement SwiftUI/AppKit structure
- Apply Settings/design-system patterns
- Add or update previews

**Then (if needed):** `apple-design`, `swiftui-accessibility-audit`, `localization`, `debugging-diagnostics`, `swift-conventions`, or `swift-concurrency-expert`

For a SwiftUI modern-API / maintainability **review** pass, stay on
`macos-app-engineering` and open
The global `macos-app-engineering` skill owns the SwiftUI review appendix;
load its repository-local companion at `.agents/overlays/macos-app-engineering.md`
when the review is project-specific.

**Example:** "Design the meeting recording UI" → `macos-app-engineering`

---

### SwiftUI Performance Issues

**Primary:** `macos-app-engineering`
- Janky scrolling
- Layout thrash
- Excessive view updates

**Complementary:** `debugging-diagnostics` when the root cause is unclear

**Example:** "Scrolling in recording list is janky" → `macos-app-engineering` plus `debugging-diagnostics` if reproduction/diagnosis is needed

---

### Audio Capture and Processing

**Primary:** `audio-realtime`
- Audio glitches, underruns, dropout
- Low-latency callback optimization
- ProcessTap or AVAudioSourceNode work

**Example:** "Audio recording has glitches on M2" → `audio-realtime`

---

### Concurrency and Actor Isolation

**Primary:** `swift-concurrency-expert`

**Example:** "Actor-isolated property accessed from non-isolated context" → `swift-concurrency-expert`

---

### Code Quality and Refactoring

**Primary:** `code-quality`
- Readability and maintainability improvements
- Refactoring duplicated logic

**Complementary:** `swift-conventions`

Use `thermo-nuclear-code-quality-review` for review output, semaforo severity, and strict structural maintainability analysis.

**Example:** "Extract duplicate audio logic into a reusable service" → `code-quality`

---


### Debugging, Crashes, Flaky Behavior, and Diagnostics

**Primary:** `debugging-diagnostics`
- Unknown root cause investigation
- Crash analysis
- Flaky behavior
- `AppLogger` and `Logger`
- Structured event naming
- Payload redaction
- Failure signatures and metric correlation

**Complementary:** any subsystem skill that matches the narrowed scope

**Example:** "Crash on app quit when recording is active" → `debugging-diagnostics`
**Example:** "Add diagnostic logging around shortcut capture failures" → `debugging-diagnostics`

---

### Data Persistence, Storage, and Migrations

**Primary:** `data-persistence`
- Repositories
- Storage strategy
- Migrations and synchronization

**Example:** "Design storage strategy for meeting transcripts" → `data-persistence`

---

### Intelligence Kernel and Summary Quality

**Primary:** `intelligence-kernel`
- Kernel mode routing and feature flags
- Canonical summary schema and trust flags
- Summary benchmark thresholds and enforcement

**Complementary:** `data-persistence`, `delivery-workflow`

**Example:** "Adjust canonical summary confidence rules" → `intelligence-kernel`

---

### Security and Secret Management

**Primary:** `keychain-security`

**Example:** "Safely store API key for transcription service" → `keychain-security`

---


### Testing, Delivery, and Quality Gates

**Delivery workflow, verification policy, merge gates, and Git mechanics:** `delivery-workflow`

**XCTest implementation details:** `testing-xctest`

**Example:** "Add unit tests for TranscriptionService" → `testing-xctest`

---

### Localization and Accessibility

**Primary:** `localization`
- Localize UI text
- Manage locale-file hygiene
- Keep accessibility copy localizable

**Audit and interaction accessibility:** `swiftui-accessibility-audit`

**Example:** "Add Portuguese (Brazil) localization" → `localization`

---

### Menu Bar and macOS Native UI

**Primary:** `macos-app-engineering`
- NSStatusItem configuration
- NSMenu and NSPopover behavior
- Non-activating overlays

**Example:** "Implement menu-bar popover for recording controls" → `macos-app-engineering`

---


### Repository Standards and Project Maintenance

**Primary:** `project-standards`
- Update `AGENTS.md`
- Document project policy
- Align repository standards

**Example:** "Update AGENTS.md to reflect new skill" → `project-standards`

---

### Documentation and API Reference

**Primary:** `documentation`
- DocC comments and API documentation
- MARK organization and docs structure

**Complementary:** `project-standards`

**Example:** "Add DocC comments to the transcription service" → `documentation`

---

### Swift Style and Conventions

**Primary:** `swift-conventions`
- Swift style, type safety, API naming, and module organization

**Complementary:** `code-quality`

**Example:** "Rename public API to match module conventions" → `swift-conventions`

---

### Reference Projects and Study

**Primary:** global `reference-apps` + `.agents/overlays/reference-apps.md`
- Shared reference process and clone policy
- Prisma catalog (VoiceInk, FluidVoice, TypeWhisper, StenoAI)
- StenoAI is a **strong** UI/UX + same-domain bar (meeting record → note → summary); TypeScript/Electron stack — aesthetic/flow inspiration only; adapt via Apple HIG / SwiftUI–AppKit (`apple-design`, `macos-app-engineering`)

**Complementary:** `macos-app-engineering`, `apple-design`, `architecture`, `audio-realtime`

**Example:** "Compare dictation mode UX with VoiceInk" → `reference-apps` + overlay

**Example:** "Raise meeting-note UX toward StenoAI" → `reference-apps` + overlay, then `apple-design` / `macos-app-engineering` for native adaptation

---

Skill ownership and triggers live in each skill's `SKILL.md`; use this guide
for problem-specific routing and `AGENTS.md` for project-wide policy.
