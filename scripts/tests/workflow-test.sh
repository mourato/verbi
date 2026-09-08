#!/bin/bash

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'USAGE'
Usage: ./scripts/tests/workflow-test.sh

Description: Run deterministic fixture tests for the agent validation and delivery workflow. No Xcode build is performed.
USAGE
    exit 0
fi

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/verbi-workflow-test.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    printf '%s\n' "${haystack}" | grep -Fq -- "${needle}" || fail "missing: ${needle}"
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    if printf '%s\n' "${haystack}" | grep -Fq -- "${needle}"; then
        fail "unexpected: ${needle}"
    fi
}

new_fixture() {
    local fixture="${TMP_ROOT}/repo"
    rm -rf "${fixture}"
    mkdir -p "${fixture}/scripts/lib" \
        "${fixture}/scripts/config" \
        "${fixture}/scripts/tests" \
        "${fixture}/Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests" \
        "${fixture}/MeetingAssistant.xcworkspace/xcshareddata/swiftpm"

    cp "${SCRIPT_ROOT}/scripts/scope-check.sh" "${fixture}/scripts/scope-check.sh"
    cp "${SCRIPT_ROOT}/scripts/validate-agent.sh" "${fixture}/scripts/validate-agent.sh"
    cp "${SCRIPT_ROOT}/scripts/hooks/pre-push" "${fixture}/scripts/hooks-pre-push"
    cp "${SCRIPT_ROOT}/scripts/lib/agent-output.sh" "${fixture}/scripts/lib/agent-output.sh"
    cp "${SCRIPT_ROOT}/scripts/config/test-target-mapping.conf" "${fixture}/scripts/config/test-target-mapping.conf"
    cp "${SCRIPT_ROOT}/scripts/tests/workflow-fixture-step.sh" "${fixture}/scripts/tests/workflow-fixture-step.sh"
    chmod +x "${fixture}/scripts/scope-check.sh"
    chmod +x "${fixture}/scripts/validate-agent.sh" "${fixture}/scripts/tests/workflow-fixture-step.sh"
    chmod +x "${fixture}/scripts/hooks-pre-push"

    touch "${fixture}/Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/AlphaTests.swift"
    touch "${fixture}/Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/BetaTests.swift"
    printf '%s\n' 'fixture baseline' > "${fixture}/README.md"
    printf '%s\n' \
        'Packages/MeetingAssistantCore/Package.resolved' \
        'MeetingAssistant.xcworkspace/xcshareddata/swiftpm/Package.resolved' > "${fixture}/.gitignore"
    printf '%s\n' \
        'scope-check-agent:' \
        $'\t@if [ "$${WORKFLOW_FAIL_IF_PATH_PRESENT:-0}" = "1" ] && [ -e Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/HeadOnlyTests.swift ]; then echo "HEAD_REF marker present" >&2; exit 77; fi' \
        $'\t@if [ "$${WORKFLOW_USE_REAL_SCOPE_CHECK:-0}" = "1" ]; then MA_AGENT_MODE=1 ./scripts/scope-check.sh --agent $(ARGS); else ./scripts/tests/workflow-fixture-step.sh scope-check; fi' \
        'validate-agent:' \
        $'\t@./scripts/validate-agent.sh $(ARGS)' \
        'lint-agent:' \
        $'\t@./scripts/tests/workflow-fixture-step.sh lint' \
        'build-agent:' \
        $'\t@./scripts/tests/workflow-fixture-step.sh build' \
        'lint-strict-agent:' \
        $'\t@./scripts/tests/workflow-fixture-step.sh lint' \
        'build-test:' \
        $'\t@./scripts/tests/workflow-fixture-step.sh build-test' \
        'guidance-check:' \
        $'\t@./scripts/tests/workflow-fixture-step.sh guidance' \
        > "${fixture}/Makefile"

    git -C "${fixture}" init -q
    git -C "${fixture}" branch -M main
    git -C "${fixture}" config user.email workflow-test@example.invalid
    git -C "${fixture}" config user.name workflow-test
    git -C "${fixture}" add .
    git -C "${fixture}" commit -qm baseline
    git -C "${fixture}" update-ref refs/remotes/origin/main HEAD
    git -C "${fixture}" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
    git -C "${fixture}" update-ref refs/remotes/alt/main HEAD
    git -C "${fixture}" symbolic-ref refs/remotes/alt/HEAD refs/remotes/alt/main
    printf '%s\n' "${fixture}"
}

test_deleted_paths_are_classified() {
    local fixture
    local base
    local head
    local output

    fixture="$(new_fixture)"
    printf '%s\n' 'removed source' > "${fixture}/Removed.swift"
    printf '%s\n' 'removed test' > "${fixture}/Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/RemovedTests.swift"
    printf '%s\n' 'obsolete infra' > "${fixture}/scripts/obsolete.sh"
    git -C "${fixture}" add .
    git -C "${fixture}" commit -qm "add deletion fixtures"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    git -C "${fixture}" rm -q Removed.swift Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/RemovedTests.swift scripts/obsolete.sh
    git -C "${fixture}" commit -qm "delete fixtures"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/deletions" --committed --base "${base}" --head "${head}")"
    assert_contains "${output}" "Changed files: 3"
    assert_contains "${output}" "Build/release/test infrastructure changed (scripts/obsolete.sh)"
    assert_not_contains "${output}" "No changed files detected"
}

