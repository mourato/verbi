#!/bin/bash

# Canonical Fast/Full validation runner with content-addressed PASS evidence.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/agent-output.sh
source "${SCRIPT_DIR}/lib/agent-output.sh"

RUNNER_SCHEMA_VERSION=2
AGENT_MODE=0
LANE=""
BASE_REF=""
HEAD_REF=""
EMPTY_BASE=0
VALIDATION_MODE="working-tree"
STAGED_REQUESTED=0
COMMITTED_REQUESTED=0
DRY_RUN=0
NO_REUSE=0
CHECKOUT_EXTERNAL_INPUTS_HASH="${MA_VALIDATE_CHECKOUT_EXTERNAL_INPUTS_HASH:-}"
MATERIALIZED_EXTERNAL_INPUTS_HASH=""
EXTERNAL_INPUTS_MISMATCH=0
CACHE_DISABLED_REASON=""
START_TIME="$(date +%s)"
OVERALL_STATUS="PASS"
COMMANDS_FILE=""
REASONS_FILE=""
SELECTED_LANE=""
DECISION_STRATEGY="requested"
AUTO_DECISION_FILE=""
RUN_DIR=""
FINGERPRINT=""
CACHE_RESULT=""
CHILD_RESULTS=()

usage() {
    cat <<'USAGE'
Usage: ./scripts/validate-agent.sh --lane fast|full|auto [options]

Description: Run the canonical Fast, Full, or automatic validation lane with fingerprinted evidence.

Options:
  --lane LANE           Required: fast, full, or auto
  --base REF            Base ref used for changed-file/risk selection
  --head REF            Head ref used with --committed
  --empty-base          Use the empty Git tree as the committed diff base
  --staged              Validate the staged index only
  --committed           Validate the committed BASE..HEAD range only
  --dry-run             Print the selected command graph without executing it
  --no-reuse            Ignore cached PASS evidence and execute the gate
  --agent               Emit compact AGENT_* result lines
  --help, -h            Show this help
USAGE
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --lane)
                [ "$#" -ge 2 ] || { echo "Error: --lane requires a value."; exit 1; }
                LANE="$2"
                shift 2
                ;;
            --base)
                [ "$#" -ge 2 ] || { echo "Error: --base requires a ref value."; exit 1; }
                BASE_REF="$2"
                shift 2
                ;;
            --head)
                [ "$#" -ge 2 ] || { echo "Error: --head requires a ref value."; exit 1; }
                HEAD_REF="$2"
                shift 2
                ;;
            --empty-base)
                EMPTY_BASE=1
                shift
                ;;
            --staged)
                VALIDATION_MODE="staged"
                STAGED_REQUESTED=1
                shift
                ;;
            --committed)
                VALIDATION_MODE="committed"
                COMMITTED_REQUESTED=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --no-reuse)
                NO_REUSE=1
                shift
                ;;
            --agent)
                AGENT_MODE=1
                MA_AGENT_MODE=1
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    case "${LANE}" in
        fast|full|auto) ;;
        *)
            echo "Error: --lane must be fast, full, or auto."
            exit 1
            ;;
    esac
    if [ "${STAGED_REQUESTED}" -eq 1 ] && [ "${COMMITTED_REQUESTED}" -eq 1 ]; then
        echo "Error: --staged and --committed are mutually exclusive."
        exit 1
    fi
    if [ "${EMPTY_BASE}" -eq 1 ] && [ -n "${BASE_REF}" ]; then
        echo "Error: --empty-base and --base are mutually exclusive."
        exit 1
    fi
    if [ "${VALIDATION_MODE}" = "committed" ]; then
        if [ "${EMPTY_BASE}" -eq 0 ] && [ -z "${BASE_REF}" ]; then
            echo "Error: --committed requires --base or --empty-base."
            exit 1
        fi
        [ -n "${HEAD_REF}" ] || { echo "Error: --committed requires --head."; exit 1; }
    fi
    if [ "${VALIDATION_MODE}" = "staged" ]; then
        if ! git diff --quiet; then
            echo "Error: --staged requires no unstaged tracked changes."
            exit 1
        fi
        if [ -n "$(git ls-files --others --exclude-standard)" ]; then
            echo "Error: --staged requires no untracked files."
            exit 1
        fi
    fi
}

