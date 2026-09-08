---
kind: project-overlay
extends: apple-design
project: verbi
precedence: project
---

# Verbi visual checks

- Preserve native macOS behavior across the macOS 15 baseline and macOS 26 availability guards.
- SwiftUI is the primary presentation layer; use AppKit at status-item, panel, lifecycle, and permission boundaries.
- Inspect the recording indicator, onboarding, settings, and menu-bar surfaces before introducing new motion or material tokens.
- Keep capture → transcription → AI post-processing states legible without revealing transcript content or other private data in UI diagnostics.
- For audio-specific lifecycle constraints, use the retained local `audio-realtime` specialist.
