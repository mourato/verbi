---
name: localization
description: This skill should be used when the user asks to "localize UI text", "update Localizable.strings", "improve accessible copy", or "add accessibility localization".
---

# Localization and Accessible Copy

## Role

Canonical owner for localization and accessible copy: `"key".localized` usage, locale-file hygiene, and accessibility-copy key patterns.

## Scope Boundary

- Use this skill for localized strings, localization-key cleanup, and accessible copy text.
- Use global `better-accessibility` for keyboard focus, reduced motion, overlays, and broader accessibility behavior.

## When to Use

Trigger for `Bundle.safeModule`, `"key".localized`, localized accessibility labels/hints, or string-key cleanup across locale files.

## Non-negotiable rules

- **Never hardcode UI strings** — use `"key".localized` or `.localized(with:)`.
- **Always resolve through shared helpers** — `Bundle.safeModule` in `BundleExtension.swift`; do not re-implement bundle lookup in feature code.
- **Register new keys in all locales** (`en.lproj` and `pt.lproj`) in the same PR/slice.
- **Keep locale files symmetric** — no key in only one language.
- **Remove orphaned keys** when UI text is deleted; confirm no source references remain.
- **Key convention**: dot-separated `lower_snake_case` segments (e.g. `settings.transcriptions.empty_desc`).
- Route broad accessibility audits to global `better-accessibility`.

```swift
// ✅ Standard
Text("settings.transcriptions.title".localized)
Text("permissions.granted_count".localized(with: granted, required))

// ❌ Avoid in feature code
NSLocalizedString("settings.transcriptions.title", comment: "")
```

## Routed references

Read [localization patterns](references/localization-patterns.md) for extended examples:

| Request | Reference sections |
|---|---|
| Accessibility copy and hints | Accessible copy; key convention |
| Registration and cleanup checklists | Mandatory registration; mandatory sanitization |
| Settings taxonomy changes | Historical progression notes |

## Related Skills

- Global `better-accessibility`
- Global `macos-ui`

## References

- [BundleExtension.swift](../../../Packages/MeetingAssistantCore/Sources/Common/Utilities/BundleExtension.swift)
- [Localizable.strings](../../../Packages/MeetingAssistantCore/Sources/Common/Resources/en.lproj/Localizable.strings)