prepare_run() {
    cd "${PROJECT_ROOT}"
    ma_agent_prepare_run_dir >/dev/null
    RUN_DIR="${MA_AGENT_RUN_DIR}"
    COMMANDS_FILE="${RUN_DIR}/validate-agent.commands.tsv"
    REASONS_FILE="${RUN_DIR}/validate-agent.reasons.txt"
    : > "${COMMANDS_FILE}"
    : > "${REASONS_FILE}"
}

base_commit() {
    if [ -z "${BASE_REF}" ]; then
        printf '%s\n' ""
        return
    fi
    if ! git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null; then
        echo "Error: base ref '${BASE_REF}' does not exist."
        exit 1
    fi
    git rev-parse --verify "${BASE_REF}^{commit}"
}

ref_tree() {
    git rev-parse --verify "$1^{tree}"
}

validation_base_tree() {
    if [ "${EMPTY_BASE}" -eq 1 ]; then
        git hash-object -t tree /dev/null
    elif [ -n "${BASE_REF}" ]; then
        ref_tree "${BASE_REF}"
    elif [ "${VALIDATION_MODE}" = "staged" ]; then
        ref_tree HEAD
    else
        printf '%s\n' ""
    fi
}

validation_head_tree() {
    case "${VALIDATION_MODE}" in
        staged) git write-tree ;;
        committed) ref_tree "${HEAD_REF}" ;;
        *) ref_tree HEAD ;;
    esac
}

working_tree_is_clean() {
    git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]
}

hash_working_state() {
    {
        printf 'HEAD=%s\n' "$(git rev-parse HEAD)"
        printf 'BASE=%s\n' "$(base_commit)"
        printf '%s\n' 'STAGED_DIFF_BEGIN'
        git diff --cached --binary
        printf '%s\n' 'STAGED_DIFF_END'
        printf '%s\n' 'UNSTAGED_DIFF_BEGIN'
        git diff --binary
        printf '%s\n' 'UNSTAGED_DIFF_END'
        while IFS= read -r path; do
            [ -n "${path}" ] || continue
            printf 'UNTRACKED=%s\n' "${path}"
            if [ -f "${path}" ]; then
                shasum -a 256 "${path}"
            else
                printf '%s\n' 'non-regular-file'
            fi
        done < <(git ls-files --others --exclude-standard | sort)
    } | shasum -a 256 | awk '{print $1}'
}

hash_gate_inputs() {
    local treeish="$1"
    {
        git ls-tree -r --full-tree "${treeish}" -- \
            Makefile AGENTS.md scripts .agents/docs .agents/skills/delivery-workflow \
            .swiftlint.yml .swiftlint-baseline.json .swiftformat Package.swift '*.xcodeproj/project.pbxproj' '*.xcworkspace/*'
    } | shasum -a 256 | awk '{print $1}'
}

hash_external_gate_inputs() {
    local path
    for path in \
        Packages/MeetingAssistantCore/Package.resolved \
        MeetingAssistant.xcworkspace/xcshareddata/swiftpm/Package.resolved; do
        if ! git ls-files --error-unmatch -- "${path}" >/dev/null 2>&1; then
            continue
        fi
        if [ -f "${path}" ]; then
            printf 'PATH=%s\n' "${path}"
            shasum -a 256 "${path}"
        else
            printf 'ABSENT_TRACKED=%s\n' "${path}"
        fi
    done | shasum -a 256 | awk '{print $1}'
}

