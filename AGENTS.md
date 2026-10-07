# AGENTS.md

Verbi: local-first macOS 15+ meeting capture, transcription, and AI
post-processing app; identifiers `com.mourato.verbi`, Xcode/SwiftPM scaffold
`MeetingAssistant*`.

Commands: [Makefile](Makefile) is canonical. Project facts for global skills
live here and in linked `docs/agents/` files. Run `make guidance-check` after
changing this file, `.agents/`, or referenced command docs.

## Local routing

| Before | Read |
|---|---|
| Implementation, validation, or delivery | [Project workflow facts](docs/agents/project-workflow.md) |
| Review or retro | [Coding standards](CODING_STANDARDS.md) |
| Choosing a specialist | [Skill Routing Guide](.agents/docs/skill-routing.md) |
| Code entry points or dependency lookup | [Navigation](.agents/docs/navigation.md) |
| Choosing a build or test command | [Build and Test Reference](.agents/docs/build-and-test.md) |
| Delivery facts | [`delivery-workflow`](.agents/skills/delivery-workflow/SKILL.md) |
| Toolchain questions | `.agents/docs/swift-6-2-agent-baseline.md` |
