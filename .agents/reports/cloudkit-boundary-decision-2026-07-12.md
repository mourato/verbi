# CloudKit boundary decision — 2026-07-12

## Decision

Do not add CloudKit entitlements, a production container, sync code, or a sync UI in the current roadmap slice. Verbi should preserve local-first history and audio as the default architecture and prioritize explicit local export/import or backup before evaluating cross-device convenience.

A future, separately approved experiment may consider syncing a small allowlist of non-sensitive preferences. It must not sync meeting history, transcript content, audio, context, credentials, or performance records. This is a deferred product decision, not an implementation authorization.

## Data classification

| Data | Boundary | Decision and rationale |
| --- | --- | --- |
| Transcripts, processed content, canonical summaries, Q&A, speaker segments | Local-only | Content is sensitive meeting data. Keep in local Core Data; never put it in CloudKit for this product boundary. |
| Audio recordings and recording paths | Local-only | Audio is sensitive and paths can reveal local structure. Keep files under the existing recordings boundary. |
| Meeting titles, app identity, calendar links, timestamps, capture purpose, context items | Local-only | Metadata can reveal who met, when, where, and in which application even without transcript text. |
| Model-performance attempts and diagnostics tied to a transcription | Local-only | Attempts can expose timing, provider/model choices, and meeting relationships. |
| API keys, tokens, provider credentials, custom endpoint secrets | Prohibited | Credentials remain in Keychain; they must never be synchronized or copied into CloudKit records. |
| Vocabulary replacement rules and dictation styles | Local-only for now | Vocabulary can contain names, product terms, or confidential phrases. Sync only after an explicit sensitivity review and per-field opt-in. |
| Appearance, language, recording-indicator preferences, and other non-sensitive UI preferences | Potentially syncable later | Only candidates for a future allowlist. The list must be versioned and reviewed; the default remains local-only. |
| Selected provider/model, custom URLs, integration deep links, scripts | Local-only | These values may reveal infrastructure, accounts, or executable behavior. Do not sync them in a generic settings blob. |

## Privacy and threat model

CloudKit would add a second persistence boundary whose access control, account state, deletion behavior, and schema are outside the current local repository. The relevant threats are:

- accidental inclusion of transcript or meeting metadata in a broad settings record;
- iCloud account/device compromise exposing a larger data surface;
- shared-family or managed Apple ID behavior causing unexpected account visibility;
- stale records surviving local opt-out or app deletion;
- logs, diagnostics, or development containers exposing record payloads;
- schema evolution duplicating or overwriting local values without a reviewed conflict policy.

Private CloudKit storage would reduce broad public discoverability, but it would not make sensitive meeting data appropriate to sync by default. Encryption in transit/at rest is not a substitute for a product-level data classification decision.

## If a narrow preference sync is approved later

The implementation must use a dedicated versioned sync repository, not add CloudKit calls to `AppSettingsStore` or Core Data entities. The first version should have:

- an explicit allowlist of scalar preferences, with a schema version and per-field sensitivity review;
- opt-in disabled by default, clear account/status UI, and local operation when iCloud is unavailable;
- a private database/container with least-privilege entitlements and no public database records;
- per-record ownership tied to the signed-in iCloud account, without sharing;
- deterministic conflict metadata: `updatedAt`, device installation identifier, and schema version;
- last-writer-wins for scalar preferences using server time where available, with a deterministic device-ID tie-break;
- no merge of security-sensitive or list-valued settings until a field-specific policy exists;
- idempotent upsert/delete operations and a no-op re-run migration for schema versions;
- local values preserved when sync is disabled unless the user explicitly requests local reset;
- an opt-out flow that stops writes, deletes the app's private records after confirmation, and retains local data by default;
- explicit handling for account sign-out, quota, permission, network, schema, and partial-write failures;
- tests using an in-memory/mock sync service and synthetic values only; never real user history.

Sync must never block recording, transcription, local save, or settings startup. Offline behavior is local-first: queueing is optional for the future preference repository, but local writes remain authoritative to the active device until a reviewed reconciliation policy says otherwise.

## Rejected alternatives for this slice

- **Sync all Core Data records:** rejected because it crosses the local-first privacy boundary and would require a complete conflict, deletion, migration, and redaction design for sensitive history.
- **Sync transcripts but not audio:** rejected because text and metadata are still sensitive and would create an incomplete, confusing history when audio remains local.
- **Sync UserDefaults wholesale:** rejected because the store includes provider choices, custom URLs, integration data, scripts, and potentially sensitive vocabulary.
- **Use `NSUbiquitousKeyValueStore` for convenience:** rejected as a generic solution because it lacks the per-field record/deletion policy and operational visibility required here.
- **Implement CloudKit before product approval:** rejected because entitlements and remote persistence create external state that cannot be safely rolled back as a local refactor.
- **Prefer cloud sync over local export/import:** rejected for now; local export/import can provide portability without creating a server-side copy of meeting data and should be evaluated first.

## Current architecture evidence

The local boundary is documented in [`storage-architecture.md`](../docs/storage-architecture.md). It confirms that Core Data, recordings, UserDefaults, and Keychain are local owners; no CloudKit container, entitlement, sync repository, conflict policy, or sync-status UI exists today.

## Approval gate

No implementation should start until product/privacy owners approve:

1. the exact syncable field allowlist;
2. the user-facing consent and opt-out/deletion behavior;
3. the iCloud account/container and entitlement model;
4. conflict and migration semantics;
5. testing and operational ownership.

Issue #54 remains open as a deferred P3 decision. The current recommendation is **reject CloudKit for sensitive history and defer narrow preference sync; prioritize local export/import first**.
