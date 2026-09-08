---
kind: project-overlay
extends: macos-app-engineering
project: verbi
precedence: project
---

# Verbi application checks

- Target macOS 15+ and guard macOS 26 APIs with explicit macOS 15 fallbacks; macOS 27 remains preview-only.
- Swift 6.2 strict concurrency and default actor isolation are active; keep actor boundaries and `Sendable` reasoning explicit.
- SwiftUI owns ordinary presentation; AppKit owns status items, non-activating panels, lifecycle integration, and permission boundaries.
- Menu-bar: keep one explicit status-item owner in the app lifecycle; start with `App/AppDelegate/MenuBar.swift` and related `AppDelegate` coordinators. The floating recording indicator lives under `Packages/MeetingAssistantCore/Sources/UI/`; its visibility follows reactive recording state rather than one trigger path.
- Menu-bar and status-item actions must respect the local-first privacy boundary: do not place transcript, prompt, credential, or model internals in titles, logs, or diagnostics.
- Start module and ownership discovery in `Packages/MeetingAssistantCore/Sources/` and preserve the distinction between short source directories and `MeetingAssistantCore*` public targets.
- For recording, transcription, storage, or intelligence-specific implementation details, route to the retained local specialists.