test_committed_tree_isolated_and_invalid_flags() {
    local fixture
    local base
    local head
    local output
    local invalid_status
    local result_path
    local command_log

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'must exist in committed head' > "${fixture}/Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/HeadOnlyTests.swift"
    git -C "${fixture}" add Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/HeadOnlyTests.swift
    git -C "${fixture}" commit -qm "head-only marker"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    rm -f "${fixture}/Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/HeadOnlyTests.swift"

    set +e
    output="$(cd "${fixture}" && WORKFLOW_FAIL_IF_PATH_PRESENT=1 MA_AGENT_LOG_DIR="${TMP_ROOT}/head-isolation" ./scripts/validate-agent.sh --lane fast --committed --base "${base}" --head "${head}" --no-reuse --agent 2>&1)"
    invalid_status=$?
    set -e
    test "${invalid_status}" -eq 1
    assert_contains "${output}" "AGENT_STATUS=FAIL"
    result_path="$(printf '%s\n' "${output}" | sed -n 's/^AGENT_RESULT_JSON=//p' | tail -n 1)"
    command_log="$(python3 - "${result_path}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["commands"][0]["log"])
PY
    )"
    assert_contains "$(cat "${command_log}")" "HEAD_REF marker present"

    set +e
    output="$(cd "${fixture}" && MA_AGENT_LOG_DIR="${TMP_ROOT}/invalid-head" ./scripts/validate-agent.sh --lane fast --committed --base "${base}" --head missing-head --agent 2>&1)"
    invalid_status=$?
    set -e
    test "${invalid_status}" -eq 1
    assert_contains "${output}" "could not materialize committed head 'missing-head'"
    assert_not_contains "${output}" "AGENT_STATUS=PASS"

    set +e
    output="$(cd "${fixture}" && ./scripts/validate-agent.sh --lane fast --staged --committed --base "${base}" --head "${head}" 2>&1)"
    invalid_status=$?
    set -e
    test "${invalid_status}" -eq 1
    assert_contains "${output}" "--staged and --committed are mutually exclusive"
    set +e
    output="$(cd "${fixture}" && ./scripts/validate-agent.sh --lane fast --committed --empty-base --base "${base}" --head "${head}" 2>&1)"
    invalid_status=$?
    set -e
    test "${invalid_status}" -eq 1
    assert_contains "${output}" "--empty-base and --base are mutually exclusive"
    test "$(git -C "${fixture}" worktree list | wc -l | tr -d ' ')" -eq 1
}

test_committed_and_staged_boundaries() {
    local fixture
    local base
    local head
    local output
    local status

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'committed change' > "${fixture}/Committed.swift"
    git -C "${fixture}" add Committed.swift
    git -C "${fixture}" commit -qm committed
    head="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'unstaged noise' >> "${fixture}/README.md"
    printf '%s\n' 'untracked noise' > "${fixture}/Untracked.swift"
    output="$(cd "${fixture}" && ./scripts/scope-check.sh --dry-run --committed --base "${base}" --head "${head}")"
    assert_contains "${output}" "Added lines (${base} -> ${head}): 1"
    assert_not_contains "${output}" "Untracked.swift"
    assert_not_contains "${output}" "unstaged noise"
    output="$(cd "${fixture}" && ./scripts/scope-check.sh --dry-run --committed --empty-base --head "${head}")"
    assert_contains "${output}" "Added lines (empty tree -> ${head}):"

    rm -f "${fixture}/Untracked.swift"
    git -C "${fixture}" restore README.md
    printf '%s\n' 'staged change' > "${fixture}/Alpha.swift"
    git -C "${fixture}" add Alpha.swift
    output="$(cd "${fixture}" && ./scripts/scope-check.sh --dry-run --staged --base "${head}")"
    assert_contains "${output}" "Added lines (${head} -> staged index): 1"

    set +e
    printf '%s\n' 'unstaged' >> "${fixture}/README.md"
    output="$(cd "${fixture}" && ./scripts/scope-check.sh --dry-run --staged --base "${head}" 2>&1)"
    status=$?
    set -e
    test "${status}" -eq 1
    assert_contains "${output}" "--staged requires no unstaged tracked changes"
}

