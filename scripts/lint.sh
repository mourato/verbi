#!/bin/bash
# MARK: - Lint Script for MeetingAssistant
# Runs SwiftLint and SwiftFormat with optional compact agent output.

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STYLE_CONFIG_DIR="${AGENT_CONFIG_HOME:-${HOME}/.agents}/skills/swift-conventions/config"

# shellcheck source=scripts/lib/agent-output.sh
source "${SCRIPT_DIR}/lib/agent-output.sh"

STRICT_LINT="${STRICT_LINT:-1}"
AGENT_MODE=0
SOURCES=(App Packages/MeetingAssistantCore/Sources)

if ma_agent_mode_enabled; then
    AGENT_MODE=1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent)
            AGENT_MODE=1
            MA_AGENT_MODE=1
            shift
            ;;
        --files)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                echo "--files requires a space-separated path list" >&2
                exit 2
            fi
            read -r -a SOURCES <<< "$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [--agent] [--files \"path [path ...]\"]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

cd "${PROJECT_ROOT}"

if [ "${AGENT_MODE}" -eq 1 ]; then
    ma_agent_prepare_sandbox_env "${PROJECT_ROOT}"
    ma_agent_prepare_run_dir
    LOG_DIR="${MA_AGENT_RUN_DIR}"
    LINT_LOG="${LOG_DIR}/lint-swiftlint.log"
    FORMAT_LOG="${LOG_DIR}/lint-swiftformat.log"
    RESULT_PATH="${LOG_DIR}/lint.result.json"
else
    LINT_LOG="/tmp/ma-lint-swiftlint.log"
    FORMAT_LOG="/tmp/ma-lint-swiftformat.log"
    RESULT_PATH=""
fi

LINT_EXIT=0
FORMAT_EXIT=0
MISSING_TOOLS=0

if ! command -v swiftlint >/dev/null 2>&1; then
    echo "⚠️  SwiftLint not installed. Install with: brew install swiftlint"
    MISSING_TOOLS=1
    LINT_EXIT=127
else
    SWIFTLINT_ARGS=(lint --config "${STYLE_CONFIG_DIR}/.swiftlint.yml")
    if [ "${STRICT_LINT}" -eq 1 ]; then
        SWIFTLINT_ARGS+=(--strict)
        if [ -f .swiftlint-baseline.json ]; then
            SWIFTLINT_ARGS+=(--baseline .swiftlint-baseline.json)
        fi
    fi
    swiftlint "${SWIFTLINT_ARGS[@]}" "${SOURCES[@]}" >"${LINT_LOG}" 2>&1 || LINT_EXIT=$?
fi

if ! command -v swiftformat >/dev/null 2>&1; then
    echo "⚠️  SwiftFormat not installed. Install with: brew install swiftformat"
    MISSING_TOOLS=1
    FORMAT_EXIT=127
else
    swiftformat --lint --config "${STYLE_CONFIG_DIR}/.swiftformat" "${SOURCES[@]}" >"${FORMAT_LOG}" 2>&1 || FORMAT_EXIT=$?
fi

LINT_WARNINGS=0
LINT_ERRORS=0
FORMAT_WARNINGS=0
FORMAT_ERRORS=0
if [ -f "${LINT_LOG}" ]; then
    LINT_WARNINGS=$(grep -c "warning:" "${LINT_LOG}" || true)
    LINT_ERRORS=$(grep -Eic "error:|fatal error:" "${LINT_LOG}" || true)
fi
if [ -f "${FORMAT_LOG}" ]; then
    FORMAT_WARNINGS=$(grep -c "warning:" "${FORMAT_LOG}" || true)
    FORMAT_ERRORS=$(grep -Eic "error:|fatal error:" "${FORMAT_LOG}" || true)
fi

TOTAL_WARNINGS=$((LINT_WARNINGS + FORMAT_WARNINGS))
TOTAL_ERRORS=$((LINT_ERRORS + FORMAT_ERRORS))
HAS_ISSUES=0
if [ "${LINT_EXIT}" -ne 0 ] || [ "${FORMAT_EXIT}" -ne 0 ] || [ "${MISSING_TOOLS}" -eq 1 ]; then
    HAS_ISSUES=1
fi

STATUS="PASS"
SUMMARY="Lint checks passed"
EXIT_CODE=0
if [ "${HAS_ISSUES}" -eq 1 ]; then
    if [ "${STRICT_LINT}" -eq 1 ]; then
        STATUS="FAIL"
        SUMMARY="Lint checks failed in strict mode"
        EXIT_CODE=1
    else
        STATUS="WARN"
        SUMMARY="Lint warnings/issues detected (non-blocking)"
    fi
fi

if [ "${AGENT_MODE}" -eq 1 ]; then
    if [ "${HAS_ISSUES}" -eq 1 ]; then
        echo "AGENT_LINT_SNIPPET_BEGIN"
        if [ -f "${LINT_LOG}" ]; then
            grep -E "warning:|error:|fatal error:" "${LINT_LOG}" | head -n 20 || true
        fi
        if [ -f "${FORMAT_LOG}" ]; then
            grep -E "warning:|error:|fatal error:" "${FORMAT_LOG}" | head -n 20 || true
        fi
        echo "AGENT_LINT_SNIPPET_END"
    fi

    ma_agent_write_result_json "${RESULT_PATH}" "lint" "${STATUS}" 0 "${LINT_LOG},${FORMAT_LOG}" "${TOTAL_ERRORS}" "${SUMMARY}; warnings=${TOTAL_WARNINGS}"
    ma_agent_emit_result "lint" "${STATUS}" 0 "${LINT_LOG},${FORMAT_LOG}" "${TOTAL_ERRORS}" "${SUMMARY}; warnings=${TOTAL_WARNINGS}" "${RESULT_PATH}"
    exit "${EXIT_CODE}"
fi

echo "🔍 Running SwiftLint/SwiftFormat..."
echo ""

if [ -f "${LINT_LOG}" ] && [ "${LINT_EXIT}" -ne 0 ]; then
    cat "${LINT_LOG}"
fi
if [ -f "${FORMAT_LOG}" ] && [ "${FORMAT_EXIT}" -ne 0 ]; then
    cat "${FORMAT_LOG}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Total warnings: ${TOTAL_WARNINGS}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "${STATUS}" = "FAIL" ]; then
    exit 1
fi

if [ "${STATUS}" = "WARN" ]; then
    echo "⚠️  Lint/format issues detected (non-blocking)."
fi
