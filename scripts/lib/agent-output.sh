#!/bin/bash
# Shared helpers for low-noise script output used by AI agents.

# Progress bar state variables
_MA_PROGRESS_PID=""
_MA_PROGRESS_START_TIME=""
_MA_PROGRESS_MESSAGE=""
_MA_PROGRESS_ENABLED=0

# Check if output is to a terminal
ma_is_tty() {
    if [ -t 1 ]; then
        return 0
    fi
    return 1
}

ma_agent_mode_enabled() {
    case "${MA_AGENT_MODE:-0}" in
        1|true|TRUE|yes|YES)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Enable progress bar for agent mode
ma_agent_progress_enable() {
    if ma_agent_mode_enabled && ma_is_tty; then
        _MA_PROGRESS_ENABLED=1
    else
        _MA_PROGRESS_ENABLED=0
    fi
}

# Start progress spinner
# Usage: ma_agent_progress_start "message"
ma_agent_progress_start() {
    _MA_PROGRESS_MESSAGE="${1:-Processing}"
    _MA_PROGRESS_START_TIME=$(date +%s)
    
    if [ "${_MA_PROGRESS_ENABLED}" -eq 0 ]; then
        return
    fi

    # Print initial message
    printf "\r[%s] %s... " "▓▓▓▓▓▓▓▓▓▓" "${_MA_PROGRESS_MESSAGE}" >&2
    
    # Start background spinner
    (
        local spin_chars="▓▓░░░░░░░ ▓▓▓░░░░░░ ▓▓▓▓░░░░░ ▓▓▓▓▓░░░░ ▓▓▓▓▓▓░░░ ▓▓▓▓▓▓▓░░ ▓▓▓▓▓▓▓▓░ ▓▓▓▓▓▓▓▓▓"
        local i=0
        while true; do
            if [ "${_MA_PROGRESS_ENABLED}" -eq 0 ]; then
                break
            fi
            local elapsed=$(($(date +%s) - _MA_PROGRESS_START_TIME))
            local idx=$((i % 8))
            local bar="${spin_chars:idx*10:10}"
            printf "\r[%s] %s (%ds)" "${bar}" "${_MA_PROGRESS_MESSAGE}" "${elapsed}" >&2
            sleep 1
            i=$((i + 1))
        done
    ) &
    _MA_PROGRESS_PID=$!
}

# Update progress message
# Usage: ma_agent_progress_update "new message"
ma_agent_progress_update() {
    if [ "${_MA_PROGRESS_ENABLED}" -eq 0 ]; then
        return
    fi
    _MA_PROGRESS_MESSAGE="${1}"
}

# Stop progress spinner
# Usage: ma_agent_progress_stop [success|fail]
ma_agent_progress_stop() {
    local status="${1:-done}"
    
    if [ -n "${_MA_PROGRESS_PID}" ]; then
        kill "${_MA_PROGRESS_PID}" 2>/dev/null || true
        wait "${_MA_PROGRESS_PID}" 2>/dev/null || true
        _MA_PROGRESS_PID=""
    fi
    
    if [ "${_MA_PROGRESS_ENABLED}" -eq 0 ]; then
        return
    fi
    
    local elapsed=$(($(date +%s) - _MA_PROGRESS_START_TIME))
    
    case "${status}" in
        success)
            printf "\r[██████████] %s (completed in %ds)\n" "${_MA_PROGRESS_MESSAGE}" "${elapsed}" >&2
            ;;
        fail)
            printf "\r[XXXXXXXXXX] %s (failed after %ds)\n" "${_MA_PROGRESS_MESSAGE}" "${elapsed}" >&2
            ;;
        *)
            printf "\r[..........] %s (done in %ds)\n" "${_MA_PROGRESS_MESSAGE}" "${elapsed}" >&2
            ;;
    esac
    
    _MA_PROGRESS_ENABLED=0
}

ma_agent_log_dir() {
    printf '%s\n' "${MA_AGENT_LOG_DIR:-/tmp/ma-agent}"
}

ma_agent_prepare_log_dir() {
    ma_agent_prepare_run_dir
}