test_staged_receipt_reused_after_commit() {
    local fixture
    local base
    local head
    local output
    local log_root="${TMP_ROOT}/staged-receipt"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'receipt change' > "${fixture}/Alpha.swift"
    git -C "${fixture}" add Alpha.swift
    output="$(validate_output "${fixture}" "${log_root}" --lane fast --staged --base "${base}" --no-reuse)"
    assert_contains "${output}" "AGENT_STATUS=PASS"
    git -C "${fixture}" commit -qm receipt
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(validate_output "${fixture}" "${log_root}" --lane fast --committed --base "${base}" --head "${head}")"
    assert_contains "${output}" "Reusing PASS evidence"
    assert_contains "${output}" "AGENT_REUSED=1"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'receipt change with external input' > "${fixture}/Alpha.swift"
    git -C "${fixture}" add Alpha.swift
    output="$(validate_output "${fixture}" "${TMP_ROOT}/external-input" --lane fast --staged --base "${base}" --no-reuse)"
    assert_contains "${output}" "AGENT_STATUS=PASS"
    printf '%s\n' '{"pins": "ignored local lockfile"}' > "${fixture}/Packages/MeetingAssistantCore/Package.resolved"
    printf '%s\n' '{"pins": "ignored workspace lockfile"}' > "${fixture}/MeetingAssistant.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    git -C "${fixture}" commit -qm "external input receipt"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/external-input" --lane fast --committed --base "${base}" --head "${head}")"
    assert_not_contains "${output}" "Cache disabled: External gate inputs differ"
    assert_contains "${output}" "AGENT_STATUS=PASS"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/external-input" --lane fast --committed --base "${base}" --head "${head}")"
    assert_contains "${output}" "Reusing PASS evidence"
    assert_contains "${output}" "AGENT_REUSED=1"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' '{"pins": "tracked baseline"}' > "${fixture}/Packages/MeetingAssistantCore/Package.resolved"
    printf '%s\n' 'tracked lockfile change' > "${fixture}/Alpha.swift"
    git -C "${fixture}" add -f Packages/MeetingAssistantCore/Package.resolved Alpha.swift
    git -C "${fixture}" commit -qm "tracked lockfile baseline"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/tracked-external-input" --lane fast --committed --base "${base}" --head "${head}" --no-reuse)"
    assert_contains "${output}" "AGENT_STATUS=PASS"
    printf '%s\n' '{"pins": "dirty tracked drift"}' > "${fixture}/Packages/MeetingAssistantCore/Package.resolved"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/tracked-external-input" --lane fast --committed --base "${base}" --head "${head}")"
    assert_contains "${output}" "Cache disabled: External gate inputs differ"
    assert_not_contains "${output}" "Reusing PASS evidence"
    assert_contains "${output}" "AGENT_REUSED=0"
}

test_pre_push_skips_build_and_test() {
    local fixture
    local base
    local head
    local output
    local step_log="${TMP_ROOT}/pre-push-no-steps.log"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' '#!/bin/bash' 'echo infra' > "${fixture}/scripts/push-infra.sh"
    chmod +x "${fixture}/scripts/push-infra.sh"
    git -C "${fixture}" add scripts/push-infra.sh
    git -C "${fixture}" commit -qm "scripts push fixture"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    : > "${step_log}"
    output="$(cd "${fixture}" && printf 'refs/heads/main %s refs/heads/main %s\n' "${head}" "${base}" | WORKFLOW_STEP_LOG="${step_log}" MA_AGENT_LOG_DIR="${TMP_ROOT}/pre-push-scripts" ./scripts/hooks-pre-push)"
    assert_contains "${output}" "Pre-push: refs/heads/main"
    assert_contains "${output}" "build/test gates are owned by end-of-task development"
    assert_not_contains "${output}" "gate: Option C"
    assert_not_contains "${output}" "Running lint-strict:"
    assert_not_contains "${output}" "Running build-test:"
    assert_not_contains "${output}" "AGENT_STATUS="
    test ! -s "${step_log}"
}

test_pre_commit_staged_format() {
    local fixture
    local toolchain_dir
    local output
    local partial_index_after
    local partial_index_before
    local partial_worktree_after
    local partial_worktree_before
    local staged_blob
    local spaced_staged_blob
    local status
    local unstaged_blob

    fixture="$(new_fixture)"
    toolchain_dir="${TMP_ROOT}/pre-commit-tools"
    mkdir -p "${toolchain_dir}"

    cat > "${toolchain_dir}/swiftformat" <<'EOF'
#!/bin/bash
file=""
lint=0
for arg in "$@"; do
    case "$arg" in
        --lint) lint=1 ;;
        --config) ;;
        *) file="$arg" ;;
    esac
done
[ -n "$file" ] || exit 0
if [ "$lint" -eq 1 ]; then
    grep -q 'UNFORMATTED' "$file" && exit 1 || exit 0
fi
if grep -q 'UNFORMATTED' "$file"; then
    sed -i.bak 's/UNFORMATTED//' "$file"
    rm -f "${file}.bak"
fi
exit 0
EOF

    cat > "${toolchain_dir}/swiftlint" <<'EOF'
#!/bin/bash
fix=0
quiet=0
files=()
for arg in "$@"; do
    case "$arg" in
        --fix) fix=1 ;;
        --config|--quiet) ;;
        lint) ;;
        *) files+=("$arg") ;;
    esac
done
if [ "$fix" -eq 1 ]; then
    for f in "${files[@]}"; do
        [ -f "$f" ] || continue
        if grep -q 'AUTOFIX' "$f"; then
            sed -i.bak 's/AUTOFIX//' "$f"
            rm -f "${f}.bak"
        fi
    done
