---
name: architecture
description: This skill should be used when the user asks to "design module boundaries", "apply Clean Architecture", "refactor architecture", or "define dependency injection" in this project.
---

# Architecture Principles

## Role

Canonical owner for module boundaries, Clean Architecture, and dependency injection in Verbi.

## Scope Boundary

Use for module ownership, dependency direction, and cross-layer abstractions. Delegate platform UI to global `macos-ui` and readability to global `simplify-as-you-go`.

## When to Use

Use for module ownership, dependency direction, and cross-layer abstractions in Verbi.

## Project specifics

- SwiftPM target and import names stay `VerbiCore*`; source directories under `Packages/VerbiCore/Sources/` use short PascalCase names.
- `VerbiCoreCommon` — logging, config, utilities, resources; `VerbiCoreDomain` — entities, contracts, use cases.
- `VerbiCoreInfrastructure` — OS/external adapters (Keychain, networking, providers); `VerbiCoreData` — persistence repositories and storage.
- `VerbiCoreAudio` — capture, buffering, rendering, file writing; `VerbiCoreAI` — transcription, post-processing, rendering.
- `VerbiCoreUI` — view models, coordinators, SwiftUI/AppKit presentation; `VerbiCore` — compatibility export layer for app and tests.
- Boundary rule: depend inward through protocols, not across feature layers through concrete types.
- DI: inject dependencies through initializers; avoid `.shared` singletons in ViewModels; prefer protocol abstractions and composition over inheritance.
- Layout: organize split files by owning type directory, not `Type+Concern.swift`; keep companion basenames unique within the target.
- Audio hot path: callbacks stay allocation-minimal and free of MainActor hops; prefer `OSAllocatedUnfairLock` over `NSLock`; route file IO, diagnostics, and formatting out of callbacks.

Validation: `make arch-check` for cross-module refactors.

## Follows global codebase-design

Deep-module design, seam placement, testability through a small interface, and reuse-before-create vocabulary come from global `codebase-design`.

Related: global `macos-ui`, global `simplify-as-you-go`, `../audio-realtime/SKILL.md`, `../delivery-workflow/SKILL.md`.
