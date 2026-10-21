#!/bin/bash

# Internal sourced fixture suite used by workflow-test.sh; not a standalone command.

assert_scope_decision() {
    local output="$1"
    local expected_lane="$2"
    local expected_strategy="$3"
    local expected_reason="${4:-}"
    local result_path

    result_path="$(printf '%s\n' "${output}" | sed -n 's/^AGENT_RESULT_JSON=//p' | tail -n 1)"
    test -f "${result_path}" || fail "scope decision result is missing"
    python3 - "${result_path}" "${expected_lane}" "${expected_strategy}" "${expected_reason}" <<'PY'
import json
import sys

path, expected_lane, expected_strategy, expected_reason = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    decision = json.load(handle)["decision"]
assert decision["selectedLane"] == expected_lane
assert decision["strategy"] == expected_strategy
if expected_reason:
    assert decision["reasons"].count(expected_reason) == 1
PY
}

test_scope_check_reuses_decision_file() {
    local fixture
    local decision_file
    local output

    fixture="$(new_fixture)"
    decision_file="${TMP_ROOT}/reused-decision.json"
    printf '%s\n' '{"decision":{"selectedLane":"fast","strategy":"scoped-validation","codeRelevant":false,"guidanceRelevant":true,"changedFiles":["AGENTS.md"],"reasons":[],"targetedTests":[],"diffRange":"fixture decision"}}' > "${decision_file}"
    output="$(cd "${fixture}" && MA_AGENT_LOG_DIR="${TMP_ROOT}/reused-decision" ./scripts/scope-check.sh --agent --decision-file "${decision_file}" --no-build)"
    assert_contains "${output}" "AGENT_STATUS=PASS"
    assert_contains "${output}" "Added lines (fixture decision): 0"
    assert_not_contains "${output}" "No changed files detected"
    assert_contains "${output}" "Guidance passed."
}

test_app_product_swift_uses_mapping() {
    local fixture
    local base
    local head
    local output

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    mkdir -p "${fixture}/App"
    printf '%s\n' 'struct Feature {}' > "${fixture}/App/Feature.swift"
    git -C "${fixture}" add App/Feature.swift
    git -C "${fixture}" commit -qm "app product swift"
    head="$(git -C "${fixture}" rev-parse HEAD)"

    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-app-product" --committed --base "${base}" --head "${head}")"
    assert_scope_decision "${output}" fast scoped-validation
    assert_contains "${output}" "Product source files changed: 1"
    assert_contains "${output}" "Candidate targeted tests: 2"
    assert_contains "${output}" "--file AppCommandStateTests"
    assert_contains "${output}" "--file NavigationServiceTests"
}

test_core_ui_product_swift_without_mapping_is_full() {
    local fixture
    local base
    local head
    local output

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    mkdir -p "${fixture}/Packages/MeetingAssistantCore/Sources/UI"
    printf '%s\n' 'struct Feature {}' > "${fixture}/Packages/MeetingAssistantCore/Sources/UI/Feature.swift"
    git -C "${fixture}" add Packages/MeetingAssistantCore/Sources/UI/Feature.swift
    git -C "${fixture}" commit -qm "core ui product swift"
    head="$(git -C "${fixture}" rev-parse HEAD)"

    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-ui-product" --committed --base "${base}" --head "${head}")"
    assert_scope_decision "${output}" full full-gate "No trustworthy targeted test mapping from changed files"
    assert_contains "${output}" "Candidate targeted tests: 0"
}

test_domain_product_swift_without_mapping_is_full() {
    local fixture
    local base
    local head
    local output

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    mkdir -p "${fixture}/Packages/MeetingAssistantCore/Sources/Domain"
    printf '%s\n' 'public struct PublicLookingFeature {}' > "${fixture}/Packages/MeetingAssistantCore/Sources/Domain/PublicLookingFeature.swift"
    git -C "${fixture}" add Packages/MeetingAssistantCore/Sources/Domain/PublicLookingFeature.swift
    git -C "${fixture}" commit -qm "domain product swift"
    head="$(git -C "${fixture}" rev-parse HEAD)"

    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-domain-product" --committed --base "${base}" --head "${head}")"
    assert_scope_decision "${output}" full full-gate "No trustworthy targeted test mapping from changed files"
    assert_contains "${output}" "Candidate targeted tests: 0"
}

