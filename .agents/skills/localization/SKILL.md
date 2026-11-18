---
name: localization
description: This skill should be used when the user asks to "localize UI text", "update Localizable.strings", "improve accessible copy", or "add accessibility localization".
---

# Localization and Accessible Copy

## Role

Canonical owner for localized strings, key hygiene, and accessible copy in Verbi.

## Scope Boundary

Use for localized text and key cleanup. Delegate broader accessibility behavior to global `better-accessibility`.

## When to Use

Use for localized strings, localization-key cleanup, and accessible copy text in Verbi.

## Project specifics

Non-negotiable rules:

- Never hardcode UI strings; use `"key".localized` or `.localized(with:)`.
- Always resolve through `Bundle.safeModule` in `BundleExtension.swift`; do not re-implement bundle lookup in feature code.
- Register new keys in `en.lproj` and `pt.lproj` in the same PR/slice; keep locale files symmetric.
- Remove orphaned keys when UI text is deleted, after confirming no source references remain.
- Key convention: dot-separated `lower_snake_case` segments, for example `settings.transcriptions.empty_desc`.

```swift
Text("settings.transcriptions.title".localized)
Text("permissions.granted_count".localized(with: granted, required))
```

Do not use `NSLocalizedString` in feature code. Extended examples: [references/localization-patterns.md](references/localization-patterns.md).

## Related

Global `better-accessibility`, global `macos-ui`. References: `Packages/VerbiCore/Sources/Common/Utilities/BundleExtension.swift`, `Packages/VerbiCore/Sources/Common/Resources/en.lproj/Localizable.strings`.
