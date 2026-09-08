#!/bin/bash
# =============================================================================
# build-release.sh - Builds Verbi.app using xcodebuild CLI in Release mode
# =============================================================================
# Uses xcodebuild CLI to create a Release build and exports it to dist/
# CLI-first workflow for consistent builds across environments.
# =============================================================================

set -e
set -o pipefail

MA_RELEASE_SIGNING_MODE_WAS_SET=0
if [ "${MA_RELEASE_SIGNING_MODE+x}" = "x" ]; then
    MA_RELEASE_SIGNING_MODE_WAS_SET=1
fi

# Configuration
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/config/app_identity.sh
source "${PROJECT_DIR}/scripts/config/app_identity.sh"
# shellcheck source=scripts/config/release_signing.sh
source "${PROJECT_DIR}/scripts/config/release_signing.sh"

if [ "${1:-}" = "--ci" ] && [ "${MA_RELEASE_SIGNING_MODE_WAS_SET}" -eq 0 ]; then
    MA_RELEASE_SIGNING_MODE="adhoc"
fi

XCODEPROJ="${PROJECT_DIR}/${XCODEPROJ_NAME}"
DIST_DIR="${PROJECT_DIR}/dist"
DERIVED_DATA="${PROJECT_DIR}/.xcode-build"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Building ${APP_PRODUCT_NAME}.app (Release)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if ! ma_validate_release_signing_mode; then
    exit 1
fi
if ! ma_require_release_identity; then
    exit 1
fi
echo -e "${YELLOW}Release signing mode:${NC} $(ma_release_signing_description)"

# Check if xcodeproj exists
if [ ! -d "${XCODEPROJ}" ]; then
    echo -e "${RED}Error: Xcode project not found at ${XCODEPROJ}${NC}"
    echo -e "${YELLOW}Ensure you are in the repo root and that ${XCODEPROJ_NAME} exists.${NC}"
    exit 1
fi

# Create dist directory
mkdir -p "${DIST_DIR}"

# Build Release
echo -e "${YELLOW}[1/4]${NC} Building with canonical build entrypoint (Release)..."
"${PROJECT_DIR}/scripts/run-build.sh" --configuration Release

# Check build result
BUILD_DIR="${DERIVED_DATA}/Build/Products/Release"
if [ ! -d "${BUILD_DIR}/${APP_PRODUCT_NAME}.app" ]; then
    echo -e "${RED}Error: Build failed. App not found at ${BUILD_DIR}/${APP_PRODUCT_NAME}.app${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Build completed${NC}"

# Copy to dist
echo -e "${YELLOW}[2/4]${NC} Copying to dist/..."
rm -rf "${DIST_DIR}/${APP_PRODUCT_NAME}.app"
cp -R "${BUILD_DIR}/${APP_PRODUCT_NAME}.app" "${DIST_DIR}/"
echo -e "${GREEN}✓ App copied to dist/${NC}"

# Code sign
echo -e "${YELLOW}[3/4]${NC} Code signing..."
if ma_release_uses_keychain_identity; then
    resolved_identity="$(ma_resolve_codesign_identity "${MA_RELEASE_CODE_SIGN_IDENTITY}")"
    codesign --force --deep --keychain "${HOME}/Library/Keychains/login.keychain-db" --timestamp=none --sign "${resolved_identity}" "${DIST_DIR}/${APP_PRODUCT_NAME}.app"
else
    codesign --force --deep --sign - "${DIST_DIR}/${APP_PRODUCT_NAME}.app"
fi
codesign --verify --deep --strict --verbose=2 "${DIST_DIR}/${APP_PRODUCT_NAME}.app"
echo -e "${GREEN}✓ Code signing completed${NC}"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${DIST_DIR}/${APP_PRODUCT_NAME}.app/Contents/Info.plist")"
UPDATE_ARCHIVE="${DIST_DIR}/${APP_PRODUCT_NAME}-${APP_VERSION}.zip"
echo -e "${YELLOW}[4/4]${NC} Creating update archive..."
rm -f "${UPDATE_ARCHIVE}"
ditto -c -k --keepParent "${DIST_DIR}/${APP_PRODUCT_NAME}.app" "${UPDATE_ARCHIVE}"
echo -e "${GREEN}✓ Update archive created${NC}"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Build completed successfully!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "App bundle location:"
echo -e "  ${YELLOW}${DIST_DIR}/${APP_PRODUCT_NAME}.app${NC}"
echo -e "Update archive location:"
echo -e "  ${YELLOW}${UPDATE_ARCHIVE}${NC}"
echo ""
echo -e "To run the app:"
echo -e "  ${YELLOW}open \"${DIST_DIR}/${APP_PRODUCT_NAME}.app\"${NC}"
echo ""
echo -e "To create a DMG:"
echo -e "  ${YELLOW}./scripts/create-dmg.sh${NC}"
echo ""

# Ask if user wants to run (skip in CI mode)
if [[ "$1" != "--ci" && "$1" != "--no-interactive" ]]; then
    read -p "Run the app now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "${DIST_DIR}/${APP_PRODUCT_NAME}.app"
    fi
fi