fi
for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    grep -q 'LINTFAIL' "$f" && exit 1
done
exit 0
EOF
    chmod +x "${toolchain_dir}/swiftformat" "${toolchain_dir}/swiftlint"

    mkdir -p "${fixture}/scripts/hooks"
    cp "${SCRIPT_ROOT}/scripts/hooks/pre-commit" "${fixture}/scripts/hooks/pre-commit"
    chmod +x "${fixture}/scripts/hooks/pre-commit"
    touch "${fixture}/.swiftformat" "${fixture}/.swiftlint.yml"

    printf 'UNFORMATTED let staged = 1\n' > "${fixture}/Staged.swift"
    printf 'UNFORMATTED let unstaged = 2\n' > "${fixture}/Unstaged.swift"
    git -C "${fixture}" add Staged.swift Unstaged.swift
    git -C "${fixture}" commit -qm "tracked swift fixtures"
    printf 'UNFORMATTED let staged = 2\n' > "${fixture}/Staged.swift"
    printf 'UNFORMATTED let unstaged = 3\n' > "${fixture}/Unstaged.swift"
    printf 'UNFORMATTED let spaced = 4\n' > "${fixture}/Path With Space.swift"
    git -C "${fixture}" add Staged.swift "Path With Space.swift"

    output="$(cd "${fixture}" && PATH="${toolchain_dir}:${PATH}" ./scripts/hooks/pre-commit 2>&1)"
    assert_contains "${output}" "Applying SwiftFormat"
    assert_contains "${output}" "Re-staging formatted Swift files"
    assert_contains "${output}" "pre-commit checks passed"
    assert_contains "${output}" "run end-of-task validate-agent before push when behavior changed"
    assert_not_contains "${output}" "pre-push validates or reuses the exact committed range"
    assert_not_contains "${output}" "pre-push is light unless auto=Full"

    staged_blob="$(git -C "${fixture}" show :Staged.swift)"
    spaced_staged_blob="$(git -C "${fixture}" show ':Path With Space.swift')"
    unstaged_blob="$(cat "${fixture}/Unstaged.swift")"
    printf '%s' "${staged_blob}" | grep -Fq 'UNFORMATTED' && fail "staged index still contains UNFORMATTED"
    printf '%s' "${spaced_staged_blob}" | grep -Fq 'UNFORMATTED' && fail "spaced staged path still contains UNFORMATTED"
    assert_contains "${spaced_staged_blob}" "let spaced = 4"
    printf '%s' "${unstaged_blob}" | grep -Fq 'UNFORMATTED' || fail "unstaged working tree should remain unformatted"

    printf 'LINTFAIL let blocked = 1\n' > "${fixture}/Blocked.swift"
    git -C "${fixture}" add Blocked.swift
    set +e
    output="$(cd "${fixture}" && PATH="${toolchain_dir}:${PATH}" ./scripts/hooks/pre-commit 2>&1)"
    status=$?
    set -e
    test "${status}" -eq 1
    assert_contains "${output}" "SwiftLint violations remain"

    git -C "${fixture}" restore --staged Blocked.swift
    rm -f "${fixture}/Blocked.swift"
    output="$(cd "${fixture}" && PATH="${toolchain_dir}:${PATH}" SKIP_LINT=1 ./scripts/hooks/pre-commit 2>&1)"
    assert_contains "${output}" "Lint/format checks skipped via SKIP_LINT=1"

    printf 'let original = 1\n' > "${fixture}/Partial.swift"
    git -C "${fixture}" add Partial.swift
    git -C "${fixture}" commit -qm "partial staging baseline"
    printf 'UNFORMATTED let stagedPartial = 2\n' > "${fixture}/Partial.swift"
    git -C "${fixture}" add Partial.swift
    printf 'UNFORMATTED let stagedPartial = 2\nlet unstagedPartial = 3\n' > "${fixture}/Partial.swift"
    partial_index_before="$(git -C "${fixture}" show :Partial.swift)"
    partial_worktree_before="$(cat "${fixture}/Partial.swift")"
    cat > "${fixture}/scripts/hooks/first-commit-version-bump.sh" <<'EOF'
#!/bin/bash
printf 'called\n' > .daily-bump-called
printf 'let bumpAbsorbedUserWork = true\n' >> Partial.swift
git add Partial.swift
EOF
    chmod +x "${fixture}/scripts/hooks/first-commit-version-bump.sh"

    set +e
    output="$(cd "${fixture}" && PATH="${toolchain_dir}:${PATH}" FORCE_DAILY_VERSION_BUMP=1 SKIP_LINT=1 ./scripts/hooks/pre-commit 2>&1)"
    status=$?
    set -e

    test "${status}" -eq 1
    assert_contains "${output}" "Cannot autofix partially staged Swift files"
    assert_contains "${output}" "Partial.swift"
    partial_index_after="$(git -C "${fixture}" show :Partial.swift)"
    partial_worktree_after="$(cat "${fixture}/Partial.swift")"
    test "${partial_index_after}" = "${partial_index_before}" || fail "partial-staging hook changed the index"
    test "${partial_worktree_after}" = "${partial_worktree_before}" || fail "partial-staging hook changed the worktree"
    test "${partial_index_after}" != "${partial_worktree_after}" || fail "partial-staging fixture did not preserve distinct index and worktree content"
    test ! -e "${fixture}/.daily-bump-called" || fail "daily bump ran before the partial-staging preflight"

    fixture="$(new_fixture)"
    mkdir -p "${fixture}/scripts/hooks" \
        "${fixture}/Packages/MeetingAssistantCore/Sources/Common"
    cp "${SCRIPT_ROOT}/scripts/hooks/pre-commit" "${fixture}/scripts/hooks/pre-commit"
    chmod +x "${fixture}/scripts/hooks/pre-commit"
    touch "${fixture}/.swiftformat" "${fixture}/.swiftlint.yml"
    cat > "${fixture}/scripts/hooks/first-commit-version-bump.sh" <<'EOF'