external_inputs_fingerprint() {
    if [ "${EXTERNAL_INPUTS_MISMATCH}" -eq 1 ]; then
        printf 'checkout:%s;materialized:%s\n' "${CHECKOUT_EXTERNAL_INPUTS_HASH}" "${MATERIALIZED_EXTERNAL_INPUTS_HASH}"
    else
        printf '%s\n' "${MATERIALIZED_EXTERNAL_INPUTS_HASH}"
    fi
}

toolchain_identity_hash() {
    {
        if command -v swift >/dev/null 2>&1; then swift --version 2>&1 || true; else echo 'swift=unavailable'; fi
        if command -v xcodebuild >/dev/null 2>&1; then xcodebuild -version 2>&1 || true; else echo 'xcodebuild=unavailable'; fi
        if command -v swiftlint >/dev/null 2>&1; then swiftlint version 2>&1 || true; else echo 'swiftlint=unavailable'; fi
        if command -v swiftformat >/dev/null 2>&1; then swiftformat --version 2>&1 || true; else echo 'swiftformat=unavailable'; fi
    } | shasum -a 256 | awk '{print $1}'
}

compute_fingerprint() {
    local base_tree
    local head_tree
    base_tree="$(validation_base_tree)"
    head_tree="$(validation_head_tree)"
    MATERIALIZED_EXTERNAL_INPUTS_HASH="$(hash_external_gate_inputs)"
    if [ "${VALIDATION_MODE}" = "committed" ] && [ -n "${CHECKOUT_EXTERNAL_INPUTS_HASH}" ] && [ "${CHECKOUT_EXTERNAL_INPUTS_HASH}" != "${MATERIALIZED_EXTERNAL_INPUTS_HASH}" ]; then
        EXTERNAL_INPUTS_MISMATCH=1
        CACHE_DISABLED_REASON="External gate inputs differ between checkout and materialized HEAD_REF"
    fi
    FINGERPRINT="$({
        printf 'runnerSchema=%s\n' "${RUNNER_SCHEMA_VERSION}"
        printf 'requestedLane=%s\n' "${LANE}"
        printf 'selectedLane=%s\n' "${SELECTED_LANE}"
        printf 'validationScope=tree-range\n'
        printf 'baseTree=%s\n' "${base_tree}"
        printf 'headTree=%s\n' "${head_tree}"
        # Dirty working trees must salt the fingerprint. A clean tree omits
        # workingState so a working-tree PASS with the same base/head trees can
        # be reused by a later --committed validate-agent (same selected lane + toolchain).
        if [ "${VALIDATION_MODE}" = "working-tree" ] && ! working_tree_is_clean; then
            printf 'workingState=%s\n' "$(hash_working_state)"
        fi
        printf 'gateInputs=%s\n' "$(hash_gate_inputs "${head_tree}")"
        printf 'externalGateInputs=%s\n' "$(external_inputs_fingerprint)"
        printf 'toolchain=%s\n' "$(toolchain_identity_hash)"
    } | shasum -a 256 | awk '{print $1}')"
}

scope_args() {
    case "${VALIDATION_MODE}" in
        staged) printf '%s' '--staged' ;;
        committed)
            if [ "${EMPTY_BASE}" -eq 1 ]; then
                printf '%s' "--committed --empty-base --head $(printf '%q' "${HEAD_REF}")"
            else
                printf '%s' "--committed --base $(printf '%q' "${BASE_REF}") --head $(printf '%q' "${HEAD_REF}")"
            fi
            ;;
    esac
}

