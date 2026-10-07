#!/bin/bash
# =============================================================================
# scope-check.sh - Scoped validation driven by changed files
# =============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_MAPPING_CONFIG="${SCRIPT_DIR}/config/test-target-mapping.conf"

# shellcheck source=scripts/lib/agent-output.sh
source "${SCRIPT_DIR}/lib/agent-output.sh"

AGENT_MODE=0
BASE_REF=""
HEAD_REF=""
EMPTY_BASE=0
STAGED_MODE=0
COMMITTED_MODE=0
MAX_TARGETED=8
RUN_BUILD=1
DRY_RUN=0
FORCE_FULL=0

START_TIME="$(date +%s)"
LOG_PATH="/tmp/ma-scope-check-$$.log"
RESULT_PATH=""
DECISION_FILE=""
DIFF_RANGE_LABEL="HEAD -> working tree"

TMP_FILES=()
TARGETED_TESTS_RESULT=()
FULL_RISK_REASONS=()
CHANGED_FILES_RESULT=()
DECISION_CODE_RELEVANT=0
DECISION_GUIDANCE_RELEVANT=0
SELECTED_LANE="fast"
DECISION_STRATEGY="scoped-validation"

if ma_agent_mode_enabled; then
    AGENT_MODE=1
fi

usage() {
    cat <<'USAGE'
Usage: ./scripts/scope-check.sh [options]

Description: Classify changed files, select targeted checks, and escalate to the full gate when required.

Options:
  --base REF            Compare against git ref in addition to local working tree
  --head REF            Head ref used with --committed
  --empty-base          Use the empty Git tree as the committed diff base
  --staged              Validate the staged index; reject unstaged/untracked files
  --committed           Validate the committed BASE..HEAD range only
  --max-targeted N      Maximum mapped targeted tests before escalating (default: 8)
  --no-build            Skip narrow build step before targeted tests
  --dry-run             Print decisions and commands without executing checks
  --decision-file PATH  Reuse a validated machine-readable decision for execution
  --force-full          Always run full gate (`make build-test`)
  --agent               Emit compact AGENT_* result lines
  --help, -h            Show this help

Examples:
  ./scripts/scope-check.sh
  ./scripts/scope-check.sh --dry-run
  ./scripts/scope-check.sh --base main --max-targeted 10
USAGE
}

new_tmp_file() {
    local tmp
    tmp="$(mktemp /tmp/ma-scope-check.XXXXXX)"
    TMP_FILES+=("${tmp}")
    printf '%s\n' "${tmp}"
}

cleanup_tmp_files() {
    local tmp
    for tmp in "${TMP_FILES[@]+"${TMP_FILES[@]}"}"; do
        if [ -f "${tmp}" ]; then
            rm -f "${tmp}"
        fi
    done
}

append_line_once() {
    local value="$1"
    local file_path="$2"
    if [ -z "${value}" ]; then
        return
    fi
    if [ ! -f "${file_path}" ]; then
        return
    fi
    if ! grep -Fxq "${value}" "${file_path}" 2>/dev/null; then
        echo "${value}" >> "${file_path}"
    fi
}

lowercase() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

run_cmd() {
    local cmd="$1"
    if [ "${DRY_RUN}" -eq 1 ]; then
        echo "[dry-run] ${cmd}"
        return 0
    fi
    echo "→ ${cmd}"
    eval "${cmd}"
}