#!/bin/bash
printf 'called\n' > .daily-bump-called
printf 'UNFORMATTED public let appVersion = "2.0"\n' > Packages/MeetingAssistantCore/Sources/Common/AppVersion.swift
git add Packages/MeetingAssistantCore/Sources/Common/AppVersion.swift
EOF
    chmod +x "${fixture}/scripts/hooks/first-commit-version-bump.sh"

    output="$(cd "${fixture}" && PATH="${toolchain_dir}:${PATH}" FORCE_DAILY_VERSION_BUMP=1 ./scripts/hooks/pre-commit 2>&1)"
    assert_contains "${output}" "Found 1 staged Swift file"
    assert_contains "${output}" "Applying SwiftFormat"
    test -e "${fixture}/.daily-bump-called" || fail "clean daily bump fixture was not invoked"
    staged_blob="$(git -C "${fixture}" show :Packages/MeetingAssistantCore/Sources/Common/AppVersion.swift)"
    if printf '%s' "${staged_blob}" | grep -Fq 'UNFORMATTED'; then
        fail "AppVersion.swift staged by daily bump was not formatted"
    fi
}

test_pre_push_protocol() {
    local fixture
    local base
    local head
    local output
    local status

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'push change' > "${fixture}/Alpha.swift"
    git -C "${fixture}" add Alpha.swift
    git -C "${fixture}" commit -qm push
    local first_head
    first_head="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'second push commit' > "${fixture}/Beta.swift"
    git -C "${fixture}" add Beta.swift
    git -C "${fixture}" commit -qm "second push"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'local-only' >> "${fixture}/README.md"
    printf '%s\n' 'local-untracked' > "${fixture}/local-only.swift"
    output="$(cd "${fixture}" && printf 'refs/heads/main %s refs/heads/main 0000000000000000000000000000000000000000\n' "${head}" | MA_AGENT_LOG_DIR="${TMP_ROOT}/pre-push" ./scripts/hooks-pre-push alt https://alt.example.invalid/prisma.git)"
    assert_contains "${output}" "Pre-push: refs/heads/main"
    assert_contains "${output}" "remote: alt"
    assert_contains "${output}" "build/test gates are owned by end-of-task development"
    assert_not_contains "${output}" "alt.example.invalid"
    assert_not_contains "${output}" "gate: Option C"
    assert_not_contains "${output}" "Running lint-strict:"
    assert_not_contains "${output}" "Running build-test:"
    assert_not_contains "${output}" "AGENT_STATUS="
    assert_not_contains "${output}" "local-only.swift"

    output="$(cd "${fixture}" && printf 'refs/heads/main %s refs/heads/main %s\n' "${head}" "${first_head}" | MA_AGENT_LOG_DIR="${TMP_ROOT}/pre-push-incremental" ./scripts/hooks-pre-push alt https://alt.example.invalid/prisma.git)"
    assert_contains "${output}" "remote tip: ${first_head}"
    assert_contains "${output}" "build/test gates are owned by end-of-task development"
    assert_not_contains "${output}" "Running lint-strict:"
    assert_not_contains "${output}" "Running build-test:"

    output="$(cd "${fixture}" && printf 'refs/heads/main %s refs/heads/main 0000000000000000000000000000000000000000\n' "${head}" | MA_AGENT_LOG_DIR="${TMP_ROOT}/pre-push-direct-url" ./scripts/hooks-pre-push 'https://alice:s3cr3t@direct.example.invalid/prisma.git?token=secret#fragment')"
    assert_contains "${output}" "transport: direct URL"
    assert_not_contains "${output}" "s3cr3t"
    assert_not_contains "${output}" "token=secret"
    assert_not_contains "${output}" "AGENT_STATUS="

    output="$(cd "${fixture}" && printf 'refs/heads/main %s refs/heads/main 0000000000000000000000000000000000000000\n' "${head}" | MA_AGENT_LOG_DIR="${TMP_ROOT}/pre-push-scp" ./scripts/hooks-pre-push build.example.invalid:prisma.git)"
    assert_contains "${output}" "transport: direct URL"
    output="$(cd "${fixture}" && printf 'refs/heads/main %s refs/heads/main 0000000000000000000000000000000000000000\n' "${head}" | MA_AGENT_LOG_DIR="${TMP_ROOT}/pre-push-scp-user" ./scripts/hooks-pre-push alice@build.example.invalid:prisma.git)"
    assert_contains "${output}" "transport: direct URL"
    output="$(cd "${fixture}" && printf 'refs/heads/main %s refs/heads/main 0000000000000000000000000000000000000000\n' "${head}" | MA_AGENT_LOG_DIR="${TMP_ROOT}/pre-push-relative-repo" ./scripts/hooks-pre-push repo.git)"
    assert_contains "${output}" "transport: direct URL"
    output="$(cd "${fixture}" && printf 'refs/heads/main %s refs/heads/main 0000000000000000000000000000000000000000\n' "${head}" | MA_AGENT_LOG_DIR="${TMP_ROOT}/pre-push-relative-path" ./scripts/hooks-pre-push path/to/repo.git)"
    assert_contains "${output}" "transport: direct URL"
    mkdir -p "${fixture}/repo"
    output="$(cd "${fixture}" && printf 'refs/heads/main %s refs/heads/main 0000000000000000000000000000000000000000\n' "${head}" | MA_AGENT_LOG_DIR="${TMP_ROOT}/pre-push-existing-path" ./scripts/hooks-pre-push repo)"
    assert_contains "${output}" "transport: direct URL"

    output="$(cd "${fixture}" && printf 'refs/tags/v1 %s refs/tags/v1 %s\n' "${head}" "${base}" | ./scripts/hooks-pre-push)"
    assert_contains "${output}" "Skipping tag push"

    set +e
    output="$(cd "${fixture}" && printf 'refs/notes/review %s refs/notes/review %s\n' "${head}" "${base}" | ./scripts/hooks-pre-push alt https://alt.example.invalid/prisma.git 2>&1)"
    status=$?
    set -e
    test "${status}" -eq 1
    assert_contains "${output}" "unsupported local ref refs/notes/review"

    output="$(cd "${fixture}" && printf 'refs/notes/review 0000000000000000000000000000000000000000 refs/notes/review %s\n' "${base}" | ./scripts/hooks-pre-push alt https://alt.example.invalid/prisma.git)"
    assert_contains "${output}" "Skipping deleted ref refs/notes/review"

    set +e
    output="$(cd "${fixture}" && printf 'refs/heads/other %s refs/heads/other %s\n' "${head}" "${base}" | ./scripts/hooks-pre-push 2>&1)"
    status=$?
    set -e
    test "${status}" -eq 1
    assert_contains "${output}" "refusing to push refs/heads/other"
}

