#!/bin/bash
# =============================================================================
# run-tests.sh - Runs tests with formatted output
# =============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_SUITES_CONFIG="${SCRIPT_DIR}/config/test-suites.sh"
# shellcheck source=scripts/config/app_identity.sh
source "${SCRIPT_DIR}/config/app_identity.sh"
source "${TEST_SUITES_CONFIG}"

XCODEPROJ="${PROJECT_DIR}/${XCODEPROJ_NAME}"

# shellcheck source=scripts/lib/agent-output.sh
source "${SCRIPT_DIR}/lib/agent-output.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
VERBOSE=0
QUIET=0
STRICT=0
AGENT_MODE=0
SPECIFIC_TESTS=()
TEST_FILES=()
SUITE="${TEST_SUITE_DEFAULT}"
HEARTBEAT_INTERVAL_SEC="${MA_SWIFT_TEST_HEARTBEAT_INTERVAL_SEC:-15}"
PARALLEL_ENABLED=0
PARALLEL_WORKERS="${TEST_SUITE_PARALLEL_WORKERS}"
PARALLEL_OVERRIDE_SET=0
FORCE_RESOLVE=0

if ma_agent_mode_enabled; then
    AGENT_MODE=1
fi

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --quiet|-q)
            QUIET=1
            shift
            ;;
        --strict|-s)
            STRICT=1
            shift
            ;;
        --agent)
            AGENT_MODE=1
            MA_AGENT_MODE=1
            shift
            ;;
        --test|-t)
            SPECIFIC_TESTS+=("$2")
            shift 2
            ;;
        --file|-f)
            TEST_FILES+=("$2")
            shift 2
            ;;
        --suite)
            SUITE="$2"
            shift 2
            ;;
        --parallel)
            PARALLEL_ENABLED=1
            PARALLEL_OVERRIDE_SET=1
            shift
            ;;
        --no-parallel)
            PARALLEL_ENABLED=0
            PARALLEL_OVERRIDE_SET=1
            shift
            ;;
        --force-resolve)
            FORCE_RESOLVE=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Description: Run the configured Swift test suite with optional targeting, strictness, and agent output."
            echo ""
            echo "Options:"
            echo "  --verbose, -v    Run tests with verbose output"
            echo "  --quiet, -q      Run tests quietly (no output except final result)"
            echo "  --strict, -s     Run tests with strict concurrency checking"
            echo "  --agent          Emit compact machine-readable result lines"
            echo "  --test, -t TEST  Run specific test (repeatable)"
            echo "  --file, -f FILE  Run tests from specific file (repeatable)"
            echo "  --suite NAME     Suite to run: dev, full, smoke, perf, benchmark, sensitive, appkit"
            echo "  --parallel       Force parallel execution when the suite supports it"
            echo "  --no-parallel    Force serial execution"
            echo "  --force-resolve  Force SwiftPM dependency resolution in agent mode"
            echo "  --help, -h       Show this help"
            echo ""
            echo "Examples:"
            echo "  $0"
            echo "  $0 --verbose"
            echo "  $0 --quiet"
            echo "  $0 --agent"
            echo "  $0 --file RecordingViewModelTests"
            echo "  $0 --test testInitialState"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

if [ ! -d "${XCODEPROJ}" ]; then
    MESSAGE="Xcode project not found at ${XCODEPROJ}"
    if [ "${AGENT_MODE}" -eq 1 ]; then
        ma_agent_prepare_run_dir
        LOG_DIR="${MA_AGENT_RUN_DIR}"
        LOG_PATH="${LOG_DIR}/test-swift.log"
        RESULT_PATH="${LOG_DIR}/test-swift.result.json"
        ma_agent_write_result_json "${RESULT_PATH}" "test" "FAIL" 0 "${LOG_PATH}" 1 "${MESSAGE}"
        ma_agent_emit_result "test" "FAIL" 0 "${LOG_PATH}" 1 "${MESSAGE}" "${RESULT_PATH}"
    else
        echo -e "${RED}Error: ${MESSAGE}${NC}"
        echo -e "${YELLOW}Ensure you are in the repo root and that ${XCODEPROJ_NAME} exists.${NC}"
    fi
    exit 1
