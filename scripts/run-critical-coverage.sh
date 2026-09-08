#!/bin/bash
# ======================================================================
# run-critical-coverage.sh - Measure coverage for the curated smoke flows
# ======================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKAGE_DIR="${PROJECT_DIR}/Packages/MeetingAssistantCore"

# shellcheck source=scripts/config/test-suites.sh
source "${SCRIPT_DIR}/config/test-suites.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required to summarize Swift coverage." >&2
    exit 1
fi

COVERAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/verbi-critical-coverage.XXXXXX")"
TEST_LOG="${COVERAGE_ROOT}/test.log"

cleanup() {
    if [ "${MA_COVERAGE_KEEP:-0}" != "1" ]; then
        rm -rf "${COVERAGE_ROOT}"
    fi
}
trap cleanup EXIT

echo "Running critical coverage suite (smoke selection)..."
if ! (
    cd "${PACKAGE_DIR}"
    swift test \
        --disable-sandbox \
        --scratch-path "${COVERAGE_ROOT}" \
        --filter "${TEST_SUITE_SMOKE_FILTER_REGEX}" \
        --enable-code-coverage \
        --quiet
) >"${TEST_LOG}" 2>&1; then
    echo "Critical coverage tests failed:" >&2
    tail -80 "${TEST_LOG}" >&2
    exit 1
fi

COVERAGE_JSON="$(find "${COVERAGE_ROOT}/out/Products/Debug/codecov" -maxdepth 1 -type f -name '*.json' -print | head -n 1)"
if [ -z "${COVERAGE_JSON}" ] || [ ! -f "${COVERAGE_JSON}" ]; then
    echo "Error: Swift did not produce a coverage report." >&2
    exit 1
fi

coverage_summary() {
    local metric="$1"
    jq -r --arg metric "${metric}" '
        reduce [ .data[0].files[]
            | select(.filename | contains("/Sources/"))
            | .summary[$metric]
        ][] as $item
            ({"count": 0, "covered": 0};
                .count += $item.count
                | .covered += $item.covered
            )
        | if .count == 0 then
            "0/0 (0.00%)"
          else
            "\(.covered)/\(.count) (\((.covered * 10000 / .count | round) / 100)% )"
          end
    ' "${COVERAGE_JSON}" | sed 's/% )/%)/'
}

echo "CRITICAL_TEST_SELECTION=${TEST_SUITE_SMOKE_FILTER_REGEX}"
echo "CRITICAL_COVERAGE_LINES=$(coverage_summary lines)"
echo "CRITICAL_COVERAGE_FUNCTIONS=$(coverage_summary functions)"
echo "CRITICAL_COVERAGE=PASS"
