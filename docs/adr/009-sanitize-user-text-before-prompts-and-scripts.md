# ADR 009: Sanitize user text before it enters AI prompts or AppleScript

**Status:** Accepted
**Date:** 2026-11-20

## Context

Verbi mixes user text (vocabulary, notes, captured context) into AI prompts and into an `osascript` command in a Debug fallback. Unescaped text could break prompt boundaries, leak context metadata, or run AppleScript.

## Decision

- Prompt block content escapes reserved tags so user text cannot break the wrapper boundaries.
- Post-processing output is sanitized so that captured context metadata can never reach user-visible text.
- Vocabulary terms are stripped of control characters and of VOCABULARY delimiter tags before they enter the post-processing prompt, so a saved term cannot break the prompt block.
- When the `redactSensitiveData` setting is on (the default), context metadata is redacted for emails, URLs, tokens and long numeric sequences before it is sent to the AI provider.
- In the Debug fallback for runs outside an app bundle, notification text is interpolated into an osascript command, so quotes, backslashes and AppleScript metacharacters are escaped and the text is truncated first; release builds use `UNUserNotificationCenter`.

## Consequences

Each rule above also lives in `docs/CODE_CONSTRAINTS.md` beside its owning file, because source code carries no comments. Change a rule, its code, and this ADR together.

## Rejected or deferred

Trusting saved vocabulary and context as plain text was rejected, because a saved term could close a prompt block or inject instructions.

## References and license

Recovered from code comments removed by the comment cleanup; no external material.

## Affected surfaces

- `Packages/VerbiCore/Sources/Common/Security/MeetingNotesMarkdownSanitizer.swift`
- `Packages/VerbiCore/Sources/Common/Utilities/TranscriptionOutputSanitizer.swift`
- `Packages/VerbiCore/Sources/Domain/Models/VocabularySnapshot.swift`
- `Packages/VerbiCore/Sources/Infrastructure/Models/AppSettingsStore/AppSettings.swift`
- `Packages/VerbiCore/Sources/Infrastructure/Services/ContextAwarenessPrivacy.swift`
- `Packages/VerbiCore/Sources/Infrastructure/Services/ContextAwarenessService.swift`
- `Packages/VerbiCore/Sources/Infrastructure/Services/NotificationService.swift`
