---
kind: project-overlay
extends: code-quality
project: verbi
precedence: project
---

# Verbi ownership checks

- Product and technical identifiers use Verbi (`com.mourato.verbi`); MeetingAssistant* remains the Xcode/SwiftPM scaffold.
- Preserve ownership boundaries under `Packages/MeetingAssistantCore/Sources/`: `Common`, `Domain`, `Infrastructure`, `Data`, `Audio`, `AI`, `UI`, `Core`, `Mocking`, and `MockingMacros`.
- Public SwiftPM targets remain `MeetingAssistantCore*`; do not infer public module names from short filesystem directories.
- Colocate types in owning directories and keep split Swift filenames unique; do not use `Type+Concern.swift`.
- Route architecture, persistence, audio, and intelligence-kernel findings to the retained local specialists rather than duplicating their rules here.
