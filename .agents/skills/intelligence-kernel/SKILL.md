---
name: intelligence-kernel
description: This skill should be used when the user asks to "change meeting post-processing", "work with canonical summary schema", "tune intelligence kernel modes", or "update summary benchmark gates".
---

# Intelligence Kernel

## Role

Operational guidance for the reusable intelligence kernel, canonical summary contract, and summary-quality regression gates.

## Scope Boundary

- Use this skill for intelligence-kernel contracts, mode routing, trust flags, and benchmark gates.
- Use `../data-persistence/SKILL.md` when the main concern is storage or migration rather than kernel behavior.
- Use global `delivery-workflow` when the main concern is command selection and verification policy.

## When to Use

Use this skill for:
- `IntelligenceKernelMode` routing changes (`meeting`, `dictation`, `assistant`)
- Canonical summary contract/schema updates
- Trust-flags validation behavior changes
- Summary benchmark thresholds, baseline, or gate mode updates
- Meeting post-processing and grounded Q&A changes that must remain mode-aware

## Canonical Contract Surface

Primary files:
- `Packages/MeetingAssistantCore/Sources/Domain/Models/IntelligenceKernel.swift`
- `Packages/MeetingAssistantCore/Sources/Domain/Models/CanonicalSummary.swift`
- `Packages/MeetingAssistantCore/Sources/AI/Services/Output/CanonicalSummaryPipeline.swift`

Canonical summary fields:
- `schemaVersion`, `generatedAt`, `summary`, `keyPoints`, `decisions`, `actionItems`, `openQuestions`, `trustFlags`

Trust flags:
- `isGroundedInTranscript`
- `containsSpeculation`
- `isHumanReviewed`
- `confidenceScore` (`0...1`)

Validation invariants:
- `schemaVersion` must be within `1...CanonicalSummary.currentSchemaVersion`
- `summary` must be non-empty after trimming
- list entries (`keyPoints`, `decisions`, `openQuestions`) cannot contain empty strings
- each `actionItems.title` must be non-empty
- `trustFlags.confidenceScore` must be in `0...1`

## Mode Gating and Rollout

Gate behavior through feature flags and settings adapters:
- `FeatureFlags.enableIntelligenceKernel`
- `FeatureFlags.enableMeetingIntelligenceMode`
- `FeatureFlags.enableDictationIntelligenceMode`
- `FeatureFlags.enableAssistantIntelligenceMode`
- `AppSettingsStore.intelligenceKernelEnabled`
- `AppSettingsStore.isIntelligenceKernelModeEnabled(_:)`

Rule: call sites should stay on shared kernel contracts and avoid mode-specific branching in UI surfaces.

## Persistence and Fallback Invariants

- Preserve model-selection persistence across create, reload, edit, and delete flows; changes must be covered by contract tests.
- When conversation state is missing or partial, use a schema-safe deterministic fallback rather than inventing context or silently dropping the request.
- Update kernel-facing contract tests whenever persistence fields cross AI, Data, Domain, or UI boundaries.

## Benchmark and Regression Gates

Commands:

```bash
make benchmark-summary
AGENT=1 make benchmark-summary
./scripts/run-summary-benchmark.sh --enforce
./scripts/run-summary-benchmark.sh --report-only --record-baseline
```

Gate control:
- `MA_SUMMARY_BENCHMARK_GATE_MODE=report-only` (default)
- `MA_SUMMARY_BENCHMARK_GATE_MODE=enforce`

Artifacts:
- Fixtures: `Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/Resources/Benchmarks/summary-benchmark-fixtures.v1.json`
- Baseline: `Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/Resources/Benchmarks/summary-benchmark-baseline.v1.json`
- Result: `/tmp/summary-benchmark-result.v1.json` (or `/tmp/ma-agent/summary-benchmark-result.v1.json` in agent mode)

## Change Checklist

1. Apply `reuse -> extend -> create` before adding new kernel-specific abstractions.
2. If schema changes, update `CanonicalSummary.currentSchemaVersion` and persistence compatibility.
3. Keep fallback/repair flows deterministic; avoid introducing non-deterministic parser behavior.
4. Add/adjust tests in kernel contracts, persistence validation, and benchmark regression suites.
5. Run `make build-test`; for rubric changes, run benchmark commands.

## Provider and Prompt Invariants

- Use provider-selection domain values across UI, recording, and transcription clients; avoid raw model strings in retry or mode-aware flows.
- Segment history retry actions by capture purpose and readiness. Hide providers or models that are not fully configured or compatible.
- Keep meeting retries local-only until the meeting configuration model explicitly supports remote providers.
- Route prompt assembly through the shared request resolver whenever mode, model, context metadata, or prompt type can affect output.
- Keep simple-model optimizations scoped to the matching mode and prompt identity; preserve meeting and custom-prompt contracts.
- Treat context metadata as disambiguation and test that tagged context is not duplicated in request bodies.

## Routing

- Cross-module API boundary decisions -> `../architecture/SKILL.md`
- Persistence and migration impact -> `../data-persistence/SKILL.md`
- Validation gates and test strategy -> global `delivery-workflow`
