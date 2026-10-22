#!/bin/zsh
# =============================================================================
# run-summary-benchmark.sh - Runs summary benchmark + regression gate for issue #101
# =============================================================================

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/lib/agent-output.sh
source "${SCRIPT_DIR}/lib/agent-output.sh"

AGENT_MODE=0
MODE="report-only"
RECORD_BASELINE=0

case "${MA_AGENT_MODE:-0}" in
    1|true|TRUE|yes|YES)
        AGENT_MODE=1
        ;;
esac

while [[ $# -gt 0 ]]; do
    case "$1" in
        --agent)
            AGENT_MODE=1
            MA_AGENT_MODE=1
            ;;
        --report-only)
            MODE="report-only"
            ;;
        --enforce)
            MODE="enforce"
            ;;
        --record-baseline)
            RECORD_BASELINE=1
            ;;
        --help|-h)
            echo "Usage: $0 [--report-only|--enforce] [--record-baseline] [--agent]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
    shift
done

BASELINE_PATH="${PROJECT_ROOT}/Packages/VerbiCore/Tests/VerbiCoreTests/Resources/Benchmarks/summary-benchmark-baseline.v1.json"

if [[ "${AGENT_MODE}" -eq 1 ]]; then
    ma_agent_prepare_run_dir
    LOG_DIR="${MA_AGENT_RUN_DIR}"
    LOG_PATH="${LOG_DIR}/summary-benchmark-${MODE}.stream.log"
    RESULT_PATH="${LOG_DIR}/summary-benchmark.result.json"
    BENCHMARK_RESULT_PATH="${LOG_DIR}/summary-benchmark-result.v1.json"
else
    LOG_PATH="/tmp/summary-benchmark-${MODE}.stream.log"
    RESULT_PATH=""
    BENCHMARK_RESULT_PATH="/tmp/summary-benchmark-result.v1.json"
fi

BASELINE_SOURCE="commit:$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD)"

START_TIME=$(date +%s)

MA_SUMMARY_BENCHMARK_MODE="${MODE}" \
MA_SUMMARY_BENCHMARK_RESULT_PATH="${BENCHMARK_RESULT_PATH}" \
MA_SUMMARY_BENCHMARK_BASELINE_PATH="${BASELINE_PATH}" \
MA_SUMMARY_BENCHMARK_RECORD_BASELINE="${RECORD_BASELINE}" \
MA_SUMMARY_BENCHMARK_BASELINE_SOURCE="${BASELINE_SOURCE}" \
MA_SKIP_OVERLAY_LIFECYCLE_TESTS=1 \
"${SCRIPT_DIR}/run-tests.sh" --test testSummaryBenchmarkGate >"${LOG_PATH}" 2>&1
EXIT_CODE=$?

if [[ "${AGENT_MODE}" -eq 0 ]] || [[ "${EXIT_CODE}" -ne 0 ]]; then
    cat "${LOG_PATH}"
fi

if [[ "${RECORD_BASELINE}" -eq 1 ]] && [[ "${EXIT_CODE}" -eq 0 ]]; then
    BASELINE_NOTE="baseline updated at ${BASELINE_PATH}"
else
    BASELINE_NOTE="baseline unchanged"
fi

if [[ "${EXIT_CODE}" -eq 0 ]]; then
    SUMMARY="Summary benchmark ${MODE} passed; result=${BENCHMARK_RESULT_PATH}; ${BASELINE_NOTE}"
else
    SUMMARY="Summary benchmark ${MODE} failed; see ${LOG_PATH}"
fi

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

if [[ "${AGENT_MODE}" -eq 1 ]]; then
    STATUS="FAIL"
    ERROR_COUNT=1
    if [[ "${EXIT_CODE}" -eq 0 ]]; then
        STATUS="PASS"
        ERROR_COUNT=0
    fi

    python3 - "${RESULT_PATH}" "${STATUS}" "${DURATION}" "${LOG_PATH}" "${ERROR_COUNT}" "${SUMMARY}" "${MODE}" "${BENCHMARK_RESULT_PATH}" <<'PY'
import json
import sys

result_path, status, duration, log_path, error_count, summary, mode, benchmark_result = sys.argv[1:]
result = {
    "schemaVersion": 2,
    "step": "summary-benchmark",
    "status": status,
    "durationSec": int(duration),
    "log": log_path,
    "errorCount": int(error_count),
    "commands": [{"name": "summary-benchmark", "status": status, "durationSec": int(duration), "log": log_path}],
    "decision": {"strategy": mode, "benchmarkResult": benchmark_result},
    "summary": summary,
}
with open(result_path, "w", encoding="utf-8") as handle:
    json.dump(result, handle, separators=(",", ":"))
    handle.write("\n")
PY

    echo "AGENT_STEP=summary-benchmark"
    echo "AGENT_STATUS=${STATUS}"
    echo "AGENT_DURATION_SEC=${DURATION}"
    echo "AGENT_LOG=${LOG_PATH}"
    echo "AGENT_ERROR_COUNT=${ERROR_COUNT}"
    echo "AGENT_SUMMARY=${SUMMARY}"
    echo "AGENT_RESULT_JSON=${RESULT_PATH}"
    exit "${EXIT_CODE}"
fi

echo "${SUMMARY}"
exit "${EXIT_CODE}"