collect_changed_files() {
    local changed_file_list="$1"
    : > "${changed_file_list}"

    if [ "${COMMITTED_MODE}" -eq 1 ]; then
        local committed_base="${BASE_REF}"
        if [ "${EMPTY_BASE}" -eq 1 ]; then
            committed_base="$(git hash-object -t tree /dev/null)"
            DIFF_RANGE_LABEL="empty tree -> ${HEAD_REF}"
        else
            DIFF_RANGE_LABEL="${BASE_REF} -> ${HEAD_REF}"
        fi
        git diff --name-only --diff-filter=ACMRD "${committed_base}" "${HEAD_REF}" >> "${changed_file_list}"
    elif [ "${STAGED_MODE}" -eq 1 ]; then
        DIFF_RANGE_LABEL="${BASE_REF:-HEAD} -> staged index"
        git diff --cached --name-only --diff-filter=ACMRD ${BASE_REF:+"${BASE_REF}"} >> "${changed_file_list}"
    else
        if [ -n "${BASE_REF}" ]; then
            if ! git rev-parse --verify --quiet "${BASE_REF}" >/dev/null; then
                echo "Error: base ref '${BASE_REF}' does not exist."
                return 1
            fi
            DIFF_RANGE_LABEL="${BASE_REF} -> working tree"
        fi
        local tracked_base="${BASE_REF:-HEAD}"
        git diff --name-only --diff-filter=ACMRD "${tracked_base}" >> "${changed_file_list}"
        git ls-files --others --exclude-standard >> "${changed_file_list}"
    fi

    sed '/^$/d' "${changed_file_list}" | sort -u > "${changed_file_list}.sorted"
    mv "${changed_file_list}.sorted" "${changed_file_list}"
    return 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --base)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --base requires a ref value."
                    exit 1
                fi
                BASE_REF="$2"
                shift 2
                ;;
            --head)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --head requires a ref value."
                    exit 1
                fi
                HEAD_REF="$2"
                shift 2
                ;;
            --empty-base)
                EMPTY_BASE=1
                shift
                ;;
            --staged)
                STAGED_MODE=1
                shift
                ;;
            --committed)
                COMMITTED_MODE=1
                shift
                ;;
            --max-targeted)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --max-targeted requires a numeric value."
                    exit 1
                fi
                MAX_TARGETED="$2"
                shift 2
                ;;
            --no-build)
                RUN_BUILD=0
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --decision-file)
                if [[ $# -lt 2 ]]; then
                    echo "Error: --decision-file requires a path."
                    exit 1
                fi
                DECISION_FILE="$2"
                shift 2
                ;;
            --force-full)
                FORCE_FULL=1
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

    if ! [[ "${MAX_TARGETED}" =~ ^[0-9]+$ ]] || [ "${MAX_TARGETED}" -le 0 ]; then
        echo "Error: --max-targeted must be a positive integer."
        exit 1
    fi
    if [ "${STAGED_MODE}" -eq 1 ] && [ "${COMMITTED_MODE}" -eq 1 ]; then
        echo "Error: --staged and --committed are mutually exclusive."
        exit 1
    fi
    if [ "${EMPTY_BASE}" -eq 1 ] && [ -n "${BASE_REF}" ]; then
        echo "Error: --empty-base and --base are mutually exclusive."
        exit 1
    fi
    if [ "${COMMITTED_MODE}" -eq 1 ]; then
        if [ "${EMPTY_BASE}" -eq 0 ] && [ -z "${BASE_REF}" ]; then
            echo "Error: --committed requires --base or --empty-base."
            exit 1
        fi
        [ -n "${HEAD_REF}" ] || { echo "Error: --committed requires --head."; exit 1; }
        if [ "${EMPTY_BASE}" -eq 0 ]; then
            git rev-parse --verify --quiet "${BASE_REF}^{commit}" >/dev/null || { echo "Error: base ref '${BASE_REF}' does not exist."; exit 1; }
        fi
        git rev-parse --verify --quiet "${HEAD_REF}^{commit}" >/dev/null || { echo "Error: head ref '${HEAD_REF}' does not exist."; exit 1; }
    fi
    if [ "${STAGED_MODE}" -eq 1 ]; then
        if ! git diff --quiet; then
            echo "Error: --staged requires no unstaged tracked changes."
            exit 1
        fi
        if [ -n "$(git ls-files --others --exclude-standard)" ]; then
            echo "Error: --staged requires no untracked files."
            exit 1
        fi
        if git ls-files --unmerged --error-unmatch -- ':/' >/dev/null 2>&1; then
            echo "Error: --staged cannot validate an unmerged index."
            exit 1
        fi
    fi
}

