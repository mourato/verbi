# Verbi Review Profile

This project profile extends the global `thermo-nuclear-code-quality-review`
skill. It contains Verbi-specific review lenses only; workflow lanes,
validation commands, Git mechanics, and delivery evidence remain owned by
`delivery-workflow`.

## Project context

- Verbi is a local-first macOS meeting capture, transcription, and AI
  post-processing app.
- The minimum deployment target is macOS 15+ and Swift 6.2 strict concurrency
  is enabled.
- SwiftUI is the default UI layer; AppKit is used for status items, panels,
  lifecycle, permissions, and capabilities SwiftUI cannot express reliably.
- Clean Architecture boundaries and the repository module ownership in
  `AGENTS.md` are review constraints.

## Verbi-specific review lenses

- Check actor isolation, `@MainActor`, `Sendable`, cancellation, callback
  boundaries, and races in Swift concurrency.
- Check audio callbacks, buffering, underruns, latency, and real-time safety
  when audio code is touched.
- Check persistence boundaries, Core Data migrations, repository ownership,
  atomic updates, and data retention behavior.
- Check transcript, prompt, response, recording-path, and personal-identifier
  privacy in logs, diagnostics, and agent artifacts.
- Check Keychain use for credentials and least-privilege entitlements.
- Check localization keys, removed-key hygiene, accessibility labels and
  hints, keyboard/focus behavior, and reduced-motion behavior for UI changes.
- Check macOS 15 fallbacks and `#available(macOS 26, *)` guards for newer APIs.
- Check local model registry entries, unload hooks, and `modelResidencyTimeout`
  coverage for every local model runtime.
- Prefer the existing canonical module, helper, design-system component, and
  navigation pattern over a new wrapper or duplicate path.

## Structural quality bar

- Look aggressively for a structural simplification that deletes branches,
  wrappers, modes, or layers instead of merely moving complexity.
- Treat ad-hoc conditionals, feature checks in shared flows, and one-off flags
  as maintainability findings.
- Do not allow a change to push a file from below 1,000 lines above 1,000
  without a compelling structural reason and an explicit decomposition review.
- Prefer direct, typed, maintainable Swift over casts, magical wrappers,
  unnecessary optionality, or bespoke helpers that duplicate canonical code.

## Verbi semaforo

- **Critical**: crash risk, data loss, privacy/security harm, hard-constraint
  breach, or a release-blocking regression.
- **Medium**: correctness risk, maintainability regression, missing required
  test/verification, concurrency or persistence weakness, or material UX issue.
- **Low**: optional clarity, style, or opportunistic cleanup.

Critical and Medium findings block handoff under the project's review policy.
Low findings require an explicit deferral note.

## Required review evidence

Separate changed-path failures from baseline failures. Report touched files,
affected subsystem, validation commands, assumptions, and unresolved risks.
Review artifacts must not contain prompts, transcripts, secrets, or sensitive
diagnostics.