load_auto_decision() {
    local preview_log="${RUN_DIR}/scope-decision-preview.log"
    local preview_result="${RUN_DIR}/scope-check.result.json"
    local base_args=""
    local mode_args=""
    local decision

    if [ -n "${BASE_REF}" ]; then
        base_args="--base $(printf '%q' "${BASE_REF}")"
    fi
    mode_args="$(scope_args)"
    if ! eval "./scripts/scope-check.sh --dry-run --agent ${mode_args} ${base_args}" > "${preview_log}" 2>&1; then
        echo "Error: scope-check could not select an auto lane. See ${preview_log}."
        exit 1
    fi
    if [ ! -f "${preview_result}" ]; then
        echo "Error: scope-check did not produce a machine-readable lane decision."
        exit 1
    fi
    AUTO_DECISION_FILE="${preview_result}"

    decision="$(python3 - "${preview_result}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    result = json.load(handle)
decision = result.get("decision", {})
if decision.get("selectedLane") not in {"fast", "full"}:
    raise SystemExit("invalid selected lane")
print(decision["selectedLane"])
print(decision.get("strategy", "scope-check"))
for reason in decision.get("reasons", []):
    print(reason)
PY
    )"
    SELECTED_LANE="$(printf '%s\n' "${decision}" | sed -n '1p')"
    DECISION_STRATEGY="$(printf '%s\n' "${decision}" | sed -n '2p')"
    printf '%s\n' "${decision}" | sed -n '3,$p' > "${REASONS_FILE}"
}

select_lane() {
    case "${LANE}" in
        auto|fast)
            load_auto_decision
            ;;
        full)
            SELECTED_LANE="full"
            DECISION_STRATEGY="requested"
            printf 'requested lane: %s\n' "${LANE}" > "${REASONS_FILE}"
            ;;
    esac
}

result_is_valid() {
    local result_path="$1"
    [ -f "${result_path}" ] || return 1
    python3 - "${result_path}" "${FINGERPRINT}" <<'PY'
import json
import os
import re
import sys

path, fingerprint = sys.argv[1:]
def require_logs(value):
    log_paths = [item for item in re.split(r"[,;]", value or "") if item]
    if not log_paths:
        raise ValueError("missing log")
    for log_path in log_paths:
        if not os.path.isfile(log_path):
            raise ValueError("missing log")

try:
    with open(path, encoding="utf-8") as handle:
        result = json.load(handle)
    if result.get("schemaVersion") != 2:
        raise ValueError("schema")
    if result.get("step") != "validate-agent":
        raise ValueError("step")
    if result.get("status") != "PASS" or result.get("dryRun") is not False:
        raise ValueError("status")
    if result.get("validationFingerprint") != fingerprint:
        raise ValueError("fingerprint")
    if not os.path.isdir(result.get("runDir", "")):
        raise ValueError("run directory")
    commands = result.get("commands")
    if not commands:
        raise ValueError("commands")
    command_results = []
    for command in commands:
        if command.get("status") != "PASS":
            raise ValueError("command status")
        require_logs(command.get("log"))
        result_paths = command.get("resultPaths")
        if not result_paths:
            raise ValueError("command results")
        command_results.extend(result_paths)
    child_results = result.get("childResults")
    if not child_results or child_results != command_results:
        raise ValueError("children")
    for child_path in child_results:
        if not os.path.isfile(child_path):
            raise ValueError("missing child")
        with open(child_path, encoding="utf-8") as child_handle:
            child = json.load(child_handle)
        if child.get("schemaVersion") != 2 or not child.get("step"):
            raise ValueError("child schema")
        if child.get("validationFingerprint") != fingerprint:
            raise ValueError("child fingerprint")
        if child.get("status") != "PASS":
            raise ValueError("child status")
        require_logs(child.get("log"))
        for command in child.get("commands", []):
            if command.get("status") != "PASS":
                raise ValueError("child command status")
            require_logs(command.get("log"))
except (OSError, ValueError, json.JSONDecodeError):
    raise SystemExit(1)
PY
}