# Create or reuse the immutable artifact tree for one agent invocation.
# Parent scripts export MA_AGENT_RUN_DIR so nested validation commands share it.
ma_agent_prepare_run_dir() {
    local existing_dir="${MA_AGENT_RUN_DIR:-}"
    if [ -n "${existing_dir}" ]; then
        mkdir -p "${existing_dir}"
        printf '%s\n' "${existing_dir}"
        return
    fi

    local root
    local repo_path
    local repo_hash
    local timestamp
    local run_dir

    root="$(ma_agent_log_dir)"
    mkdir -p "${root}"
    repo_path="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    repo_hash="$(printf '%s' "${repo_path}" | shasum -a 256 | awk '{print substr($1, 1, 16)}')"
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    run_dir="$(mktemp -d "${root}/run-${repo_hash}-${timestamp}-$$-XXXXXX")"

    export MA_AGENT_RUN_DIR="${run_dir}"
    printf '%s\n' "${run_dir}"
}

ma_agent_prepare_sandbox_env() {
    local project_root="$1"
    local sandbox_root="${project_root}/.tmp/agent-env"
    local home_dir="${sandbox_root}/home"
    local tmp_dir="${sandbox_root}/tmp"

    mkdir -p "${home_dir}" "${tmp_dir}"
    mkdir -p "${home_dir}/.cache/clang/ModuleCache"
    mkdir -p "${home_dir}/Library/Caches/org.swift.swiftpm"
    mkdir -p "${home_dir}/Library/org.swift.swiftpm/configuration"
    mkdir -p "${home_dir}/Library/org.swift.swiftpm/security"

    # Pin the config home before HOME moves to the sandbox: consumers resolve
    # skill configs as ${AGENT_CONFIG_HOME:-${HOME}/.agents}.
    export AGENT_CONFIG_HOME="${AGENT_CONFIG_HOME:-$HOME/.agents}"
    export HOME="${home_dir}"
    export TMPDIR="${tmp_dir}"
    export CLANG_MODULE_CACHE_PATH="${home_dir}/.cache/clang/ModuleCache"
}

ma_agent_json_escape() {
    local value="$1"
    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/}
    value=${value//$'\t'/\\t}
    printf '%s' "${value}"
}

ma_agent_json_array() {
    local item
    local first=1
    printf '['
    for item in "$@"; do
        if [ "${first}" -eq 0 ]; then
            printf ','
        fi
        printf '"%s"' "$(ma_agent_json_escape "${item}")"
        first=0
    done
    printf ']'
}

ma_agent_error_count() {
    local log_path="$1"
    local count
    if [ ! -f "${log_path}" ]; then
        printf '0\n'
        return
    fi

    count="$(grep -Ec "error:|fatal error:" "${log_path}" 2>/dev/null || true)"
    if [ -z "${count}" ]; then
        count=0
    fi
    printf '%s\n' "${count}"
}