prepare_agent_logging() {
    if [ "${AGENT_MODE}" -eq 0 ]; then
        return
    fi
    local log_dir
    ma_agent_prepare_run_dir
    log_dir="${MA_AGENT_RUN_DIR}"
    LOG_PATH="${log_dir}/scope-check.log"
    RESULT_PATH="${log_dir}/scope-check.result.json"
    : > "${LOG_PATH}"
    exec > >(tee "${LOG_PATH}") 2>&1
}

count_added_lines_excluding_archive() {
    awk -F'\t' '
        $3 !~ /^\.agents\/docs\/archive\// && $1 ~ /^[0-9]+$/ { sum += $1 }
        END { print sum + 0 }
    '
}

count_added_lines() {
    local changed_file_list="$1"
    local tracked_base="${BASE_REF:-HEAD}"
    local tracked_added_lines
    local untracked_added_lines=0
    local file_path
    local numstat
    local added

    if [ "${COMMITTED_MODE}" -eq 1 ]; then
        local committed_base="${BASE_REF}"
        if [ "${EMPTY_BASE}" -eq 1 ]; then
            committed_base="$(git hash-object -t tree /dev/null)"
        fi
        tracked_added_lines="$(git diff --numstat --diff-filter=ACMRD "${committed_base}" "${HEAD_REF}" -- \
            | count_added_lines_excluding_archive)"
    elif [ "${STAGED_MODE}" -eq 1 ]; then
        tracked_added_lines="$(git diff --cached --numstat --diff-filter=ACMRD ${BASE_REF:+"${BASE_REF}"} -- \
            | count_added_lines_excluding_archive)"
    else
        tracked_added_lines="$(git diff --numstat --diff-filter=ACMRD "${tracked_base}" -- \
            | count_added_lines_excluding_archive)"
    fi

    if [ "${STAGED_MODE}" -eq 1 ] || [ "${COMMITTED_MODE}" -eq 1 ]; then
        printf '%s\n' "${tracked_added_lines}"
        return 0
    fi

    while IFS= read -r file_path; do
        [ -n "${file_path}" ] || continue
        if git ls-files --error-unmatch -- "${file_path}" >/dev/null 2>&1; then
            continue
        fi
        numstat="$(git diff --no-index --numstat /dev/null "${file_path}" 2>/dev/null || true)"
        added="$(printf '%s\n' "${numstat}" | awk '$1 ~ /^[0-9]+$/ {print $1; exit}')"
        if [ -n "${added}" ]; then
            untracked_added_lines=$((untracked_added_lines + added))
        fi
    done < "${changed_file_list}"

    printf '%s\n' $((tracked_added_lines + untracked_added_lines))
}