fi

# Auto-enable verbose output in CI for better diagnostics outside agent mode
if [ "${CI:-}" = "true" ] && [ "${VERBOSE}" -eq 0 ] && [ "${AGENT_MODE}" -eq 0 ]; then
    VERBOSE=1
fi

# Enable Swift backtraces on crashes in CI
if [ "${CI:-}" = "true" ]; then
    export SWIFT_BACKTRACE=enable
    export SWIFT_BACKTRACE_MODE=full
fi

suite_skip_regex=""
suite_filter_regex=""
suite_allows_parallel=0
# ponytail: keep functional suites serial while they share process-wide
# UserDefaults and Keychain state; revisit with per-test isolation if runtime
# becomes material. Explicit --parallel remains available for deliberate runs.

case "${SUITE}" in
    dev)
        suite_skip_regex="${TEST_SUITE_DEV_SKIP_REGEX}"
        export MA_SKIP_OVERLAY_LIFECYCLE_TESTS=1
        ;;
    full)
        suite_skip_regex="${TEST_SUITE_FULL_SKIP_REGEX}"
        export MA_SKIP_OVERLAY_LIFECYCLE_TESTS=1
        ;;
    smoke)
        suite_filter_regex="${TEST_SUITE_SMOKE_FILTER_REGEX}"
        suite_skip_regex="${TEST_SUITE_SMOKE_SKIP_REGEX}"
        export MA_SKIP_OVERLAY_LIFECYCLE_TESTS=1
        ;;
    perf)
        suite_filter_regex="${TEST_SUITE_PERFORMANCE_FILTER_REGEX}"
        export MA_SKIP_OVERLAY_LIFECYCLE_TESTS=1
        ;;
    benchmark)
        suite_filter_regex="${TEST_SUITE_BENCHMARK_FILTER_REGEX}"
        export MA_SKIP_OVERLAY_LIFECYCLE_TESTS=1
        ;;
    sensitive)
        suite_filter_regex="${TEST_SUITE_SENSITIVE_FILTER_REGEX}"
        export MA_SKIP_OVERLAY_LIFECYCLE_TESTS=1
        ;;
    appkit)
        suite_filter_regex="${TEST_SUITE_APPKIT_FILTER_REGEX}"
        unset MA_SKIP_OVERLAY_LIFECYCLE_TESTS
        ;;
    *)
        echo -e "${RED}Unknown suite: ${SUITE}${NC}"
        exit 1
        ;;
esac

TEST_ARGS=()
TARGET_DESCRIPTION="${SUITE} suite"
TARGET_LABEL="${SUITE}"
regex_escape() {
    printf '%s' "$1" | sed 's/[.[\*^$()+?{|\\]/\\&/g'
}

join_regex_values() {
    local value
    local escaped
    local joined=""
    for value in "$@"; do
        escaped="$(regex_escape "${value}")"
        if [ -n "${joined}" ]; then
            joined+="|"
        fi
        joined+="${escaped}"
    done
    printf '%s' "${joined}"
}

if [ "${#TEST_FILES[@]}" -gt 0 ]; then
    COMBINED_TEST_FILTER="$(join_regex_values "${TEST_FILES[@]}")"
    TEST_ARGS+=(--filter "(${COMBINED_TEST_FILTER})")
    TARGET_DESCRIPTION="tests from files: $(IFS=', '; echo "${TEST_FILES[*]}")"
    TARGET_LABEL="${TEST_FILES[0]}"
elif [ "${#SPECIFIC_TESTS[@]}" -gt 0 ]; then
    COMBINED_TEST_FILTER="$(join_regex_values "${SPECIFIC_TESTS[@]}")"
    TEST_ARGS+=(--filter "(${COMBINED_TEST_FILTER})")
    TARGET_DESCRIPTION="specific tests: $(IFS=', '; echo "${SPECIFIC_TESTS[*]}")"
    TARGET_LABEL="${SPECIFIC_TESTS[0]}"
