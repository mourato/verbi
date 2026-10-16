#!/bin/bash
# =============================================================================
# run-build.sh - Build entry point with optional low-noise agent output mode
# =============================================================================

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/config/app_identity.sh
source "${SCRIPT_DIR}/config/app_identity.sh"

# shellcheck source=scripts/lib/agent-output.sh
source "${SCRIPT_DIR}/lib/agent-output.sh"
# shellcheck source=scripts/config/release_signing.sh
source "${SCRIPT_DIR}/config/release_signing.sh"

XCODEPROJ="${PROJECT_ROOT}/${XCODEPROJ_NAME}"
DERIVED_DATA="${VALIDATE_DERIVED_DATA_PATH:-${PROJECT_ROOT}/.xcode-build}"

CONFIGURATION="Debug"
AGENT_MODE=0

if ma_agent_mode_enabled; then
    AGENT_MODE=1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration|-c)
            CONFIGURATION="$2"
            shift 2
            ;;
        --agent)
            AGENT_MODE=1
            MA_AGENT_MODE=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--configuration Debug|Release] [--agent]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Enable progress bar for agent mode (after argument parsing)
ma_agent_progress_enable

case "${CONFIGURATION}" in
    Debug|Release)
        ;;
    *)
        echo "Invalid configuration: ${CONFIGURATION}. Use Debug or Release."
        exit 1
        ;;
esac

CONFIG_SLUG="$(echo "${CONFIGURATION}" | tr '[:upper:]' '[:lower:]')"

if [ "${AGENT_MODE}" -eq 1 ]; then
    ma_agent_prepare_sandbox_env "${PROJECT_ROOT}"
    ma_agent_prepare_run_dir
    LOG_DIR="${MA_AGENT_RUN_DIR}"
    LOG_PATH="${LOG_DIR}/build-${CONFIG_SLUG}.log"
    RESULT_PATH="${LOG_DIR}/build-${CONFIG_SLUG}.result.json"
else
    LOG_PATH="/tmp/ma-build-${CONFIG_SLUG}.log"
    RESULT_PATH=""
fi

if [ ! -d "${XCODEPROJ}" ]; then
    MSG="Xcode project not found at ${XCODEPROJ}"
    if [ "${AGENT_MODE}" -eq 1 ]; then
        ma_agent_write_result_json "${RESULT_PATH}" "build" "FAIL" 0 "${LOG_PATH}" 1 "${MSG}"
        ma_agent_emit_result "build" "FAIL" 0 "${LOG_PATH}" 1 "${MSG}" "${RESULT_PATH}"
    else
        echo "Error: ${MSG}"
    fi
    exit 1
fi

SAFE_XCODEBUILD_SCRIPT="${SCRIPT_DIR}/xcodebuild-safe.sh"

if [ ! -x "${SAFE_XCODEBUILD_SCRIPT}" ]; then
    MSG="Safe xcodebuild wrapper not executable at ${SAFE_XCODEBUILD_SCRIPT}"
    if [ "${AGENT_MODE}" -eq 1 ]; then
        ma_agent_write_result_json "${RESULT_PATH}" "build" "FAIL" 0 "${LOG_PATH}" 1 "${MSG}"
        ma_agent_emit_result "build" "FAIL" 0 "${LOG_PATH}" 1 "${MSG}" "${RESULT_PATH}"
    else
        echo "Error: ${MSG}"
    fi
    exit 1
fi

START_TIME=$(date +%s)

# Start progress indicator
if [ "${AGENT_MODE}" -eq 1 ]; then
    ma_agent_progress_start "Building ${APP_PRODUCT_NAME} (${CONFIGURATION})"
fi

"${SAFE_XCODEBUILD_SCRIPT}" \
    --project "${XCODEPROJ}" \
    --scheme "${APP_SCHEME}" \
    --configuration "${CONFIGURATION}" \
    --derived-data "${DERIVED_DATA}" \
    --destination 'platform=macOS' \
    --action build >"${LOG_PATH}" 2>&1
EXIT_CODE=$?

# Sign Debug with the release identity so macOS treats it as the installed app
# (menu bar status items, Keychain, and TCC grants are bound to the signing team).
if [ "${EXIT_CODE}" -eq 0 ] && [ "${CONFIGURATION}" = "Debug" ]; then
    DEBUG_APP="${DERIVED_DATA}/Build/Products/Debug/${APP_PRODUCT_NAME}.app"
    if ma_codesign_identity_is_stable "${MA_RELEASE_CODE_SIGN_IDENTITY}" 2 0.10; then
        resolved_identity="$(ma_resolve_codesign_identity "${MA_RELEASE_CODE_SIGN_IDENTITY}")"
        codesign --force --deep --preserve-metadata=entitlements --timestamp=none \
            --sign "${resolved_identity}" "${DEBUG_APP}" >>"${LOG_PATH}" 2>&1
        EXIT_CODE=$?
    else
        echo "Warning: '${MA_RELEASE_CODE_SIGN_IDENTITY}' identity unavailable; Debug build stays ad-hoc signed." >>"${LOG_PATH}"
    fi
fi

END_TIME=$(date +%s)

# Stop progress indicator
if [ "${AGENT_MODE}" -eq 1 ]; then
    if [ "${EXIT_CODE}" -eq 0 ]; then
        ma_agent_progress_stop "success"
    else
        ma_agent_progress_stop "fail"
    fi
fi
DURATION=$((END_TIME - START_TIME))

ERROR_COUNT=0
if [ "${EXIT_CODE}" -ne 0 ]; then
    ERROR_COUNT="$(ma_agent_error_count "${LOG_PATH}")"
    if [ "${ERROR_COUNT}" -eq 0 ]; then
        ERROR_COUNT=1
    fi
fi
SUMMARY="Build ${CONFIGURATION} failed"
if [ "${EXIT_CODE}" -eq 0 ]; then
    SUMMARY="Build ${CONFIGURATION} succeeded"
elif grep -q "BUILD FAILED" "${LOG_PATH}"; then
    SUMMARY="BUILD FAILED (${CONFIGURATION})"
fi

if [ "${AGENT_MODE}" -eq 1 ]; then
    STATUS="FAIL"
    if [ "${EXIT_CODE}" -eq 0 ]; then
        STATUS="PASS"
    fi

    if [ "${EXIT_CODE}" -ne 0 ]; then
        ma_agent_failure_excerpt "${LOG_PATH}" "error:|fatal error:|BUILD FAILED" 20 80
    fi

    ma_agent_write_result_json "${RESULT_PATH}" "build" "${STATUS}" "${DURATION}" "${LOG_PATH}" "${ERROR_COUNT}" "${SUMMARY}"
    ma_agent_emit_result "build" "${STATUS}" "${DURATION}" "${LOG_PATH}" "${ERROR_COUNT}" "${SUMMARY}" "${RESULT_PATH}"
    exit "${EXIT_CODE}"
fi

echo "Building ${APP_PRODUCT_NAME} (${CONFIGURATION})..."
grep -E "(Compiling|Linking|Signing|BUILD|error:|warning:)" "${LOG_PATH}" | head -30 || true
if [ "${EXIT_CODE}" -eq 0 ]; then
    echo "✓ ${CONFIGURATION} build completed"
else
    echo "✗ ${CONFIGURATION} build failed"
    echo "Full output: ${LOG_PATH}"
fi

exit "${EXIT_CODE}"