should_treat_as_infra_trigger() {
    local file_path="$1"
    case "${file_path}" in
        Makefile|Package.swift|scripts/*|.github/workflows/*|*.xcodeproj/*|*.xcworkspace/*|*.pbxproj)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

should_treat_as_high_risk_path() {
    local file_path="$1"
    case "${file_path}" in
        *Packages/MeetingAssistantCore/Sources/Audio/*|*Packages/MeetingAssistantCore/Sources/Data/*|*Security/*|*Keychain*|*Concurrency*|*actor*|*Actor*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_product_swift_path() {
    local file_path="$1"
    case "${file_path}" in
        App/*.swift|MeetingAssistantAI/Sources/*.swift|Packages/MeetingAssistantCore/Sources/*.swift)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

map_tokens_from_changed_file() {
    local file_path="$1"
    local token_file="$2"
    local file_name
    local stem
    local root
    local parent_dir
    local grandparent_dir

    file_name="$(basename "${file_path}")"
    stem="${file_name%.swift}"
    root="${stem%%+*}"
    parent_dir="$(basename "$(dirname "${file_path}")")"
    grandparent_dir="$(basename "$(dirname "$(dirname "${file_path}")")")"

    append_line_once "${stem}" "${token_file}"
    if [ "${root}" != "${stem}" ]; then
        append_line_once "${root}" "${token_file}"
    fi

    if [ "${parent_dir}" != "$(basename "${PROJECT_DIR}")" ] && [ "${parent_dir}" != "$(basename "$(pwd)")" ]; then
        append_line_once "${parent_dir}" "${token_file}"
    fi

    if [ "${parent_dir}" = "AppDelegate" ] || [ "${parent_dir}" = "AssistantShortcutController" ] || [ "${parent_dir}" = "AppSettingsStore" ] || [ "${parent_dir}" = "RecordingManager" ]; then
        append_line_once "${parent_dir}" "${token_file}"
    elif [ "${parent_dir}" = "Models" ] || [ "${parent_dir}" = "Services" ] || [ "${parent_dir}" = "ViewModels" ] || [ "${parent_dir}" = "components" ]; then
        append_line_once "${grandparent_dir}" "${token_file}"
    fi
}

build_targeted_test_candidates() {
    local changed_file_list="$1"
    local targeted_tests_file="$2"
    local full_reasons_file="$3"
    local token_file
    local test_file_paths
    local exact_matches
    local fuzzy_matches
    local file_path
    local token
    local token_lower
    local base_name
    local base_lower

    token_file="$(new_tmp_file)"
    test_file_paths="$(new_tmp_file)"
    exact_matches="$(new_tmp_file)"
    fuzzy_matches="$(new_tmp_file)"

    : > "${targeted_tests_file}"
    : > "${exact_matches}"
    : > "${fuzzy_matches}"

    find "${PROJECT_DIR}/Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests" \
        -type f -name '*Tests.swift' | sort > "${test_file_paths}"

    while IFS= read -r file_path; do
        [ -n "${file_path}" ] || continue
        case "${file_path}" in
            Packages/MeetingAssistantCore/Tests/MeetingAssistantCoreTests/*Tests.swift)
                append_line_once "$(basename "${file_path}" .swift)" "${exact_matches}"
                ;;
            *.swift)
                map_tokens_from_changed_file "${file_path}" "${token_file}"
                ;;
        esac
    done < "${changed_file_list}"

    while IFS= read -r token; do
        [ -n "${token}" ] || continue
        token_lower="$(lowercase "${token}")"

        if [ "${#token_lower}" -lt 4 ]; then
            continue
        fi

        while IFS= read -r file_path; do
            [ -n "${file_path}" ] || continue
            base_name="$(basename "${file_path}" .swift)"
            base_lower="$(lowercase "${base_name}")"

            if [ "${base_lower}" = "${token_lower}tests" ] || [ "${base_lower}" = "${token_lower}" ]; then
                append_line_once "${base_name}" "${exact_matches}"
            elif [ "${#token_lower}" -ge 6 ] && [[ "${base_lower}" == *"${token_lower}"*tests* ]]; then
                append_line_once "${base_name}" "${fuzzy_matches}"
            fi
        done < "${test_file_paths}"
    done < "${token_file}"

    if [ -f "${TEST_MAPPING_CONFIG}" ]; then
        while IFS='|' read -r pattern mapped_tests; do
            [ -n "${pattern}" ] || continue
            case "${pattern}" in
                \#*)
                    continue
                    ;;
            esac

            while IFS= read -r file_path; do
                [ -n "${file_path}" ] || continue
                if [[ "${file_path}" == ${pattern} ]]; then
                    IFS=',' read -r -a mapped_array <<< "${mapped_tests}"
                    for mapped_test in "${mapped_array[@]}"; do
                        append_line_once "${mapped_test}" "${exact_matches}"
                    done
                fi
            done < "${changed_file_list}"
        done < "${TEST_MAPPING_CONFIG}"
    fi

    cat "${exact_matches}" "${fuzzy_matches}" | sed '/^$/d' | sort -u > "${targeted_tests_file}"

    if [ ! -s "${targeted_tests_file}" ]; then
        append_line_once "No trustworthy targeted test mapping from changed files" "${full_reasons_file}"
    fi
}

load_decision_file() {
    local decision_file="$1"
    local decision_header_file
    local reasons_file
    local targeted_tests_file
    local header_count
    if [ ! -f "${decision_file}" ]; then
        echo "Error: decision file does not exist: ${decision_file}"
        return 1
    fi

    decision_header_file="$(new_tmp_file)"
    reasons_file="$(new_tmp_file)"
    targeted_tests_file="$(new_tmp_file)"
    if ! python3 - "${decision_file}" > "${decision_header_file}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    result = json.load(handle)
decision = result.get("decision", {})
selected_lane = decision.get("selectedLane")
strategy = decision.get("strategy")
diff_range = decision.get("diffRange", "reused decision")
reasons = decision.get("reasons", [])
tests = decision.get("targetedTests", [])
if selected_lane not in {"fast", "full"}:
    raise SystemExit("invalid selected lane")
if not isinstance(strategy, str) or not isinstance(diff_range, str):
    raise SystemExit("invalid decision metadata")
if not isinstance(reasons, list) or not all(isinstance(item, str) for item in reasons):
    raise SystemExit("invalid decision reasons")
if not isinstance(tests, list) or not all(isinstance(item, str) for item in tests):
    raise SystemExit("invalid targeted tests")
print(selected_lane)
print(strategy)
print(diff_range)
PY
    then
        return 1
    fi

    header_count="$(wc -l < "${decision_header_file}" | tr -d ' ')"
    if [ "${header_count}" -ne 3 ]; then
        echo "Error: decision file has invalid metadata: ${decision_file}"
        return 1
    fi
    {
        IFS= read -r SELECTED_LANE
        IFS= read -r DECISION_STRATEGY
        IFS= read -r DIFF_RANGE_LABEL
    } < "${decision_header_file}"

    FULL_RISK_REASONS=()
    if ! python3 - "${decision_file}" > "${reasons_file}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    for item in json.load(handle).get("decision", {}).get("reasons", []):
        print(item)
PY
    then
        return 1
    fi
    while IFS= read -r reason; do
        [ -n "${reason}" ] && FULL_RISK_REASONS+=("${reason}")
    done < "${reasons_file}"

    TARGETED_TESTS_RESULT=()
    if ! python3 - "${decision_file}" > "${targeted_tests_file}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    for item in json.load(handle).get("decision", {}).get("targetedTests", []):
        print(item)
PY
    then
        return 1
    fi
    while IFS= read -r test_identifier; do
        [ -n "${test_identifier}" ] && TARGETED_TESTS_RESULT+=("${test_identifier}")
    done < "${targeted_tests_file}"

    if ! python3 - "${decision_file}" > "${changed_file_list}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    changed_files = json.load(handle).get("decision", {}).get("changedFiles", [])
if not isinstance(changed_files, list) or not changed_files or not all(isinstance(item, str) and item for item in changed_files):
    raise SystemExit("invalid changed files")
for item in sorted(set(changed_files)):
    print(item)
PY
    then
        echo "Error: decision file has invalid changed files: ${decision_file}"
        return 1
    fi
    CHANGED_FILES_RESULT=()
    while IFS= read -r file_path; do
        [ -n "${file_path}" ] && CHANGED_FILES_RESULT+=("${file_path}")
    done < "${changed_file_list}"

    DECISION_CODE_RELEVANT="$(python3 - "${decision_file}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle).get("decision", {}).get("codeRelevant")
if not isinstance(value, bool):
    raise SystemExit("invalid code relevance")
print(int(value))
PY
    )"
    DECISION_GUIDANCE_RELEVANT="$(python3 - "${decision_file}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    value = json.load(handle).get("decision", {}).get("guidanceRelevant")
if not isinstance(value, bool):
    raise SystemExit("invalid guidance relevance")
print(int(value))
PY
    )"
    return 0
}

main() {

    local changed_file_list
    local full_reasons_file
    local targeted_tests_file
    local modules_file
    local swift_files_changed=0
    local product_source_files_changed=0
    local added_lines=0
    local module_count=0
    local targeted_count=0
    local code_relevant=0
    local guidance_relevant=0
    local should_run_full=0
    local should_run_intermediate=0
    local reason
    local test_identifier
    local targeted_test_args=""
    local quoted_test_identifier
    local file_path
    local module_name

    trap cleanup_tmp_files EXIT
    cd "${PROJECT_DIR}" || return 1

    changed_file_list="$(new_tmp_file)"
    full_reasons_file="$(new_tmp_file)"
    targeted_tests_file="$(new_tmp_file)"
    modules_file="$(new_tmp_file)"

    if [ -n "${DECISION_FILE}" ]; then
        load_decision_file "${DECISION_FILE}" || return 1
        code_relevant="${DECISION_CODE_RELEVANT}"
        guidance_relevant="${DECISION_GUIDANCE_RELEVANT}"
        targeted_count=0
        : > "${full_reasons_file}"
        : > "${targeted_tests_file}"
        if [ "${#FULL_RISK_REASONS[@]}" -gt 0 ]; then
            for reason in "${FULL_RISK_REASONS[@]}"; do
                [ -n "${reason}" ] && printf '%s\n' "${reason}" >> "${full_reasons_file}"
            done
        fi
        if [ "${#TARGETED_TESTS_RESULT[@]}" -gt 0 ]; then
            for test_identifier in "${TARGETED_TESTS_RESULT[@]}"; do
                [ -n "${test_identifier}" ] && printf '%s\n' "${test_identifier}" >> "${targeted_tests_file}"
            done
        fi
        targeted_count="$(sed '/^$/d' "${targeted_tests_file}" | wc -l | tr -d ' ')"
        if [ "${SELECTED_LANE}" = "full" ]; then
            should_run_full=1
        elif [ "${DECISION_STRATEGY}" = "intermediate-gate" ]; then
            should_run_intermediate=1
        fi
    else
    if ! collect_changed_files "${changed_file_list}"; then
        return 1
    fi

    if [ ! -s "${changed_file_list}" ]; then
        echo "No changed files detected. Nothing to validate."
        return 0
    fi

    CHANGED_FILES_RESULT=()
    while IFS= read -r file_path; do
        [ -n "${file_path}" ] && CHANGED_FILES_RESULT+=("${file_path}")
    done < "${changed_file_list}"

    while IFS= read -r file_path; do
        [ -n "${file_path}" ] || continue

        case "${file_path}" in
            *.swift|*.m|*.mm|*.h|*.c|*.cpp|Makefile|Package.swift|scripts/*|.github/workflows/*|*.xcodeproj/*|*.xcworkspace/*)
                code_relevant=1
                ;;
        esac

        case "${file_path}" in
            AGENTS.md|.agents/docs/*|.agents/skills/*)
                guidance_relevant=1
                ;;
        esac

        case "${file_path}" in
            *.swift)
                swift_files_changed=$((swift_files_changed + 1))
                ;;
        esac

        if is_product_swift_path "${file_path}"; then
            product_source_files_changed=$((product_source_files_changed + 1))
        fi

        if should_treat_as_infra_trigger "${file_path}"; then
            append_line_once "Build/release/test infrastructure changed (${file_path})" "${full_reasons_file}"
        fi

        if should_treat_as_high_risk_path "${file_path}"; then
            append_line_once "High-risk path changed (${file_path})" "${full_reasons_file}"
        fi

        case "${file_path}" in
            Packages/MeetingAssistantCore/Sources/*/*)
                module_name="$(printf '%s\n' "${file_path}" | awk -F/ '{print $4}')"
                append_line_once "${module_name}" "${modules_file}"
                ;;
        esac
    done < "${changed_file_list}"

    module_count="$(sort -u "${modules_file}" | sed '/^$/d' | wc -l | tr -d ' ')"
    if [ "${module_count}" -gt 1 ]; then
        append_line_once "Cross-module change detected (${module_count} modules touched)" "${full_reasons_file}"
    fi

    added_lines="$(count_added_lines "${changed_file_list}")"
    if [ "${added_lines}" -gt 300 ]; then
        append_line_once "Large delta detected (${added_lines} added lines > 300)" "${full_reasons_file}"
    fi

    if [ "${product_source_files_changed}" -gt 8 ]; then
        append_line_once "High product source-file churn detected (${product_source_files_changed} files > 8)" "${full_reasons_file}"
    fi

    if [ "${FORCE_FULL}" -eq 1 ]; then
        append_line_once "Forced full gate by flag (--force-full)" "${full_reasons_file}"
    fi

    if [ -s "${full_reasons_file}" ]; then
        should_run_full=1
    fi

    if [ -z "${DECISION_FILE}" ] && [ "${guidance_relevant}" -eq 1 ]; then
        echo "- Running guidance gate..."
        run_cmd "make guidance-check" || return $?
        echo "  Guidance passed."
        DECISION_CODE_RELEVANT="${code_relevant}"
        DECISION_GUIDANCE_RELEVANT="${guidance_relevant}"
    fi

    if [ "${code_relevant}" -eq 0 ] && [ "${should_run_full}" -eq 0 ]; then
        echo "Only non-code files changed. Skipping scoped build/tests."
        return 0
    fi

    if [ -z "${DECISION_FILE}" ] && [ "${should_run_full}" -eq 0 ]; then
        build_targeted_test_candidates "${changed_file_list}" "${targeted_tests_file}" "${full_reasons_file}"
        targeted_count="$(sed '/^$/d' "${targeted_tests_file}" | wc -l | tr -d ' ')"

        if [ "${targeted_count}" -gt "${MAX_TARGETED}" ]; then
            should_run_intermediate=1
        fi

        if [ -s "${full_reasons_file}" ]; then
            should_run_full=1
        fi
    fi

    FULL_RISK_REASONS=()
    if [ -s "${full_reasons_file}" ]; then
        while IFS= read -r reason; do
            [ -n "${reason}" ] || continue
            FULL_RISK_REASONS+=("${reason}")
        done < "${full_reasons_file}"
    fi
    if [ "${should_run_full}" -eq 1 ]; then
        SELECTED_LANE="full"
        DECISION_STRATEGY="full-gate"
    elif [ "${should_run_intermediate}" -eq 1 ]; then
        SELECTED_LANE="fast"
        DECISION_STRATEGY="intermediate-gate"
    else
        SELECTED_LANE="fast"
        DECISION_STRATEGY="scoped-validation"
    fi
    fi

    if [ -n "${DECISION_FILE}" ] && [ "${guidance_relevant}" -eq 1 ]; then
        echo "- Running guidance gate..."
        run_cmd "make guidance-check" || return $?
        echo "  Guidance passed."
        DECISION_CODE_RELEVANT="${code_relevant}"
        DECISION_GUIDANCE_RELEVANT="${guidance_relevant}"
    fi

    echo "Scoped validation plan:"
    echo "- Changed files: $(wc -l < "${changed_file_list}" | tr -d ' ')"
    echo "- Swift files changed: ${swift_files_changed}"
    echo "- Product source files changed: ${product_source_files_changed}"
    echo "- Added lines (${DIFF_RANGE_LABEL}): ${added_lines}"
    echo "- Candidate targeted tests: ${targeted_count}"

    TARGETED_TESTS_RESULT=()
    while IFS= read -r test_identifier; do
        [ -n "${test_identifier}" ] || continue
        TARGETED_TESTS_RESULT+=("${test_identifier}")
        quoted_test_identifier="$(printf '%q' "${test_identifier}")"
        targeted_test_args+=" --file ${quoted_test_identifier}"
    done < "${targeted_tests_file}"

    # Fast-fail: run lint first (cheap gate, catches style issues before build)
    if [ "${code_relevant}" -eq 1 ]; then
        echo "- Running lint gate..."
        run_cmd "make lint" || return $?
        echo "  Lint passed."
    fi

    if [ "${should_run_full}" -eq 1 ]; then
        echo "- Strategy: full gate (make build-test)"
        echo "- Full-gate reasons:"
        while IFS= read -r reason; do
            [ -n "${reason}" ] || continue
            echo "  - ${reason}"
        done < "${full_reasons_file}"

        run_cmd "make build-test"
        return $?
    fi

    if [ "${should_run_intermediate}" -eq 1 ]; then
        echo "- Strategy: intermediate gate (build + test-full)"
        echo "- Reason: mapped targeted tests exceed threshold (${targeted_count} > ${MAX_TARGETED})"

        if [ "${RUN_BUILD}" -eq 1 ]; then
            run_cmd "make build" || return $?
        else
            echo "- Narrow build step skipped (--no-build)"
        fi

        run_cmd "make test-full" || return $?

        return 0
    fi

    echo "- Strategy: scoped checks"
    if [ "${RUN_BUILD}" -eq 1 ]; then
        run_cmd "make build" || return $?
    else
        echo "- Narrow build step skipped (--no-build)"
    fi

    if [ -n "${targeted_test_args}" ]; then
        if [ "${AGENT_MODE}" -eq 1 ]; then
            run_cmd "./scripts/run-tests.sh --suite dev${targeted_test_args} --agent" || return $?
        else
            run_cmd "./scripts/run-tests.sh --suite dev${targeted_test_args}" || return $?
        fi
    fi

    return 0
}