test_test_only_swift_stays_fast_when_mapped() {
    local fixture
    local base
    local head
    local output

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'test alpha' > "${fixture}/Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/AlphaTests.swift"
    git -C "${fixture}" add Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/AlphaTests.swift
    git -C "${fixture}" commit -qm "test-only swift"
    head="$(git -C "${fixture}" rev-parse HEAD)"

    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-test-only" --committed --base "${base}" --head "${head}")"
    assert_scope_decision "${output}" fast scoped-validation
    assert_contains "${output}" "Product source files changed: 0"
    assert_contains "${output}" "Candidate targeted tests: 1"
    assert_contains "${output}" "--file AlphaTests"
}

test_nine_test_files_do_not_trigger_product_churn() {
    local fixture
    local base
    local head
    local index
    local output

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    for index in $(seq 1 9); do
        printf '%s\n' "test-${index}" > "${fixture}/Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/Boundary${index}Tests.swift"
    done
    git -C "${fixture}" add Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests
    git -C "${fixture}" commit -qm "nine test-only files"
    head="$(git -C "${fixture}" rev-parse HEAD)"

    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-nine-tests" --committed --base "${base}" --head "${head}")"
    assert_scope_decision "${output}" fast intermediate-gate
    assert_contains "${output}" "Swift files changed: 9"
    assert_contains "${output}" "Product source files changed: 0"
    assert_not_contains "${output}" "High product source-file churn"
}

test_guidance_and_resource_boundaries_stay_fast() {
    local fixture
    local base
    local head
    local output

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' '# Fixture guidance' > "${fixture}/AGENTS.md"
    git -C "${fixture}" add AGENTS.md
    git -C "${fixture}" commit -qm "guidance-only boundary"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-guidance" --committed --base "${base}" --head "${head}")"
    assert_scope_decision "${output}" fast scoped-validation
    assert_contains "${output}" "[dry-run] make guidance-check"
    assert_not_contains "${output}" "make build-test"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    mkdir -p "${fixture}/Packages/MeetingAssistantCore/Sources/Common/Resources/en.lproj"
    printf '%s\n' '"fixture" = "Fixture";' > "${fixture}/Packages/MeetingAssistantCore/Sources/Common/Resources/en.lproj/Localizable.strings"
    git -C "${fixture}" add Packages/MeetingAssistantCore/Sources/Common/Resources/en.lproj/Localizable.strings
    git -C "${fixture}" commit -qm "resource-only boundary"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-resource" --committed --base "${base}" --head "${head}")"
    assert_scope_decision "${output}" fast scoped-validation
    assert_contains "${output}" "Only non-code files changed"
    assert_not_contains "${output}" "make build-test"
}

test_existing_full_trigger_boundaries_remain_full() {
    local fixture
    local base
    local head
    local output

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' '#!/bin/bash' > "${fixture}/scripts/changed.sh"
    git -C "${fixture}" add scripts/changed.sh
    git -C "${fixture}" commit -qm "script boundary"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-script" --committed --base "${base}" --head "${head}")"
    assert_scope_decision "${output}" full full-gate "Build/release/test infrastructure changed (scripts/changed.sh)"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    mkdir -p "${fixture}/Packages/MeetingAssistantCore/Sources/Audio"
    printf '%s\n' 'struct AudioFeature {}' > "${fixture}/Packages/MeetingAssistantCore/Sources/Audio/AudioFeature.swift"
    git -C "${fixture}" add Packages/MeetingAssistantCore/Sources/Audio/AudioFeature.swift
    git -C "${fixture}" commit -qm "audio boundary"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-audio" --committed --base "${base}" --head "${head}")"
    assert_scope_decision "${output}" full full-gate "High-risk path changed (Packages/MeetingAssistantCore/Sources/Audio/AudioFeature.swift)"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    mkdir -p "${fixture}/Packages/MeetingAssistantCore/Sources/Data"
    printf '%s\n' 'struct DataFeature {}' > "${fixture}/Packages/MeetingAssistantCore/Sources/Data/DataFeature.swift"
    git -C "${fixture}" add Packages/MeetingAssistantCore/Sources/Data/DataFeature.swift
    git -C "${fixture}" commit -qm "data boundary"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-data" --committed --base "${base}" --head "${head}")"
    assert_scope_decision "${output}" full full-gate "High-risk path changed (Packages/MeetingAssistantCore/Sources/Data/DataFeature.swift)"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    mkdir -p "${fixture}/Packages/MeetingAssistantCore/Sources/UI" \
        "${fixture}/Packages/MeetingAssistantCore/Sources/Domain"
    printf '%s\n' 'struct UIChange {}' > "${fixture}/Packages/MeetingAssistantCore/Sources/UI/UIChange.swift"
    printf '%s\n' 'struct DomainChange {}' > "${fixture}/Packages/MeetingAssistantCore/Sources/Domain/DomainChange.swift"
    git -C "${fixture}" add Packages/MeetingAssistantCore/Sources
    git -C "${fixture}" commit -qm "cross-module boundary"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-cross-module" --committed --base "${base}" --head "${head}")"
    assert_scope_decision "${output}" full full-gate "Cross-module change detected (2 modules touched)"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'test alpha' > "${fixture}/Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/AlphaTests.swift"
    git -C "${fixture}" add Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/AlphaTests.swift
    git -C "${fixture}" commit -qm "force-full boundary"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/scope-force-full" --committed --base "${base}" --head "${head}" --force-full)"
    assert_scope_decision "${output}" full full-gate "Forced full gate by flag (--force-full)"
}

