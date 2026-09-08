---
kind: project-overlay
extends: reference-apps
project: verbi
precedence: project
---

# Verbi / Verbi reference catalog

**Same-domain** here means meeting capture, transcription, voice-to-text, or
audio processing.

Relative clones from this repo: `../References/<CanonicalName>/`.

## Registered references

### VoiceInk

| Attribute | Value |
|-----------|-------|
| **Canonical name** | VoiceInk |
| **Classification** | UI/UX + Same-domain |
| **Local path** | `../References/VoiceInk/` |
| **Cloned?** | Yes |
| **Reference revision** | `baae439aae22` (2025-12-07) |
| **Remote** | https://github.com/mourato/VoiceInk.git |
| **License** | GPL-3.0 (`LICENSE`) |
| **License URL** | https://www.gnu.org/licenses/gpl-3.0.html |
| **Reuse decision** | Inspiration and independent reimplementation only; do not copy source or assets. No README credit required. |
| **Description** | macOS voice transcription; architecture, audio pipeline, and UI patterns |

### FluidVoice

| Attribute | Value |
|-----------|-------|
| **Canonical name** | FluidVoice |
| **Classification** | Same-domain |
| **Local path** | `../References/FluidVoice/` |
| **Cloned?** | Yes |
| **Remote** | https://github.com/altic-dev/FluidVoice/ |
| **Reference revision** | `dc570291261e` (2026-07-06; nearest tag `v1.6.2`) |
| **License** | GPL-3.0 (`LICENSE`; GPLv3 applies from 2026-02-23; earlier releases were Apache-2.0) |
| **License URL** | https://www.gnu.org/licenses/gpl-3.0.html |
| **Reuse decision** | Inspiration and independent reimplementation only; do not copy source or assets. No README credit required. |
| **Description** | Fluid voice UI and audio interactions |

### TypeWhisper

| Attribute | Value |
|-----------|-------|
| **Canonical name** | TypeWhisper |
| **Classification** | Same-domain |
| **Local path** | `../References/TypeWhisper/` |
| **Cloned?** | Yes |
| **Remote** | https://github.com/TypeWhisper/typewhisper-mac |
| **Reference revision** | `3a15a618d657` (2026-07-07; nearest tag `v1.6.0-daily.20260706`) |
| **License** | GPL-3.0 (`LICENSE`; copyright TypeWhisper, 2026) |
| **License URL** | https://www.gnu.org/licenses/gpl-3.0.html |
| **Reuse decision** | Inspiration and independent reimplementation only; do not copy source or assets. No README credit required. |
| **Description** | macOS voice-to-text; transcription workflow reference |

### StenoAI

| Attribute | Value |
|-----------|-------|
| **Canonical name** | StenoAI |
| **Classification** | UI/UX + Same-domain (**strong reference**) |
| **Local path** | `../References/StenoAI/` |
| **Cloned?** | Yes |
| **Remote** | https://github.com/ruzin/stenoai |
| **Reference revision** | `35952b04fb6e` (2026-07-25) |
| **License** | MIT (`LICENSE`; copyright Skrape Limited, 2025) |
| **License URL** | https://opensource.org/license/mit |
| **Reuse decision** | Inspiration and independent SwiftUI/AppKit reimplementation only; do not copy web/Electron source, assets, or UI copy. No README credit required. |
| **Stack** | TypeScript / Electron web UI + Python local AI — **not** Swift/AppKit |
| **Description** | Privacy-first meeting notepad: recording, live transcription, note-taking, summary/report generation, and meeting Q&A. Primary bar for interface polish and the end-to-end meeting-note flow. |
| **Transfer policy** | **Aesthetic and product-flow inspiration only.** Study hierarchy, density, recording/summary journeys, and calm editorial UX; re-express every adopted pattern in SwiftUI/AppKit under Apple HIG, platform materials, and Verbi architecture. Do **not** copy web/Electron chrome, CSS tokens, or TypeScript structure into production code. Prefer `apple-design` + `macos-app-engineering` when translating visuals or interaction. |
| **Touchpoints** | Recording / transcription pill coexistence; stop → note landing; resume-into-note; live transcript attribution; summary + user notes fold-in; report templates; meeting library detail |

## Product routing

After locating reference material:

- Architecture patterns → local `architecture`
- Audio pipeline → local `audio-realtime`
- macOS UI implementation → global `macos-app-engineering` (+ overlay)
- Visual/interaction translation from non-native references (especially StenoAI) → global `apple-design` (+ overlay), then `macos-app-engineering`
- Review of changes inspired by references → global `thermo-nuclear-code-quality-review`

Summary, fixture, provider-drift, and `make benchmark-summary` gates stay with
`intelligence-kernel` and delivery guidance — not this overlay.
