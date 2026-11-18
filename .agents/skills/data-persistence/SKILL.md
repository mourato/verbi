---
name: data-persistence
description: This skill should be used when the user asks to "store/load data", "design repositories", "plan migrations", or "implement persistence synchronization".
---

# Data Persistence Strategies

## Role

Canonical owner for storage, repositories, and migration guidance in Verbi.

## Scope Boundary

Use for repositories, storage design, migration planning, and persistence synchronization. Delegate credential storage to `../keychain-security/SKILL.md`.

## When to Use

Use for repositories, storage design, migration planning, and persistence synchronization in Verbi.

## Project specifics

Surfaces: `Packages/VerbiCore/Sources/Data/Data/CoreData/CoreDataStack.swift`, `Packages/VerbiCore/Sources/Data/Services/StorageService/StorageService.swift`, `Packages/VerbiCore/Sources/Infrastructure/Services/KeychainManager.swift`.

Rules:

- Use protocol-based repositories to decouple business logic from the persistence implementation.
- Perform database operations on background contexts to avoid blocking the main thread.
- Handle missing data or corruption gracefully with explicit default states; prune cached or temporary data.
- Keep secrets out of UserDefaults and plain files; route credential persistence to `../keychain-security/SKILL.md`.

Migration and history invariants:

1. Keep existing UserDefaults readable and Keychain identifiers resolving previous credentials.
2. Make persistent-store path changes deterministic and idempotent.
3. Preserve recoverability; never leave a partial destructive migration.
4. Keep retention cleanup from deleting dashboard history unexpectedly.
5. Validate round-trip mapping across persistence, domain, and UI boundaries.
6. Model retry or reprocess analytics as append-only attempts, preserving legacy transcription snapshots.
7. Test fresh backfill, no-op re-run, and isolated checkpoint keys.
8. Expose newest-first attempt history separately from aggregate ranking queries.

## Related
`../keychain-security/SKILL.md`, `../architecture/SKILL.md`.
