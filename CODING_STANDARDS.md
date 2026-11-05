# Verbi coding standards

Read during review (Standards axis) and retro. Extends the global standards at
`${AGENT_CONFIG_HOME:-$HOME/.agents}/core/standards/CODING_STANDARDS.md` and the
`swift-conventions` skill; project rules only.

## Review focus

- Failure here: audio, transcripts, or notes leaving the Mac without a remote
  provider the user configured, or showing up in logs and diagnostics.
- Failure here: recording that starts without a user action.
- Skip: `App/Assets.xcassets/`.
- Needs a person: `App/Verbi.entitlements`, Keychain code
  (`KeychainManager.swift`, `DefaultKeychainProvider.swift`), and remote
  transcription clients in `Packages/VerbiCore/Sources/AI/Services/`.

## Rules

- Module ownership: `Common` utilities, `Domain` entities, `Infrastructure`
  adapters, `Data` persistence, `Audio` capture, `AI` transcription, `UI`
  presentation, `Core` exports.
- New SwiftUI state uses Observation; keep `ObservableObject` until a migration
  is verified.
- User-facing strings use `"key".localized`; delete orphaned keys with the text.
- Every local model honors `modelResidencyTimeout`; new models need a registry
  entry and unload hook.
- Secrets live in Keychain. Logs, diagnostics, menu-bar titles, and agent
  artifacts never carry tokens, transcripts, prompts, responses, or PII.
- Least-privilege entitlements; validate external input at module boundaries.
- Keep capture -> transcription -> AI post-processing states legible in UI.
