---
kind: project-overlay
extends: swiftui-accessibility-audit
project: verbi
precedence: project
---

# Verbi accessibility checks

- macOS 15 is the minimum supported target; guard macOS 26 APIs and preserve macOS 15 fallbacks.
- Review the SwiftUI/AppKit lifecycle at `App/AppDelegate/` and the floating recording indicator under `Packages/MeetingAssistantCore/Sources/UI/`.
- Recording and transcription flows require explicit microphone, Screen Recording, and Accessibility permission communication; never expose transcript or model content in diagnostics.
- Menu-bar state must remain understandable through labels and menu copy; route status-item ownership details to the global `macos-app-engineering` skill and this project's overlay.
- For domain-specific audio behavior, use the retained local `audio-realtime` specialist.