emit_agent_result() {
    local status="$1"
    local result_path="$2"
    local duration=$(( $(date +%s) - START_TIME ))
    if [ "${DRY_RUN}" -eq 1 ]; then
        return
    fi
    if [ "${AGENT_MODE}" -eq 0 ]; then
        echo "Validation result: status=${status}; lane=${SELECTED_LANE}; fingerprint=${FINGERPRINT}; result=${result_path}"
    fi
    if [ "${AGENT_MODE}" -eq 1 ]; then
        local reasons_summary
        reasons_summary="$(tr '\n' '|' < "${REASONS_FILE}" | sed 's/|$//')"
        echo "AGENT_STEP=validate-agent"
        echo "AGENT_STATUS=${status}"
        echo "AGENT_DURATION_SEC=${duration}"
        echo "AGENT_LOG=${RUN_DIR}"
        echo "AGENT_ERROR_COUNT=$([ "${status}" = "PASS" ] && echo 0 || echo 1)"
        echo "AGENT_SUMMARY=lane=${SELECTED_LANE}; strategy=${DECISION_STRATEGY}; reasons=${reasons_summary}; fingerprint=${FINGERPRINT}"
        echo "AGENT_VALIDATION_FINGERPRINT=${FINGERPRINT}"
        if [ -n "${result_path}" ] && [ "${result_path}" = "${CACHE_RESULT}" ]; then
            echo "AGENT_REUSED=1"
        else
            echo "AGENT_REUSED=0"
        fi
        echo "AGENT_RESULT_JSON=${result_path}"
    fi
}

run_step() {
    local name="$1"
    local command="$2"
    local log_path="${RUN_DIR}/validate-agent-${name}.log"
    local started
    local ended
    local exit_code
    local status
    local result_paths
    local result_csv

    echo "Running ${name}: ${command}"
    started="$(date +%s)"
    if eval "${command}" > "${log_path}" 2>&1; then
        exit_code=0
        status="PASS"
    else
        exit_code=$?
        status="FAIL"
        OVERALL_STATUS="FAIL"
    fi
    ended="$(date +%s)"
    result_paths="$(sed -n 's/^AGENT_RESULT_JSON=//p' "${log_path}" | while IFS= read -r path; do [ -f "${path}" ] && printf '%s\n' "${path}"; done)"
    result_csv="$(printf '%s\n' "${result_paths}" | sed '/^$/d' | paste -sd, -)"
    if [ "${exit_code}" -eq 0 ] && [ -z "${result_csv}" ]; then
        status="INCOMPLETE"
        OVERALL_STATUS="FAIL"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "${name}" "${status}" "$((ended - started))" "${log_path}" "${result_csv}" >> "${COMMANDS_FILE}"
    while IFS= read -r path; do
        [ -n "${path}" ] || continue
        CHILD_RESULTS+=("${path}")
    done < <(printf '%s\n' "${result_paths}" | sed '/^$/d')
}

write_aggregate() {
    local result_path="${RUN_DIR}/validate-agent.result.json"
    python3 - "${result_path}" "${FINGERPRINT}" "${SELECTED_LANE}" "${BASE_REF}" "${HEAD_REF}" "${VALIDATION_MODE}" "${EXTERNAL_INPUTS_MISMATCH}" "${RUN_DIR}" "${OVERALL_STATUS}" "${COMMANDS_FILE}" "${REASONS_FILE}" "${DECISION_STRATEGY}" <<'PY'
import json
import sys

result_path, fingerprint, lane, base, head, validation_mode, external_mismatch, run_dir, status, commands_path, reasons_path, strategy = sys.argv[1:]
commands = []
child_results = []
with open(commands_path, encoding="utf-8") as handle:
    for line in handle:
        name, step_status, duration, log_path, result_csv = line.rstrip("\n").split("\t")
        result_paths = [item for item in result_csv.split(",") if item]
        commands.append({"name": name, "status": step_status, "durationSec": int(duration), "log": log_path, "resultPaths": result_paths})
        child_results.extend(result_paths)
with open(reasons_path, encoding="utf-8") as handle:
    reasons = [line.rstrip("\n") for line in handle if line.rstrip("\n")]
result = {
    "schemaVersion": 2,
    "step": "validate-agent",
    "status": status,
    "durationSec": sum(item["durationSec"] for item in commands),
    "log": run_dir,
    "errorCount": 0 if status == "PASS" else 1,
    "commands": commands,
    "decision": {"selectedLane": lane, "strategy": strategy, "reasons": reasons},
    "validationFingerprint": fingerprint,
    "dryRun": False,
    "reused": False,
    "runDir": run_dir,
    "base": base,
    "head": head,
    "validationMode": validation_mode,
    "externalInputsMismatch": external_mismatch == "1",
    "childResults": child_results,
    "summary": f"{lane} validation {status.lower()}"
}
with open(result_path, "w", encoding="utf-8") as handle:
    json.dump(result, handle, separators=(",", ":"))
    handle.write("\n")
PY
    printf '%s\n' "${result_path}"
}