test_committed_in_place_clean_head() {
    local fixture
    local base
    local head
    local output

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'clean committed head' > "${fixture}/Alpha.swift"
    git -C "${fixture}" add Alpha.swift
    git -C "${fixture}" commit -qm "clean head"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/committed-in-place" --lane fast --committed --base "${base}" --head "${head}" --no-reuse)"
    assert_contains "${output}" "AGENT_STATUS=PASS"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/committed-in-place" --lane fast --committed --base "${base}" --head "${head}")"
    assert_contains "${output}" "Reusing PASS evidence"
    test "$(git -C "${fixture}" worktree list | wc -l | tr -d ' ')" -eq 1
}

test_clean_working_tree_pass_reused_by_committed() {
    local fixture
    local base
    local head
    local output
    local log_root="${TMP_ROOT}/clean-wt-reuse"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'clean working-tree receipt' > "${fixture}/Alpha.swift"
    git -C "${fixture}" add Alpha.swift
    git -C "${fixture}" commit -qm "clean working-tree receipt"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    # Working-tree mode on a clean tree with the same --base must share the
    # committed fingerprint so a later --committed validate-agent can reuse a just-run local PASS.
    output="$(validate_output "${fixture}" "${log_root}" --lane fast --base "${base}" --no-reuse)"
    assert_contains "${output}" "AGENT_STATUS=PASS"
    assert_not_contains "${output}" "Reusing PASS evidence"
    output="$(validate_output "${fixture}" "${log_root}" --lane fast --committed --base "${base}" --head "${head}")"
    assert_contains "${output}" "Reusing PASS evidence"
    assert_contains "${output}" "AGENT_REUSED=1"
}

test_archive_paths_excluded_from_large_delta() {
    local fixture
    local base
    local head
    local output

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    mkdir -p "${fixture}/.agents/docs/archive/large-delta-fixture"
    awk 'BEGIN { for (i = 1; i <= 301; i++) print "archive-line-" i }' > "${fixture}/.agents/docs/archive/large-delta-fixture/big.md"
    git -C "${fixture}" add .agents/docs/archive/large-delta-fixture/big.md
    git -C "${fixture}" commit -qm "archive-only large delta"
    head="$(git -C "${fixture}" rev-parse HEAD)"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/archive-large-delta" --committed --base "${base}" --head "${head}")"
    assert_contains "${output}" "Only non-code files changed"
    assert_not_contains "${output}" "Large delta detected"
}

scope_output() {
    local fixture="$1"
    local log_root="$2"
    shift 2
    (cd "${fixture}" && MA_AGENT_MODE=1 MA_AGENT_LOG_DIR="${log_root}" ./scripts/scope-check.sh --dry-run --agent "$@")
}

validate_output() {
    local fixture="$1"
    local log_root="$2"
    shift 2
    (cd "${fixture}" && MA_AGENT_LOG_DIR="${log_root}" ./scripts/validate-agent.sh "$@" --agent)
}

test_committed_delta_boundaries() {
    local fixture
    local base
    local output

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    awk 'BEGIN { for (i = 1; i <= 300; i++) print "line-" i }' > "${fixture}/Changed.swift"
    git -C "${fixture}" add Changed.swift
    git -C "${fixture}" commit -qm "300 lines"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/boundary-300" --base "${base}")"
    assert_contains "${output}" "Added lines (${base} -> working tree): 300"
    assert_not_contains "${output}" "Large delta detected"

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    awk 'BEGIN { for (i = 1; i <= 301; i++) print "line-" i }' > "${fixture}/Changed.swift"
    git -C "${fixture}" add Changed.swift
    git -C "${fixture}" commit -qm "301 lines"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/boundary-301" --base "${base}")"
    assert_contains "${output}" "Added lines (${base} -> working tree): 301"
    assert_contains "${output}" "Large delta detected (301 added lines > 300)"
}