emit_agent_result() {
    local exit_code="$1"
    if [ "${AGENT_MODE}" -eq 0 ]; then
        return
    fi

    local end_time
    local duration
    local status
    local error_count
    local summary

    end_time="$(date +%s)"
    duration=$((end_time - START_TIME))
    status="PASS"
    summary="Scoped validation passed"

    if [ "${exit_code}" -ne 0 ]; then
        status="FAIL"
        summary="Scoped validation failed"
    fi

    error_count="0"
    if [ "${exit_code}" -ne 0 ] && [ -f "${LOG_PATH}" ]; then
        error_count="$(ma_agent_error_count "${LOG_PATH}")"
        if [ "${error_count}" -eq 0 ]; then
            error_count=1
        fi
    fi

    targeted_tests_json="[]"
    if [ "${#TARGETED_TESTS_RESULT[@]}" -gt 0 ]; then
        targeted_tests_json="$(ma_agent_json_array "${TARGETED_TESTS_RESULT[@]}")"
    fi
    reasons_json="[]"
    if [ "${#FULL_RISK_REASONS[@]}" -gt 0 ]; then
        reasons_json="$(ma_agent_json_array "${FULL_RISK_REASONS[@]}")"
    fi
    changed_files_json="[]"
    if [ "${#CHANGED_FILES_RESULT[@]}" -gt 0 ]; then
        changed_files_json="$(ma_agent_json_array "${CHANGED_FILES_RESULT[@]}")"
    fi
    commands_json="[{\"name\":\"scope-check\",\"status\":\"${status}\",\"durationSec\":${duration},\"log\":\"$(ma_agent_json_escape "${LOG_PATH}")\"}]"
    decision_json="{\"strategy\":\"${DECISION_STRATEGY}\",\"selectedLane\":\"${SELECTED_LANE}\",\"fullRisk\":$([ "${SELECTED_LANE}" = "full" ] && echo true || echo false),\"codeRelevant\":$([ "${code_relevant:-0}" -eq 1 ] && echo true || echo false),\"guidanceRelevant\":$([ "${guidance_relevant:-0}" -eq 1 ] && echo true || echo false),\"changedFiles\":${changed_files_json},\"reasons\":${reasons_json},\"targetedTests\":${targeted_tests_json},\"diffRange\":\"$(ma_agent_json_escape "${DIFF_RANGE_LABEL}")\"}"
    ma_agent_write_result_json "${RESULT_PATH}" "scope-check" "${status}" "${duration}" "${LOG_PATH}" "${error_count}" "${summary}" "${commands_json}" "${decision_json}"
    ma_agent_emit_result "scope-check" "${status}" "${duration}" "${LOG_PATH}" "${error_count}" "${summary}" "${RESULT_PATH}"
}

parse_args "$@"
prepare_agent_logging
main
EXIT_CODE=$?
emit_agent_result "${EXIT_CODE}"
exit "${EXIT_CODE}"