print_dry_run() {
    echo "Validation preview (no evidence recorded):"
    echo "- Requested lane: ${LANE}"
    echo "- Selected lane: ${SELECTED_LANE}"
    echo "- Strategy: ${DECISION_STRATEGY}"
    while IFS= read -r reason; do
        [ -n "${reason}" ] || continue
        echo "- Reason: ${reason}"
    done < "${REASONS_FILE}"
    if [ "${SELECTED_LANE}" = "full" ]; then
        echo "- Command: make lint-strict-agent"
        echo "- Command: make build-test"
    else
        local base_args=""
        local mode_args=""
        if [ -n "${BASE_REF}" ] && [ "${VALIDATION_MODE}" != "committed" ]; then
            base_args=" ARGS=\"--base $(printf '%q' "${BASE_REF}")\""
        fi
        mode_args="$(scope_args)"
        if [ -n "${mode_args}" ]; then
            if [ -n "${base_args}" ]; then
                base_args=" ARGS=\"--base $(printf '%q' "${BASE_REF}") ${mode_args}\""
            else
                base_args=" ARGS=\"${mode_args}\""
            fi
        fi
        echo "- Command: make scope-check-agent${base_args}"
    fi
    find "${RUN_DIR}" -name '*.result.json' -delete
}

can_validate_committed_in_place() {
    local head_commit
    head_commit="$(git rev-parse --verify "${HEAD_REF}^{commit}")" || return 1
    [ "$(git rev-parse HEAD)" = "${head_commit}" ] || return 1
    working_tree_is_clean
}

run_committed_tree() {
    local temporary_worktree
    local child_status
    local worktree_registered=0
    local checkout_external_hash

    if can_validate_committed_in_place; then
        checkout_external_hash="$(hash_external_gate_inputs)"
        MA_VALIDATE_MATERIALIZED=1 MA_VALIDATE_CHECKOUT_EXTERNAL_INPUTS_HASH="${checkout_external_hash}" ./scripts/validate-agent.sh "$@"
        return $?
    fi

    cleanup_committed_worktree() {
        if [ "${worktree_registered}" -eq 1 ]; then
            if ! git worktree remove --force "${temporary_worktree}" >/dev/null 2>&1; then
                git worktree prune >/dev/null 2>&1 || true
            fi
            worktree_registered=0
        fi
        if [ -n "${temporary_worktree}" ] && [ -e "${temporary_worktree}" ]; then
            rm -rf "${temporary_worktree}"
        fi
    }

    temporary_worktree="$(mktemp -d "${TMPDIR:-/tmp}/verbi-validate-head.XXXXXX")"
    rmdir "${temporary_worktree}"
    checkout_external_hash="$(hash_external_gate_inputs)"
    trap 'cleanup_committed_worktree' EXIT
    trap 'exit 130' INT TERM HUP
    if ! git worktree add --detach --quiet "${temporary_worktree}" "${HEAD_REF}"; then
        echo "Error: could not materialize committed head '${HEAD_REF}' for validation." >&2
        cleanup_committed_worktree
        trap - EXIT INT TERM HUP
        return 1
    fi
    worktree_registered=1

    set +e
    (
        cd "${temporary_worktree}" || exit 1
        MA_VALIDATE_MATERIALIZED=1 MA_VALIDATE_CHECKOUT_EXTERNAL_INPUTS_HASH="${checkout_external_hash}" ./scripts/validate-agent.sh "$@"
    )
    child_status=$?
    set -e

    cleanup_committed_worktree
    trap - EXIT INT TERM HUP
    return "${child_status}"
}

