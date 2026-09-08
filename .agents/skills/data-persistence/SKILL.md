---
name: data-persistence
description: This skill should be used when the user asks to "store/load data", "design repositories", "plan migrations", or "implement persistence synchronization".
---

# Data Persistence Strategies

## Role

Use this skill as the canonical owner for storage, repository, and migration guidance in Verbi.

- Own persistence-mechanism choice, migration expectations, and repository abstraction guidance.
- Keep storage advice aligned with data integrity and recoverability requirements.
- Delegate secret storage and broader security baseline decisions to their specialist owners.

## Scope Boundary

- Use this skill for repositories, storage design, migration planning, and persistence synchronization.
- Use `../keychain-security/SKILL.md` for credential persistence.
- Keep sensitive-data policy beyond persistence mechanics aligned with `AGENTS.md` security constraints.

## When to Use

Use this skill when the user asks to store/load data, design repositories, plan migrations, or implement persistence synchronization.

## Overview

Guidelines for choosing the right storage mechanism and ensuring data integrity and security.

## 1. Storage Mechanisms

- **UserDefaults**: Use for lightweight preferences and simple key-value pairs.
- **Core Data / Persistence**: Use for complex models, relationships, and large datasets.
- **Keychain**: **MANDATORY** for sensitive data (API keys, passwords, tokens). Never store secrets in UserDefaults or plain files.

## 2. Integrity & Lifecycle

- **Migration Planning**: Plan for schema changes from the start (versioning, lightweight vs. heavy migration).
- **Cloud Sync**: Implement iCloud synchronization (CloudKit or `NSUbiquitousKeyValueStore`) where appropriate for user settings.
- **Threading**: Perform database operations on background contexts to avoid blocking the main thread.

## 3. Best Practices

- **Abstraction**: Use protocol-based repositories to decouple business logic from the specific persistence implementation.
- **Error Handling**: Gracefully handle missing data or corruption; provide default states where necessary.
- **Cleanup**: Implement data pruning or expiration policies for cached or temporary data.

## Migration and History Invariants

When persistence behavior changes, prioritize:

- `Packages/MeetingAssistantCore/Sources/Data/Data/CoreData/CoreDataStack.swift`
- `Packages/MeetingAssistantCore/Sources/Data/Services/StorageService/StorageService.swift`
- `Packages/MeetingAssistantCore/Sources/Infrastructure/Services/KeychainManager.swift`

For migrations and backfills:

1. Keep existing UserDefaults readable and Keychain identifiers resolving previous credentials.
2. Make persistent-store path changes deterministic and idempotent.
3. Preserve recoverability; never leave a partial destructive migration.
4. Keep retention cleanup from deleting dashboard history unexpectedly.
5. Validate round-trip mapping across persistence, domain, and UI boundaries.
6. Model retry or reprocess analytics as append-only attempts, preserving legacy transcription snapshots.
7. Test fresh backfill, no-op re-run, and isolated checkpoint keys.
8. Expose newest-first attempt history separately from aggregate ranking queries.
