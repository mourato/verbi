#!/bin/bash
# =============================================================================
# debug-app.sh - Builds and runs Verbi in debug mode via CLI
# =============================================================================
# Uses xcodebuild for a Debug build. Faster than Release for development.
# CLI-first workflow with optional test execution.
# =============================================================================

set -e

# Configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/config/app_identity.sh
source "${PROJECT_DIR}/scripts/config/app_identity.sh"

XCODEPROJ="${PROJECT_DIR}/${XCODEPROJ_NAME}"
DERIVED_DATA="${PROJECT_DIR}/.xcode-build"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Building ${APP_PRODUCT_NAME} (Debug Mode)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check if xcodeproj exists
if [ ! -d "${XCODEPROJ}" ]; then
    echo -e "${RED}Error: Xcode project not found at ${XCODEPROJ}${NC}"
    echo -e "${YELLOW}Ensure you are in the repo root and that ${XCODEPROJ_NAME} exists.${NC}"
    exit 1
fi

# Build Debug
echo -e "${YELLOW}[1/2]${NC} Building with canonical build entrypoint (Debug)..."
"${PROJECT_DIR}/scripts/run-build.sh" --configuration Debug

BUILD_DIR="${DERIVED_DATA}/Build/Products/Debug"
APP_PATH="${BUILD_DIR}/${APP_PRODUCT_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    echo -e "${RED}Error: Build failed. App not found at ${APP_PATH}${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Build completed${NC}"

# Handle command line arguments
if [[ "$1" == "--test" || "$1" == "-t" ]]; then
    echo -e "${YELLOW}[2/2]${NC} Running tests..."
    echo ""
    "${PROJECT_DIR}/scripts/run-tests-xcode.sh" --strict-xcode
    echo -e "${GREEN}✓ Tests completed${NC}"
elif [[ "$1" == "--run" || "$1" == "-r" ]]; then
    echo -e "${YELLOW}[2/2]${NC} Running ${APP_PRODUCT_NAME}..."
    echo ""
    open "${APP_PATH}"
else
    echo ""
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo ""
    echo -e "App location:"
    echo -e "  ${YELLOW}${APP_PATH}${NC}"
    echo ""
    echo -e "To run the app:"
    echo -e "  ${YELLOW}open \"${APP_PATH}\"${NC}"
    echo -e "  or: ${YELLOW}$0 --run${NC}"
    echo ""
    echo -e "To run tests:"
    echo -e "  ${YELLOW}$0 --test${NC}"
    echo ""
fi
