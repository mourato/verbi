---
name: documentation
description: This skill should be used when the user asks to "write/update documentation", "add DocC comments", "improve MARK organization", or "research API docs".
---

# Documentation Standards

## Role

Use this skill as the canonical owner for documentation practices in Verbi.

- Own DocC guidance, code-comment conventions, and documentation research order.
- Keep repository guidance aligned with the actual tool surface available in this environment.
- Delegate repository policy maintenance and external skill discovery to their specialist owners.

## Scope Boundary

- Use this skill for writing or refining documentation and DocC comments.
- Use `../project-standards/SKILL.md` for project policy, AGENTS maintenance, and guidance governance.

## When to Use

Use this skill when the user asks to write or update documentation, add DocC comments, improve MARK organization, or research API docs.

## Overview

Detailed guidance on documenting Swift code and researching external APIs with the tools that are actually available in this environment.

## 1. DocC Best Practices

- **Triple-Slash**: Use `///` for all public API documentation.
- **Format**: Follow standard Swift documentation format (Summary, Parameters, Returns, Throws).
- **Auto-Generation**: Ensure documentation is structured to be compatible with DocC generation.

## 2. External Research

Use primary sources when documentation work depends on current third-party behavior.

Preferred order:

1. Official vendor documentation
2. Repository-local guidance and comments
3. Official SDK or framework source
4. Web lookup only when the information is not available locally

If an external skill would materially help, treat it as optional and use the available skill-discovery mechanism rather than assuming that skill is installed.

## 3. Tool-Agnostic Principles

- **Clear Intent**: Documentation should explain the "Why" (intent, trade-offs) rather than just the "What".
- **Living Docs**: Keep `README.md` and `AGENTS.md` updated as the architecture evolves.
- **Known Limitations**: Document technical debt and constraints in GitHub issues (label `known-limitation`), not in root `docs/` files.

## Key Concepts

### DocC Syntax

Document public APIs with triple-slash comments and structured markup:

```swift
/// A struct representing a meeting recording.
///
/// This struct encapsulates all metadata and content of a recording,
/// including speaker identification and timestamp alignment.
///
/// ## Usage
/// ```swift
/// let recording = Recording(
///     id: UUID(),
///     title: "Team Meeting",
///     date: Date()
/// )
/// ```
public struct Recording: Identifiable, Codable {
    /// The unique identifier of the recording.
    public let id: UUID

    /// The title of the recorded meeting.
    public let title: String

    /// The date and time when recording started.
    public let date: Date

    /// The duration of the recording in seconds.
    public let duration: TimeInterval

    /// The transcribed text of the meeting.
    public let transcription: String?
}
```

## Code Organization

### MARK Comments

Use `// MARK:` to organize code into logical sections:

```swift
// MARK: - Properties

// MARK: - Initialization

// MARK: - Public Methods

// MARK: - Private Methods
```

## References

- [Meeting.swift](../../../Packages/MeetingAssistantCore/Sources/Domain/Models/Meeting.swift)
- [Apple DocC Guide](https://developer.apple.com/documentation/docc)

## Related Skills

- `../project-standards/SKILL.md`
