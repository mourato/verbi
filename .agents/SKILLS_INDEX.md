# Skills Index

Comprehensive index of all available agent skills for Verbi. For routing logic and guidance on selecting the right skill and global subagent, see [Skill Routing Guide](./docs/skill-routing.md). The reusable custom-agent catalog lives at `~/.codex/agents/` and is coordinated by the global `$agent-ops` skill.

## Complete Skills Table

| Skill | Location | Triggers / When to Use |
|-------|----------|------------------------|
| `accessibility-audit` | `.agents/skills/accessibility-audit/` | Audit VoiceOver, keyboard navigation, focus order, reduced motion, overlays, and other accessibility-sensitive UI behavior |
| `apple-design` | `.agents/skills/apple-design/` | Apple-style interaction design, fluid motion, springs, materials, typography, and reduced-motion behavior |
| `benchmarking` | `.agents/skills/benchmarking/` | Triggered by mentions of VoiceInk, FluidVoice, TypeWhisper, or "referência/inspiração". Provides canonical paths and clone policy for reference projects |
| `architecture` | `.agents/skills/architecture/` | Design module boundaries, apply Clean Architecture, refactor architecture, define dependency injection |
| `audio-realtime` | `.agents/skills/audio-realtime/` | AVAudioSourceNode, AudioRecorder, ProcessTap, audio glitches, underruns, low-latency optimization |
| `code-quality` | `.agents/skills/code-quality/` | Improve code readability, rename for clarity, refactor duplicated logic, apply clean code conventions |
| `data-persistence` | `.agents/skills/data-persistence/` | Store/load data, design repositories, plan migrations, implement synchronization |
| `debugging-diagnostics` | `.agents/skills/debugging-diagnostics/` | Debug bugs, investigate crashes, analyze flaky behavior, trace unknown root causes, standardize logging, telemetry, redaction, and diagnostic signatures |
| `delivery-workflow` | `.agents/skills/delivery-workflow/` | Classify risk, select delivery lane, choose validation commands, run checks, commit, prepare PRs, merge, and enforce pre-merge workflow |
| `documentation` | `.agents/skills/documentation/` | Write/update documentation, add DocC comments, improve MARK organization, research API docs |
| `improve` | `.agents/skills/improve/` | Audit a codebase, find improvement opportunities, suggest roadmap direction, or write implementation plans for another agent |
| `intelligence-kernel` | `.agents/skills/intelligence-kernel/` | Canonical summary schema, intelligence kernel modes, trust flags, summary benchmark gates |
| `keychain-security` | `.agents/skills/keychain-security/` | Store secret in Keychain, retrieve API keys securely, delete credential, harden KeychainManager usage |
| `localization` | `.agents/skills/localization/` | Localize UI text, update Localizable.strings, improve accessible copy, remove orphaned locale keys |
| `macos-app-engineering` | `.agents/skills/macos-app-engineering/` | macOS UI/app implementation, SwiftUI views, AppKit bridging, Settings UI, design-system components, preview coverage, and platform lifecycle |
| `menubar` | `.agents/skills/menubar/` | Build menu-bar behavior, configure NSStatusItem, implement popover, manage non-activating overlays |
| `project-standards` | `.agents/skills/project-standards/` | Update AGENTS.md, document project policy, track known limitations, align repository standards |
| `swift-concurrency-expert` | `.agents/skills/swift-concurrency-expert/` | Primary for concurrency issues: fix Swift concurrency errors, resolve actor isolation, remediate Sendable diagnostics, upgrade Swift 6.2 |
| `swift-conventions` | `.agents/skills/swift-conventions/` | Apply Swift style conventions, improve type safety, refactor API naming, organize Swift modules |
| `swiftui-pro` | `.agents/skills/swiftui-pro/` | Review SwiftUI APIs, data flow, navigation, accessibility, performance, and maintainability |
| `testing-xctest` | `.agents/skills/testing-xctest/` | Write XCTest code, structure async and `@MainActor` tests, build mocks/fakes/spies, and keep test suites maintainable |
| `thermo-nuclear-code-quality-review` | `.agents/skills/thermo-nuclear-code-quality-review/` | Default code review skill: review changes, audit PRs, find risks before merge, produce semaforo findings, and run strict maintainability analysis |

---

## Skill Selection Quick Reference

### By Problem Type

**UI/UX and Interfaces**
- First: `macos-app-engineering`
- Escalate to `swiftui-pro`, `apple-design`, `accessibility-audit`, `localization`, `menubar`, `debugging-diagnostics`, or `swift-concurrency-expert` when the task is specifically in that specialist scope

**Performance Issues**
- SwiftUI rendering: `macos-app-engineering` for view structure, then `debugging-diagnostics` if root cause is unclear
- Audio capture/processing: `audio-realtime`
- Logging and telemetry quality: `debugging-diagnostics`

**Concurrency and Safety**
- Swift 6.2 compiler errors: `swift-concurrency-expert`

**Code Quality**
- Readability/refactoring: `code-quality`
- Testing/mocks and test code structure: `testing-xctest`
- Delivery workflow, merge gates, verification policy, and Git mechanics: `delivery-workflow`
- Code review: `thermo-nuclear-code-quality-review`
- Architecture boundaries: `architecture`

**Security**
- Secret management: `keychain-security`

**Data and Storage**
- Persistence design: `data-persistence`
- Migrations: `data-persistence`

**Intelligence and Post-Processing**
- Kernel mode routing, canonical summary, benchmark gates: `intelligence-kernel`

**Debugging and Diagnostics**
- Crashes, flaky tests, unknown root causes, logging, telemetry, redaction, and failure signatures: `debugging-diagnostics`

**Documentation and Localization**
- API docs/DocC: `documentation`
- UI localization and accessible copy: `localization`
- Accessibility audit and keyboard/focus review: `accessibility-audit`

**Platform-Specific (macOS)**
- General macOS UI/app guidance: `macos-app-engineering`
- Menu bar UI: `menubar`



**Project Maintenance**
- Repository standards: `project-standards`
- Read-only improvement planning: `improve`
- Strict maintainability review: `thermo-nuclear-code-quality-review`
- Reference project registry and clone policy: `benchmarking`

### Engineering Workflow Ownership

- `delivery-workflow`: risk classification, lane selection, lifecycle sequencing, validation strategy, command mapping, branch, commit, PR, and cleanup mechanics
- `thermo-nuclear-code-quality-review`: review findings, severity framing, semaforo output, and strict structural maintainability analysis

---

## Skill Dependencies

- `accessibility-audit` → `localization` (copy and keys stay localizable)
- `macos-app-engineering` → `accessibility-audit` / `localization` / `menubar` (specialist escalation only)
- `delivery-workflow` → `testing-xctest` (delivery gates → XCTest specifics)
- `debugging-diagnostics` → subsystem skills (route to the owner once the failing surface is proven)
- `thermo-nuclear-code-quality-review` → `delivery-workflow` / other skills (review may escalate to lane, validation, or subsystem specialists)
