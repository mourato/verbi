# Swift 6.2 Agent Baseline

Verbi's owned Xcode configurations and the MeetingAssistantCore package use
Swift 6.2, complete strict concurrency checking, and explicit
`SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`. UI and lifecycle boundaries keep
their explicit `@MainActor` annotations. This baseline does not change product
behavior, persistence formats, or public APIs.

## Toolchain

Validation uses the supported Xcode 26.6 installation:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build-agent
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test-full-agent
```

Xcode-beta 27.0 / Swift 6.4 currently fails while linking SwiftSyntax 602.0.0
with missing symbols and unrelated CoreAudioTypes/SwiftUICore warnings. Do not
add a product workaround; rerun with the supported `DEVELOPER_DIR` above.

## Formatter and lint

`.swiftformat` declares Swift 6.2, four-space indentation, and the existing
generated/build exclusions. SwiftFormat 0.62.1 must receive this file through
`--base-config`; `--config` can be ignored when the command traverses the app
and package roots.

`make lint` and `make lint-agent` are fail-closed: formatter, linter, and tool
failures return non-zero. Strict SwiftLint uses the tracked
`.swiftlint-baseline.json` to allow only the existing violations; new warnings
return non-zero. `make lint-report` is the explicitly named report-only loop
that shows the pre-existing 284 diagnostic warnings, primarily structural
budgets, number separators, and complexity. New source rewrites must be
justified by a compiler, concurrency, lint, or formatter diagnostic rather than
by speculative cleanup.

Changed-file iteration is available without a second workflow:

```bash
make lint-agent FILES="App/Changed.swift"
```

Ignored SwiftPM resolution files are local dependency caches. They are not
versioned, are not required for guidance validation, and are excluded from
external-input comparison unless deliberately tracked.

## Upgrade procedure

When upgrading Swift or Xcode, update the Xcode settings, `.swift-version`,
`.swiftformat`, this document, and the project overlay together. Run the full
formatter/lint gate, the supported-toolchain build and tests, `make
validate-agent`, `make guidance-check`, and `git diff --check`. Record any
third-party toolchain incompatibility here instead of weakening concurrency
checks or adding broad `@preconcurrency` or `@unchecked Sendable` escapes.
