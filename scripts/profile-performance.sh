#!/bin/bash
# =============================================================================
# profile-performance.sh - Performance profiling workflow for Verbi
# =============================================================================
# Uses xctrace to profile CPU, Memory, and Animation performance
# CLI-first approach for CI/CD integration
# =============================================================================

set -e

# Configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/config/app_identity.sh
source "${PROJECT_DIR}/scripts/config/app_identity.sh"

XCODEPROJ="${PROJECT_DIR}/${XCODEPROJ_NAME}"
DERIVED_DATA="${PROJECT_DIR}/.xcode-build"
APP_PATH="${DERIVED_DATA}/Build/Products/Debug/${APP_PRODUCT_NAME}.app"
OUTPUT_DIR="${PROJECT_DIR}/performance-reports"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
PROFILE_TYPE="cpu"
DURATION=30
VERBOSE=0
EXTRACT_METRICS=1

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cpu)
            PROFILE_TYPE="cpu"
            shift
            ;;
        --memory)
            PROFILE_TYPE="memory"
            shift
            ;;
        --animation)
            PROFILE_TYPE="animation"
            shift
            ;;
        --all)
            PROFILE_TYPE="all"
            shift
            ;;
        --duration|-d)
            DURATION="$2"
            shift 2
            ;;
        --verbose|-v)
            VERBOSE=1
            shift
            ;;
        --no-report)
            EXTRACT_METRICS=0
            shift
            ;;
        --report)
            EXTRACT_METRICS=1
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Performance profiling for ${APP_PRODUCT_NAME}"
            echo ""
            echo "Profile Types:"
            echo "  --cpu       Profile CPU usage (default)"
            echo "  --memory    Profile memory usage"
            echo "  --animation Profile Core Animation"
            echo "  --all       Run all profile types sequentially"
            echo ""
            echo "Options:"
            echo "  --duration, -d SECS  Profile duration in seconds (default: 30)"
            echo "  --verbose, -v        Verbose output"
            echo "  --report             Export post-run metrics (default: on)"
            echo "  --no-report          Skip post-run metrics extraction"
            echo "  --help, -h           Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --cpu --duration 60    # Profile CPU for 60 seconds"
            echo "  $0 --all                  # Run all profile types"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Performance Profiling - ${APP_PRODUCT_NAME}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if app exists
if [ ! -d "${APP_PATH}" ]; then
    echo -e "${RED}Error: App not found at ${APP_PATH}${NC}"
    echo -e "${YELLOW}Run 'make build' first to build the app.${NC}"
    exit 1
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"
REPORT_PREFIX="${OUTPUT_DIR}/profile_${TIMESTAMP}"

echo -e "${YELLOW}App: ${APP_PATH}${NC}"
echo -e "${YELLOW}Output: ${OUTPUT_DIR}${NC}"
echo -e "${YELLOW}Duration: ${DURATION}s${NC}"
echo ""

# Function to run single profile
run_profile() {
    local profile_type=$1
    local template_name=$2
    local output_file="${REPORT_PREFIX}_${profile_type}.trace"

    echo -e "${BLUE}Starting ${profile_type} profiling...${NC}"

    # Launch app and start profiling
    local xctrace_cmd=(
        xcrun xctrace record
        --template "${template_name}"
        --time-limit "${DURATION}s"
        --output "${output_file}"
        --launch -- "${APP_PATH}"
    )

    if [ $VERBOSE -eq 1 ]; then
        echo -e "${YELLOW}Command: ${xctrace_cmd[*]}${NC}"
    fi

    # xctrace may return non-zero after timed recording even when trace is saved.
    set +e
    "${xctrace_cmd[@]}" >/dev/null 2>&1
    local exit_code=$?
    set -e

    if [ -e "${output_file}" ]; then
        echo -e "${GREEN}✓ ${profile_type} profile saved: ${output_file}${NC}"
        if [ "${EXTRACT_METRICS}" -eq 1 ]; then
            extract_metrics "${output_file}" "${profile_type}"
        fi
        if [ $VERBOSE -eq 1 ] && [ $exit_code -ne 0 ]; then
            echo -e "${YELLOW}xctrace exited with code ${exit_code}, but trace output exists.${NC}"
        fi
    else
        echo -e "${RED}✗ Failed to create ${profile_type} profile${NC}"
    fi
    echo ""
}

extract_metrics() {
    local trace_file=$1
    local profile_type=$2
    local script_path="${PROJECT_DIR}/scripts/extract-trace-metrics.py"
    local metrics_file="${REPORT_PREFIX}_${profile_type}_metrics.txt"
    local json_file="${REPORT_PREFIX}_${profile_type}_metrics.json"

    if [ ! -f "${script_path}" ]; then
        echo -e "${YELLOW}Metrics extractor not found: ${script_path}${NC}"
        return
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo -e "${YELLOW}python3 not found; skipping metrics extraction${NC}"
        return
    fi

    local extractor_cmd=(
        python3 "${script_path}"
        --trace "${trace_file}"
        --out "${metrics_file}"
        --json-out "${json_file}"
    )

    if [ $VERBOSE -eq 1 ]; then
        echo -e "${YELLOW}Metrics command: ${extractor_cmd[*]}${NC}"
    fi

    set +e
    "${extractor_cmd[@]}" >/dev/null 2>&1
    local metrics_exit=$?
    set -e

    if [ $metrics_exit -eq 0 ] && [ -f "${metrics_file}" ]; then
        echo -e "${GREEN}✓ ${profile_type} metrics saved: ${metrics_file}${NC}"
    else
        echo -e "${YELLOW}Could not extract ${profile_type} metrics automatically${NC}"
    fi
}

# Run profiles based on type
case $PROFILE_TYPE in
    "cpu")
        run_profile "cpu" "Time Profiler"
        ;;
    "memory")
        run_profile "memory" "Allocations"
        ;;
    "animation")
        run_profile "animation" "Animation Hitches"
        ;;
    "all")
        run_profile "cpu" "Time Profiler"
        run_profile "memory" "Allocations"
        run_profile "animation" "Animation Hitches"
        ;;
    *)
        echo -e "${RED}Invalid profile type: ${PROFILE_TYPE}${NC}"
        exit 1
        ;;
esac

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Profiling completed${NC}"
echo ""
echo -e "${YELLOW}Reports saved in: ${OUTPUT_DIR}${NC}"
echo -e "${YELLOW}Open with: open ${REPORT_PREFIX}_*.trace${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