elif [ -n "${suite_filter_regex}" ]; then
    TEST_ARGS+=(--filter "${suite_filter_regex}")
fi

if [ -n "${suite_skip_regex}" ]; then
    TEST_ARGS+=(--skip "${suite_skip_regex}")
fi

if [ "${VERBOSE}" -eq 1 ]; then
    TEST_ARGS+=(--verbose)
fi

if [ "${STRICT}" -eq 1 ]; then
    TEST_ARGS+=(-Xswiftc -strict-concurrency=complete)
fi

if [ "${PARALLEL_OVERRIDE_SET}" -eq 0 ] && [ "${#TEST_FILES[@]}" -eq 0 ] && [ "${#SPECIFIC_TESTS[@]}" -eq 0 ] && [ "${suite_allows_parallel}" -eq 1 ]; then
    PARALLEL_ENABLED=1
fi

if [ "${PARALLEL_ENABLED}" -eq 1 ]; then
    TEST_ARGS+=(--parallel --num-workers "${PARALLEL_WORKERS}")
fi

SAFE_TARGET_LABEL="$(echo "${TARGET_LABEL}" | tr -cs '[:alnum:]' '_' | sed 's/^_//; s/_$//')"
if [ -z "${SAFE_TARGET_LABEL}" ]; then
    SAFE_TARGET_LABEL="all"
fi
if [ "${MA_SWIFTPM_RESOLVE_FORCE:-0}" = "1" ]; then
    FORCE_RESOLVE=1
fi
AGENT_SWIFTPM_SCRATCH_PATH="${MA_SWIFTPM_SCRATCH_PATH:-${PROJECT_DIR}/.tmp/swiftpm-agent}"

clear_stale_swiftpm_lock() {
    local lock_path="${PROJECT_DIR}/Packages/VerbiCore/.build/.lock"
    if [ ! -f "${lock_path}" ]; then
        return
    fi

    local lock_pid
    lock_pid="$(cat "${lock_path}" 2>/dev/null || true)"
    if ! [[ "${lock_pid}" =~ ^[0-9]+$ ]]; then
        rm -f "${lock_path}"
        return
    fi

    if ! kill -0 "${lock_pid}" 2>/dev/null; then
        rm -f "${lock_path}"
    fi
}