# Extract test totals from XCTest summary lines in logs.
# Output format: "<total> <passed> <failed>"
ma_agent_extract_test_counts() {
    local log_path="$1"
    local result_line
    local total
    local failed
    local passed

    if [ ! -f "${log_path}" ]; then
        return 1
    fi

    result_line="$(
        grep -A2 -E "Test Suite 'Selected tests' (passed|failed)" "${log_path}" 2>/dev/null \
            | grep -E "Executed [0-9]+ tests?(, with [0-9]+ tests? skipped)? and [0-9]+ failures?|Executed [0-9]+ tests?, with [0-9]+ failures?" \
            | tail -n 1 || true
    )"
    if [ -z "${result_line}" ]; then
        result_line="$(grep -E "Executed [0-9]+ tests?(, with [0-9]+ tests? skipped)? and [0-9]+ failures?|Executed [0-9]+ tests?, with [0-9]+ failures?" "${log_path}" | tail -n 1 || true)"
    fi
    if [ -z "${result_line}" ]; then
        return 1
    fi

    total="$(echo "${result_line}" | sed -E 's/.*Executed ([0-9]+) tests?.*/\1/')"
    failed="$(echo "${result_line}" | sed -E 's/.*(with|and) ([0-9]+) failures?.*/\2/')"

    if ! [[ "${total}" =~ ^[0-9]+$ ]] || ! [[ "${failed}" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    passed=$((total - failed))
    if [ "${passed}" -lt 0 ]; then
        passed=0
    fi

    printf '%s %s %s\n' "${total}" "${passed}" "${failed}"
}

# Extract running test progress from per-test result lines.
# Output format: "<executed> <passed> <failed>"
ma_agent_extract_running_test_counts() {
    local log_path="$1"
    local executed
    local failed
    local passed

    if [ ! -f "${log_path}" ]; then
        return 1
    fi

    executed="$(grep -Eic "Test Case .* (passed|failed)" "${log_path}" || true)"
    failed="$(grep -Eic "Test Case .* failed" "${log_path}" || true)"

    if [ -z "${executed}" ]; then
        executed=0
    fi
    if [ -z "${failed}" ]; then
        failed=0
    fi

    if ! [[ "${executed}" =~ ^[0-9]+$ ]] || ! [[ "${failed}" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    if [ "${executed}" -eq 0 ]; then
        return 1
    fi

    passed=$((executed - failed))
    if [ "${passed}" -lt 0 ]; then
        passed=0
    fi

    printf '%s %s %s\n' "${executed}" "${passed}" "${failed}"
}

ma_agent_failure_excerpt() {
    local log_path="$1"
    local pattern="${2:-error:|fatal error:|failed}"
    local max_matches="${3:-20}"
    local tail_lines="${4:-60}"

    if [ ! -f "${log_path}" ]; then
        echo "AGENT_FAILURE_SNIPPET=log-missing"
        return
    fi

    echo "AGENT_FAILURE_SNIPPET_BEGIN"
    grep -Ei "${pattern}" "${log_path}" | head -n "${max_matches}" || true
    echo "AGENT_FAILURE_LOG_TAIL_BEGIN"
    tail -n "${tail_lines}" "${log_path}" || true
    echo "AGENT_FAILURE_LOG_TAIL_END"
    echo "AGENT_FAILURE_SNIPPET_END"
}

ma_agent_write_result_json() {
    local result_path="$1"
    local step="$2"
    local status="$3"
    local duration_sec="$4"
    local log_path="$5"
    local error_count="$6"
    local summary="$7"
    local commands_json="${8:-}"
    local decision_json="${9:-}"
    local validation_fingerprint="${10:-${MA_AGENT_VALIDATION_FINGERPRINT:-}}"
    local fingerprint_json=""
    if [ -z "${commands_json}" ]; then
        commands_json="[]"
    fi
    if [ -z "${decision_json}" ]; then
        decision_json="{}"
    fi
    if [ -n "${validation_fingerprint}" ]; then
        fingerprint_json=",\"validationFingerprint\":\"$(ma_agent_json_escape "${validation_fingerprint}")\""
    fi

    cat > "${result_path}" <<JSON
{"schemaVersion":2,"step":"$(ma_agent_json_escape "${step}")","status":"$(ma_agent_json_escape "${status}")","durationSec":${duration_sec},"log":"$(ma_agent_json_escape "${log_path}")","errorCount":${error_count},"commands":${commands_json},"decision":${decision_json}${fingerprint_json},"summary":"$(ma_agent_json_escape "${summary}")"}
JSON
}

ma_agent_emit_result() {
    local step="$1"
    local status="$2"
    local duration_sec="$3"
    local log_path="$4"
    local error_count="$5"
    local summary="$6"
    local result_path="$7"

    echo "AGENT_STEP=${step}"
    echo "AGENT_STATUS=${status}"
    echo "AGENT_DURATION_SEC=${duration_sec}"
    echo "AGENT_LOG=${log_path}"
    echo "AGENT_ERROR_COUNT=${error_count}"
    echo "AGENT_SUMMARY=${summary}"
    echo "AGENT_RESULT_JSON=${result_path}"
}
