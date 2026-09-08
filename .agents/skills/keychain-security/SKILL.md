---
name: keychain-security
description: This skill should be used when the user asks to "store secret in Keychain", "retrieve API key securely", "delete credential", or "harden KeychainManager usage".
---

# Keychain Security

## Role

Use this skill as the canonical owner for credential persistence through Keychain in Verbi.

- Own secure local secret storage and retrieval guidance.
- Keep Keychain usage aligned with the shared Infrastructure abstractions.
- Delegate broader security posture and transport concerns to their specialist owners.

## Scope Boundaries

- Use this skill for local secret persistence through KeychainManager/KeychainProvider.

Guidance for secure credential storage in the B2 modular architecture.

## When to Use

Use this skill when the user asks to store a secret in Keychain, retrieve an API key securely, delete credentials, or harden `KeychainManager` usage.

## Module ownership

- Canonical implementation: `Packages/MeetingAssistantCore/Sources/Infrastructure/Services/KeychainManager.swift`
- Preferred cross-module access: `KeychainProvider` / `DefaultKeychainProvider`

Do not duplicate keychain logic in UI/AI/Data modules.

## Current API shape

Use these abstractions:

```swift
public protocol KeychainProvider: Sendable {
    func store(_ value: String, for key: KeychainManager.Key) throws
    func retrieve(for key: KeychainManager.Key) throws -> String?
    func delete(for key: KeychainManager.Key) throws
    func exists(for key: KeychainManager.Key) -> Bool
    func retrieveAPIKey(for provider: AIProvider) throws -> String?
    func existsAPIKey(for provider: AIProvider) -> Bool
}
```

Provider-specific helpers are available on `KeychainManager`:

- `KeychainManager.apiKeyKey(for:)`
- `KeychainManager.retrieveAPIKey(for:)`
- `KeychainManager.existsAPIKey(for:)`

## Usage patterns

Prefer dependency injection:

```swift
let keychain: KeychainProvider = DefaultKeychainProvider()
let hasKey = keychain.existsAPIKey(for: .openai)
```

Store and retrieve explicit keys:

```swift
try keychain.store(secret, for: .aiAPIKeyOpenAI)
let value = try keychain.retrieve(for: .aiAPIKeyOpenAI)
```

## Security rules

1. Never store secrets in `UserDefaults`.
2. Keep key names scoped and explicit (`aiAPIKeyOpenAI`, `aiAPIKeyAnthropic`, etc.).
3. Treat `errSecItemNotFound` as non-fatal absence; other statuses are failures.
4. Do not log secret values.
5. Keep comments/documentation in English.

## Review checklist

- Is secret handling delegated to `KeychainProvider`/`KeychainManager`?
- Are errors surfaced without leaking secret contents?
- Are legacy fallback behaviors preserved when touching API key migration code?
- Are module boundaries respected (no ad-hoc keychain wrappers outside Infrastructure)?

## References

- `Packages/MeetingAssistantCore/Sources/Infrastructure/Services/KeychainManager.swift`
- `AGENTS.md` (branch workflow + language policy)

