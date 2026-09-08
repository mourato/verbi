---
kind: project-overlay
extends: delivery-workflow
project: verbi
precedence: project
---

# Verbi delivery checks

- Product-specific identifiers and commands for Verbi belong in this
  overlay or repository guidance, not in the portable global
  `delivery-workflow` skill.
- `Makefile` is the command authority. Use `make help` before direct script discovery.
- Guidance-only changes use `make guidance-check`; validation-infrastructure changes also require `make workflow-test`.
- `make validate` is the default automatic validation entry; it delegates to
  `validate-agent`. Explicit Fast/Full lanes use `make validate-agent` with
  `ARGS`.
- `make validate-lane` wraps `make validate` with the global explicit baseline
  and artifact gate, using unique ignored
  `.xcode-build-tests/validate-lane.*` DerivedData and `.tmp/validate-lane.*`
  SwiftPM scratch roots. Both run roots are watched and cleaned before the
  wrapper returns; their parent roots are preserved.
  Parity-specific roots belong to their explicit lanes.
- Changes touching Swift, behavior, audio, concurrency, persistence, security, or cross-module boundaries use that lane policy and retained specialist routing.
- Keep the app local-first: Keychain stores credentials, transcripts and prompts stay out of logs and agent artifacts, and CloudKit synchronization is intentionally absent.
- Report commands, results, risk/lane, review outcome, and known baseline failures in delivery handoffs.