test_source_file_churn() {
    local fixture
    local base
    local output
    local index

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    mkdir -p "${fixture}/App/Churn"
    for index in $(seq 1 9); do
        printf '%s\n' "source-${index}" > "${fixture}/App/Churn/Source${index}.swift"
    done
    git -C "${fixture}" add .
    git -C "${fixture}" commit -qm "source churn"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/source-churn" --base "${base}")"
    assert_contains "${output}" "Swift files changed: 9"
    assert_contains "${output}" "Product source files changed: 9"
    assert_contains "${output}" "High product source-file churn detected (9 files > 8)"
}

test_worktree_layers_are_unique() {
    local fixture
    local output

    fixture="$(new_fixture)"
    printf '%s\n' 'tracked' > "${fixture}/staged.swift"
    printf '%s\n' 'tracked' > "${fixture}/unstaged.swift"
    git -C "${fixture}" add staged.swift unstaged.swift
    git -C "${fixture}" commit -qm "tracked fixtures"
    printf '%s\n' 'staged change' >> "${fixture}/staged.swift"
    git -C "${fixture}" add staged.swift
    printf '%s\n' 'unstaged change' >> "${fixture}/unstaged.swift"
    printf '%s\n' 'untracked change' > "${fixture}/untracked.swift"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/layers")"
    assert_contains "${output}" "Changed files: 3"
    assert_contains "${output}" "Swift files changed: 3"
    assert_contains "${output}" "Product source files changed: 0"
}

test_repeated_file_targets_and_invalid_base() {
    local fixture
    local base
    local output
    local invalid_status

    fixture="$(new_fixture)"
    base="$(git -C "${fixture}" rev-parse HEAD)"
    printf '%s\n' 'alpha' > "${fixture}/Alpha.swift"
    printf '%s\n' 'beta' > "${fixture}/Beta.swift"
    git -C "${fixture}" add Alpha.swift Beta.swift
    git -C "${fixture}" commit -qm "mapped files"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/targets" --base "${base}")"
    assert_contains "${output}" "./scripts/run-tests.sh --suite dev --file AlphaTests --file BetaTests --agent"
    test "$(printf '%s\n' "${output}" | grep -Fc './scripts/run-tests.sh')" -eq 1

    set +e
    output="$(scope_output "${fixture}" "${TMP_ROOT}/invalid" --base missing-ref 2>&1)"
    invalid_status=$?
    set -e
    test "${invalid_status}" -eq 1
    assert_contains "${output}" "Error: base ref 'missing-ref' does not exist."
}

test_schema_and_parallel_artifacts() {
    local fixture
    local output
    local result_path
    local first_path
    local second_path
    local first_status
    local second_status

    fixture="$(new_fixture)"
    output="$(scope_output "${fixture}" "${TMP_ROOT}/schema")"
    result_path="$(printf '%s\n' "${output}" | sed -n 's/^AGENT_RESULT_JSON=//p' | tail -n 1)"
    test -f "${result_path}"
    python3 - "${result_path}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    result = json.load(handle)
assert result["schemaVersion"] == 2
assert result["log"]
PY

    set +e
    (cd "${fixture}" && MA_AGENT_MODE=1 MA_AGENT_LOG_DIR="${TMP_ROOT}/parallel" ./scripts/scope-check.sh --dry-run --agent > "${TMP_ROOT}/parallel-a.out" 2>&1) &
    local first_pid=$!
    (cd "${fixture}" && MA_AGENT_MODE=1 MA_AGENT_LOG_DIR="${TMP_ROOT}/parallel" ./scripts/scope-check.sh --dry-run --agent > "${TMP_ROOT}/parallel-b.out" 2>&1) &
    local second_pid=$!
    wait "${first_pid}"
    first_status=$?
    wait "${second_pid}"
    second_status=$?
    set -e
    test "${first_status}" -eq 0
    test "${second_status}" -eq 0

    first_path="$(sed -n 's/^AGENT_RESULT_JSON=//p' "${TMP_ROOT}/parallel-a.out" | tail -n 1)"
    second_path="$(sed -n 's/^AGENT_RESULT_JSON=//p' "${TMP_ROOT}/parallel-b.out" | tail -n 1)"
    test -f "${first_path}"
    test -f "${second_path}"
    test "${first_path}" != "${second_path}"
    test "$(dirname "${first_path}")" != "$(dirname "${second_path}")"
}

test_nested_commands_inherit_run_tree() {
    local fixture

    fixture="$(new_fixture)"
    (
        cd "${fixture}"
        source scripts/lib/agent-output.sh
        ma_agent_prepare_run_dir >/dev/null
        bash -c 'source scripts/lib/agent-output.sh; ma_agent_prepare_run_dir >/dev/null; test "${MA_AGENT_RUN_DIR}" = "${1}"' bash "${MA_AGENT_RUN_DIR}"
    )
}