main() {
    local cache_root
    local result_path
    local cache_tmp

    parse_args "$@"
    if [ "${VALIDATION_MODE}" = "committed" ] && [ "${MA_VALIDATE_MATERIALIZED:-0}" != "1" ]; then
        run_committed_tree "$@"
        return $?
    fi
    prepare_run
    select_lane
    compute_fingerprint

    if [ "${EXTERNAL_INPUTS_MISMATCH}" -eq 1 ]; then
        echo "Cache disabled: ${CACHE_DISABLED_REASON}. PASS evidence will not be reused or cached."
    fi

    cache_root="$(ma_agent_log_dir)/validate-agent-index"
    CACHE_RESULT="${cache_root}/${FINGERPRINT}.result.json"
    export MA_AGENT_MODE=1
    export MA_AGENT_VALIDATION_FINGERPRINT="${FINGERPRINT}"

    if [ "${DRY_RUN}" -eq 1 ]; then
        print_dry_run
        emit_agent_result "PASS" ""
        return 0
    fi

    if [ "${NO_REUSE}" -eq 0 ] && [ "${EXTERNAL_INPUTS_MISMATCH}" -eq 0 ] && result_is_valid "${CACHE_RESULT}"; then
        echo "Reusing PASS evidence: ${CACHE_RESULT}"
        emit_agent_result "PASS" "${CACHE_RESULT}"
        return 0
    fi

    if [ "${SELECTED_LANE}" = "full" ]; then
        run_step "lint-strict" "make lint-strict-agent"
        run_step "build-test" "make build-test"
    else
        if [ -n "${AUTO_DECISION_FILE}" ]; then
            local decision_args
            decision_args="--decision-file $(printf '%q' "${AUTO_DECISION_FILE}")"
            run_step "scope-check" "make scope-check-agent ARGS=\"${decision_args}\""
        else
        local base_args=""
        local mode_args=""
        if [ -n "${BASE_REF}" ] && [ "${VALIDATION_MODE}" != "committed" ]; then
            base_args="ARGS=\"--base $(printf '%q' "${BASE_REF}")\""
        fi
        mode_args="$(scope_args)"
        if [ -n "${mode_args}" ]; then
            if [ -n "${base_args}" ]; then
                base_args="ARGS=\"--base $(printf '%q' "${BASE_REF}") ${mode_args}\""
            else
                base_args="ARGS=\"${mode_args}\""
            fi
        fi
        run_step "scope-check" "make scope-check-agent ${base_args}"
        fi
    fi

    result_path="$(write_aggregate)"
    if [ "${OVERALL_STATUS}" = "PASS" ] && ! result_is_valid "${result_path}"; then
        echo "Error: Fresh validation result failed schema-v2 verification."
        OVERALL_STATUS="FAIL"
        result_path="$(write_aggregate)"
    fi
    if [ "${OVERALL_STATUS}" = "PASS" ] && [ "${EXTERNAL_INPUTS_MISMATCH}" -eq 0 ]; then
        mkdir -p "${cache_root}"
        cache_tmp="${CACHE_RESULT}.tmp.$$"
        cp "${result_path}" "${cache_tmp}"
        mv -f "${cache_tmp}" "${CACHE_RESULT}"
    fi
    emit_agent_result "${OVERALL_STATUS}" "${result_path}"
    [ "${OVERALL_STATUS}" = "PASS" ]
}

main "$@"