test_requested_fast_reports_strongest_executed_lane() {
    local fixture
    local base
    local head
    local first_fingerprint
    local output
    local result_path
    local second_fingerprint
    local step_log="${TMP_ROOT}/requested-fast-strongest-steps.log"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    mkdir -p "${fixture}/App"
    printf '%s\n' 'struct FastRequestFeature {}' > "${fixture}/App/FastRequestFeature.swift"
    git -C "${fixture}" add App/FastRequestFeature.swift
    git -C "${fixture}" commit -qm "requested fast product boundary"
    head="$(git -C "${fixture}" rev-parse HEAD)"

    output="$(cd "${fixture}" && WORKFLOW_STEP_LOG="${step_log}" MA_AGENT_LOG_DIR="${TMP_ROOT}/requested-fast-strongest" ./scripts/validate-agent.sh --lane fast --committed --base "${base}" --head "${head}" --no-reuse --agent)"
    assert_contains "${output}" "AGENT_STATUS=PASS"
    assert_contains "${output}" "AGENT_REUSED=0"
    first_fingerprint="$(printf '%s\n' "${output}" | sed -n 's/^AGENT_VALIDATION_FINGERPRINT=//p' | tail -n 1)"
    test -n "${first_fingerprint}" || fail "requested Fast fingerprint is missing"
    result_path="$(printf '%s\n' "${output}" | sed -n 's/^AGENT_RESULT_JSON=//p' | tail -n 1)"
    python3 - "${result_path}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    result = json.load(handle)
assert result["decision"]["selectedLane"] == "fast"
assert result["decision"]["strategy"] == "scoped-validation"
assert [command["name"] for command in result["commands"]] == ["scope-check"]
PY

    output="$(cd "${fixture}" && WORKFLOW_STEP_LOG="${step_log}" MA_AGENT_LOG_DIR="${TMP_ROOT}/requested-fast-strongest" ./scripts/validate-agent.sh --lane fast --committed --base "${base}" --head "${head}" --agent)"
    assert_contains "${output}" "AGENT_STATUS=PASS"
    assert_contains "${output}" "Reusing PASS evidence"
    assert_contains "${output}" "AGENT_REUSED=1"
    second_fingerprint="$(printf '%s\n' "${output}" | sed -n 's/^AGENT_VALIDATION_FINGERPRINT=//p' | tail -n 1)"
    test "${second_fingerprint}" = "${first_fingerprint}" || fail "requested Fast fingerprint changed before cache reuse"
    test "$(grep -Fxc 'scope-check' "${step_log}")" -eq 1
    test "$(grep -Fxc 'lint' "${step_log}" || true)" -eq 0
    test "$(grep -Fxc 'build-test' "${step_log}" || true)" -eq 0
}

test_app_product_swift_uses_mapping
test_core_ui_product_swift_without_mapping_is_full
test_domain_product_swift_without_mapping_is_full
test_scope_check_reuses_decision_file
test_test_only_swift_stays_fast_when_mapped
test_nine_test_files_do_not_trigger_product_churn
test_guidance_and_resource_boundaries_stay_fast
test_existing_full_trigger_boundaries_remain_full
test_requested_fast_reports_strongest_executed_lane