compute_swiftpm_dependency_fingerprint() {
    local fingerprint_files=(
        "${PROJECT_DIR}/Packages/VerbiCore/Package.swift"
        "${PROJECT_DIR}/Packages/VerbiCore/Package.resolved"
        "${PROJECT_DIR}/Package.swift"
        "${PROJECT_DIR}/Verbi.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    )
    local file_path

    {
        for file_path in "${fingerprint_files[@]}"; do
            if [ -f "${file_path}" ]; then
                printf 'FILE:%s\n' "${file_path#${PROJECT_DIR}/}"
                cat "${file_path}"
            fi
        done
        printf 'SWIFT_VERSION\n'
        swift --version 2>&1
    } | shasum -a 256 | awk '{print $1}'
}

should_resolve_swiftpm_dependencies() {
    local marker_path="$1"
    local scratch_path="$2"
    local current_fingerprint
    local previous_fingerprint

    current_fingerprint="$(compute_swiftpm_dependency_fingerprint)"
    [ -n "${current_fingerprint}" ] || return 0
    DEPENDENCY_FINGERPRINT="${current_fingerprint}"

    [ "${FORCE_RESOLVE}" -eq 1 ] && return 0
    if [ -f "${marker_path}" ] && [ -d "${scratch_path}/checkouts" ]; then
        previous_fingerprint="$(cat "${marker_path}" 2>/dev/null || true)"
        if [ "${previous_fingerprint}" = "${current_fingerprint}" ]; then
            return 1
        fi
    fi
    return 0
}

resolve_swiftpm_dependencies() {
    local scratch_path="$1"
    local marker_path="${scratch_path}/.ma-swiftpm-resolve.fingerprint"
    local marker_tmp="${marker_path}.tmp.${PPID}"

    mkdir -p "${scratch_path}"
    if ! should_resolve_swiftpm_dependencies "${marker_path}" "${scratch_path}"; then
        echo "SwiftPM resolve skipped: dependency fingerprint unchanged."
        return 0
    fi

    echo "Resolving SwiftPM dependencies."
    if ! swift package resolve --disable-sandbox --scratch-path "${scratch_path}" >/dev/null; then
        rm -f "${marker_tmp}"
        return 1
    fi
    printf '%s\n' "${DEPENDENCY_FINGERPRINT}" > "${marker_tmp}"
    mv -f "${marker_tmp}" "${marker_path}"
}

if [ "${AGENT_MODE}" -eq 1 ]; then
    ma_agent_prepare_run_dir
    LOG_DIR="${MA_AGENT_RUN_DIR}"
    LOG_PATH="${LOG_DIR}/test-swift-${SAFE_TARGET_LABEL}.log"
    RESULT_PATH="${LOG_DIR}/test-swift-${SAFE_TARGET_LABEL}.result.json"
else
    LOG_PATH="/tmp/ma-test-swift-${SAFE_TARGET_LABEL}.log"
    RESULT_PATH=""
fi

if [ "${QUIET}" -eq 0 ] && [ "${AGENT_MODE}" -eq 0 ]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  Running Tests (${TARGET_DESCRIPTION})${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
fi

run_swift_tests() {
    cd "${PROJECT_DIR}/Packages/VerbiCore"
    local scratch_path=""
    if [ "${AGENT_MODE}" -eq 1 ]; then
        scratch_path="${AGENT_SWIFTPM_SCRATCH_PATH}"
        mkdir -p "${scratch_path}"
    else
        clear_stale_swiftpm_lock
    fi

    if [ "${AGENT_MODE}" -eq 1 ]; then
        if ! resolve_swiftpm_dependencies "${scratch_path}"; then
            return 1
        fi
    else
        swift package resolve >/dev/null
    fi

    if [ "${#TEST_ARGS[@]}" -gt 0 ]; then
        if [ "${AGENT_MODE}" -eq 1 ]; then
            swift test --disable-sandbox --scratch-path "${scratch_path}" "${TEST_ARGS[@]}"
        else
            swift test "${TEST_ARGS[@]}"
        fi
    else
        if [ "${AGENT_MODE}" -eq 1 ]; then
            swift test --disable-sandbox --scratch-path "${scratch_path}"
        else
            swift test
        fi
    fi
}

run_swift_tests_with_heartbeat() {
    (run_swift_tests) >"${LOG_PATH}" 2>&1 &
    local test_pid=$!
    local start_time
    local now
    local next_heartbeat
    local elapsed
    local last_line
    local progress_counts
    local executed
    local passed
    local failed

    start_time=$(date +%s)
    next_heartbeat=$((start_time + HEARTBEAT_INTERVAL_SEC))

    while kill -0 "${test_pid}" 2>/dev/null; do
        sleep 1
        now=$(date +%s)
        if [ "${AGENT_MODE}" -eq 0 ] && [ "${QUIET}" -eq 0 ] && [ "${now}" -ge "${next_heartbeat}" ]; then
            elapsed=$((now - start_time))
            if progress_counts="$(ma_agent_extract_running_test_counts "${LOG_PATH}")"; then
                read -r executed passed failed <<< "${progress_counts}"
                echo -e "${BLUE}... progress (${elapsed}s) | Executed: ${executed} | Passed: ${passed} | Failed: ${failed}${NC}"
            else
                last_line="$(tail -n 1 "${LOG_PATH}" 2>/dev/null | tr -d '\r')"
                if [ -n "${last_line}" ]; then
                    echo -e "${BLUE}... progress (${elapsed}s) | ${last_line}${NC}"
                else
                    echo -e "${BLUE}... progress (${elapsed}s)${NC}"
                fi
            fi
            next_heartbeat=$((now + HEARTBEAT_INTERVAL_SEC))
        fi
    done

    wait "${test_pid}"
    EXIT_CODE=$?
}

START_TIME=$(date +%s)
if [ "${VERBOSE}" -eq 1 ] && [ "${AGENT_MODE}" -eq 0 ] && [ "${QUIET}" -eq 0 ]; then
    (run_swift_tests) 2>&1 | tee "${LOG_PATH}"
    EXIT_CODE=${PIPESTATUS[0]}
else
    run_swift_tests_with_heartbeat
fi
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

RESULT_LINE=""
TEST_TOTAL=""
TEST_PASSED=""
TEST_FAILED=""
if TEST_COUNTS="$(ma_agent_extract_test_counts "${LOG_PATH}")"; then
    read -r TEST_TOTAL TEST_PASSED TEST_FAILED <<< "${TEST_COUNTS}"
fi

if [ -n "${TEST_TOTAL}" ]; then
    RESULT_LINE="Total: ${TEST_TOTAL} | Passed: ${TEST_PASSED} | Failed: ${TEST_FAILED}"
elif [ "${EXIT_CODE}" -eq 0 ]; then
    RESULT_LINE="All tests passed"
else
    RESULT_LINE="Tests failed"
fi

ERROR_COUNT=0
if [ "${EXIT_CODE}" -ne 0 ]; then
    COMPILER_ERROR_COUNT="$(ma_agent_error_count "${LOG_PATH}")"
    TEST_FAILURE_COUNT="$(grep -Eic "Test Case .* failed|Test Suite .* failed" "${LOG_PATH}" || true)"
    ERROR_COUNT=$((COMPILER_ERROR_COUNT + TEST_FAILURE_COUNT))
    if [ "${ERROR_COUNT}" -eq 0 ]; then
        ERROR_COUNT=1
    fi
fi

if [ "${AGENT_MODE}" -eq 1 ]; then
    STATUS="FAIL"
    if [ "${EXIT_CODE}" -eq 0 ]; then
        STATUS="PASS"
    fi

    if [ "${EXIT_CODE}" -ne 0 ]; then
        ma_agent_failure_excerpt "${LOG_PATH}" "error:|fatal error:|Test Case .* failed|Test Suite .* failed|failed" 20 80
    fi

    TEST_FILES_JSON="[]"
    TESTS_JSON="[]"
    if [ "${#TEST_FILES[@]}" -gt 0 ]; then
        TEST_FILES_JSON="$(ma_agent_json_array "${TEST_FILES[@]}")"
    fi
    if [ "${#SPECIFIC_TESTS[@]}" -gt 0 ]; then
        TESTS_JSON="$(ma_agent_json_array "${SPECIFIC_TESTS[@]}")"
    fi
    DECISION_JSON="{\"strategy\":\"test\",\"suite\":\"$(ma_agent_json_escape "${SUITE}")\",\"targetedFiles\":${TEST_FILES_JSON},\"targetedTests\":${TESTS_JSON}}"
    COMMANDS_JSON="[{\"name\":\"swift test\",\"status\":\"${STATUS}\",\"durationSec\":${DURATION},\"log\":\"$(ma_agent_json_escape "${LOG_PATH}")\"}]"
    ma_agent_write_result_json "${RESULT_PATH}" "test" "${STATUS}" "${DURATION}" "${LOG_PATH}" "${ERROR_COUNT}" "${RESULT_LINE}" "${COMMANDS_JSON}" "${DECISION_JSON}"
    ma_agent_emit_result "test" "${STATUS}" "${DURATION}" "${LOG_PATH}" "${ERROR_COUNT}" "${RESULT_LINE}" "${RESULT_PATH}"
    exit "${EXIT_CODE}"
fi

if [ "${EXIT_CODE}" -ne 0 ] && [ "${VERBOSE}" -eq 0 ]; then
    echo ""
    cat "${LOG_PATH}"
fi

if [ "${EXIT_CODE}" -eq 0 ]; then
    echo -e "${GREEN}✓ ${RESULT_LINE}${NC} (${DURATION}s)"
else
    echo -e "${RED}✗ ${RESULT_LINE}${NC} (${DURATION}s)"
    echo -e "${YELLOW}Full output: ${LOG_PATH}${NC}"
fi

if [ "${QUIET}" -eq 0 ]; then
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
fi

exit "${EXIT_CODE}"