test_validate_runner_preview_and_reuse() {
    local fixture
    local output
    local first_result
    local second_result
    local cache_result
    local child_result
    local toolchain_dir
    local tool

    fixture="$(new_fixture)"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/validate-preview" --lane fast --dry-run)"
    assert_contains "${output}" "Validation preview (no evidence recorded):"
    assert_contains "${output}" "Command: make scope-check-agent"
    assert_not_contains "${output}" "AGENT_STATUS=PASS"
    test -z "$(find "${TMP_ROOT}/validate-preview" -name 'validate-agent.result.json' -print 2>/dev/null)"

    output="$(validate_output "${fixture}" "${TMP_ROOT}/validate-cache" --lane fast --no-reuse)"
    assert_contains "${output}" "AGENT_STATUS=PASS"
    assert_contains "${output}" "--decision-file"
    first_result="$(printf '%s\n' "${output}" | sed -n 's/^AGENT_RESULT_JSON=//p' | tail -n 1)"
    test -f "${first_result}"
    cache_result="$(find "${TMP_ROOT}/validate-cache/validate-agent-index" -name '*.result.json' -print | head -n 1)"
    test -f "${cache_result}"

    output="$(validate_output "${fixture}" "${TMP_ROOT}/validate-cache" --lane fast)"
    assert_contains "${output}" "Reusing PASS evidence"
    assert_contains "${output}" "AGENT_REUSED=1"
    second_result="$(printf '%s\n' "${output}" | sed -n 's/^AGENT_RESULT_JSON=//p' | tail -n 1)"
    test "${second_result}" = "${cache_result}"

    child_result="$(python3 - "${cache_result}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["childResults"][0])
PY
    )"
    child_log="$(python3 - "${child_result}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["log"].split(",")[0])
PY
    )"
    rm -f "${child_log}"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/validate-cache" --lane fast)"
    assert_not_contains "${output}" "Reusing PASS evidence"
    assert_contains "${output}" "AGENT_STATUS=PASS"

    child_result="$(python3 - "${cache_result}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    print(json.load(handle)["childResults"][0])
PY
    )"
    printf '%s\n' '{}' > "${child_result}"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/validate-cache" --lane fast)"
    assert_not_contains "${output}" "Reusing PASS evidence"
    assert_contains "${output}" "AGENT_STATUS=PASS"

    printf '%s\n' '{}' > "${cache_result}"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/validate-cache" --lane fast)"
    assert_not_contains "${output}" "Reusing PASS evidence"
    assert_contains "${output}" "AGENT_STATUS=PASS"

    printf '%s\n' '# config change' >> "${fixture}/Makefile"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/validate-cache" --lane fast)"
    assert_not_contains "${output}" "Reusing PASS evidence"

    printf '%s\n' 'untracked' > "${fixture}/untracked.swift"
    output="$(validate_output "${fixture}" "${TMP_ROOT}/validate-cache" --lane fast)"
    assert_not_contains "${output}" "Reusing PASS evidence"

    output="$(validate_output "${fixture}" "${TMP_ROOT}/validate-cache" --lane full --no-reuse)"
    assert_contains "${output}" "AGENT_STATUS=PASS"
    test "$(printf '%s\n' "${output}" | grep -Fc 'Running lint-strict:')" -eq 1
    test "$(printf '%s\n' "${output}" | grep -Fc 'Running build-test:')" -eq 1
    output="$(validate_output "${fixture}" "${TMP_ROOT}/validate-cache" --lane full)"
    assert_contains "${output}" "Reusing PASS evidence"

    toolchain_dir="${TMP_ROOT}/toolchain"
    mkdir -p "${toolchain_dir}"
    for tool in swift xcodebuild swiftlint swiftformat; do
        printf '#!/bin/sh\nprintf "%s\\n" fixture-%s\n' "${tool}" "${tool}" > "${toolchain_dir}/${tool}"
        chmod +x "${toolchain_dir}/${tool}"
    done
    output="$(cd "${fixture}" && PATH="${toolchain_dir}:${PATH}" MA_AGENT_LOG_DIR="${TMP_ROOT}/validate-cache" ./scripts/validate-agent.sh --lane full --agent)"
    assert_not_contains "${output}" "Reusing PASS evidence"
}

test_committed_delta_boundaries
test_deleted_paths_are_classified
test_committed_tree_isolated_and_invalid_flags
test_source_file_churn
test_worktree_layers_are_unique
test_repeated_file_targets_and_invalid_base
test_schema_and_parallel_artifacts
test_nested_commands_inherit_run_tree
test_validate_runner_preview_and_reuse
test_committed_and_staged_boundaries
test_staged_receipt_reused_after_commit
test_committed_in_place_clean_head
test_clean_working_tree_pass_reused_by_committed
test_archive_paths_excluded_from_large_delta
test_pre_push_skips_build_and_test
test_pre_commit_staged_format
test_pre_push_protocol
source "${SCRIPT_ROOT}/scripts/tests/scope-classification-test.sh"
"${SCRIPT_ROOT}/scripts/tests/guidance-validation-test.sh"
"${SCRIPT_ROOT}/scripts/tests/hooks-setup-test.sh"
"${SCRIPT_ROOT}/scripts/tests/meeting-notes-editor-build-test.sh"
"${SCRIPT_ROOT}/scripts/tests/preview-check-test.sh"
"${SCRIPT_ROOT}/scripts/tests/localization-check-test.sh"
"${SCRIPT_ROOT}/scripts/tests/swiftpm-resolution-test.sh"
"${SCRIPT_ROOT}/scripts/tests/agent-artifacts-test.sh"
echo "WORKFLOW_TEST_STATUS=PASS"
