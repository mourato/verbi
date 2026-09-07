#!/bin/bash
# =============================================================================
# create-dmg.sh - Packages Vozinha.app into a .dmg file
# =============================================================================
# Works with the new Xcode project structure. Will build Release if needed.
# =============================================================================

set -euo pipefail

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

DIST_DIR="${PROJECT_DIR}/dist"
APP_BUNDLE="${DIST_DIR}/${APP_PRODUCT_NAME}.app"
DMG_NAME="${APP_PRODUCT_NAME}.dmg"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
STAGING_DIR="${DIST_DIR}/dmg_staging"
RW_DMG_PATH="${DIST_DIR}/${APP_PRODUCT_NAME}-rw.dmg"
MOUNT_POINT="${DIST_DIR}/dmg_mount"
DMG_ICON_SIZE="${DMG_ICON_SIZE:-160}"
CI_MODE=0
NO_INTERACTIVE=0
AUTO_SIGNING=0

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

cleanup() {
    set +e
    if mount | grep -Fq "on ${MOUNT_POINT} "; then
        hdiutil detach "${MOUNT_POINT}" -quiet || hdiutil detach "${MOUNT_POINT}" -force -quiet
    fi
    rm -rf "${STAGING_DIR}" "${MOUNT_POINT}"
    rm -f "${RW_DMG_PATH}"
}

prompt_release_signing_mode() {
    local detected_mode=""
    local default_choice="1"
    local reply=""

    detected_mode="$(ma_autodetect_release_signing_mode)"

    echo -e "${YELLOW}Select DMG signing mode:${NC}"
    if [ "${detected_mode}" = "identity" ]; then
        echo "  1) Auto (default): use keychain identity because '${MA_RELEASE_CODE_SIGN_IDENTITY}' is available"
    else
        echo "  1) Auto (default): use adhoc because '${MA_RELEASE_CODE_SIGN_IDENTITY}' is not available"
    fi
    echo "  2) Keychain identity (${MA_RELEASE_CODE_SIGN_IDENTITY})"
    echo "  3) Adhoc"
    printf "Choose [1/2/3] (default: %s): " "${default_choice}"
    read -r reply
    echo ""

    case "${reply:-${default_choice}}" in
        1)
            MA_RELEASE_SIGNING_MODE="${detected_mode}"
            ;;
        2)
            MA_RELEASE_SIGNING_MODE="identity"
            ;;
        3)
            MA_RELEASE_SIGNING_MODE="adhoc"
            ;;
        *)
            echo -e "${RED}Invalid selection: ${reply}${NC}" >&2
            return 1
            ;;
    esac

    return 0
}

apply_finder_layout() {
    local mount_point="$1"
    local icon_size="$2"
    local escaped_mount_point
    local script_output

    escaped_mount_point="${mount_point//\"/\\\"}"
    if ! script_output="$(osascript <<EOF 2>&1
set dmgFolder to POSIX file "${escaped_mount_point}" as alias

tell application "Finder"
    tell folder dmgFolder
        open
        set current view of container window to icon view
        tell icon view options of container window
            set arrangement to not arranged
            set icon size to ${icon_size}
        end tell
        delay 0.5
        close
    end tell
end tell
EOF
)"; then
        echo -e "${YELLOW}Warning: Could not apply Finder layout customization.${NC}"
        echo -e "         Reason: ${script_output}"
        return 1
    fi

    sync
    return 0
}

trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ci)
            CI_MODE=1
            shift
            ;;
        --no-interactive)
            NO_INTERACTIVE=1
            shift
            ;;
        --auto-signing)
            AUTO_SIGNING=1
            shift
            ;;
        --help|-h)
            cat <<'EOF'
Usage: scripts/create-dmg.sh [options]

Options:
  --ci              Run in CI mode (no prompts)
  --no-interactive  Run without prompts
  --auto-signing    Auto-detect keychain identity mode
  --help            Show help
EOF
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            exit 1
            ;;
    esac
done

if [ "${CI_MODE}" -eq 1 ] || [ "${NO_INTERACTIVE}" -eq 1 ]; then
    INTERACTIVE=0
else
    INTERACTIVE=1
fi

if [ "${CI_MODE}" -eq 1 ] && [ "${MA_RELEASE_SIGNING_MODE_WAS_SET}" -eq 0 ]; then
    MA_RELEASE_SIGNING_MODE="adhoc"
fi

if [ "${MA_RELEASE_SIGNING_MODE_WAS_SET}" -eq 0 ]; then
    if [ "${INTERACTIVE}" -eq 1 ]; then
        if ! prompt_release_signing_mode; then
            exit 1
        fi
    elif [ "${AUTO_SIGNING}" -eq 1 ]; then
        MA_RELEASE_SIGNING_MODE="$(ma_autodetect_release_signing_mode)"
    fi
fi

if ! ma_validate_release_signing_mode; then
    exit 1
fi

if ! ma_require_release_identity; then
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Creating ${DMG_NAME}${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}Release signing mode:${NC} $(ma_release_signing_description)"

# Always build Release version
echo -e "${YELLOW}Building Release version...${NC}"
echo ""
if [ "${INTERACTIVE}" -eq 0 ]; then
    MA_RELEASE_SIGNING_MODE="${MA_RELEASE_SIGNING_MODE}" \
    MA_RELEASE_CODE_SIGN_IDENTITY="${MA_RELEASE_CODE_SIGN_IDENTITY}" \
    "${PROJECT_DIR}/scripts/build-release.sh" --ci
else
    MA_RELEASE_SIGNING_MODE="${MA_RELEASE_SIGNING_MODE}" \
    MA_RELEASE_CODE_SIGN_IDENTITY="${MA_RELEASE_CODE_SIGN_IDENTITY}" \
    "${PROJECT_DIR}/scripts/build-release.sh" <<< "n"
fi
echo ""

# Verify app exists after build
if [ ! -d "${APP_BUNDLE}" ]; then
    echo -e "${RED}Error: App bundle still not found after build.${NC}"
    exit 1
fi

# Prepare staging area
echo -e "${YELLOW}[1/5]${NC} Preparing staging area..."
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

# Copy App Bundle
echo -e "      Copying ${APP_PRODUCT_NAME}.app..."
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"

# Create Applications symlink
echo -e "      Creating /Applications link..."
ln -s /Applications "${STAGING_DIR}/Applications"

# Create writable DMG
echo -e "${YELLOW}[2/5]${NC} Creating writable DMG..."
rm -f "${DMG_PATH}" "${RW_DMG_PATH}"
hdiutil create -volname "${APP_PRODUCT_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov -format UDRW \
    "${RW_DMG_PATH}"

# Mount and customize Finder view options
echo -e "${YELLOW}[3/5]${NC} Customizing Finder view..."
rm -rf "${MOUNT_POINT}"
mkdir -p "${MOUNT_POINT}"
hdiutil attach "${RW_DMG_PATH}" -nobrowse -quiet -mountpoint "${MOUNT_POINT}"
if apply_finder_layout "${MOUNT_POINT}" "${DMG_ICON_SIZE}"; then
    echo -e "      Applied icon size: ${DMG_ICON_SIZE}px"
else
    echo -e "      Continuing with default Finder layout."
fi
hdiutil detach "${MOUNT_POINT}" -quiet || hdiutil detach "${MOUNT_POINT}" -force -quiet
rm -rf "${MOUNT_POINT}"

# Convert writable DMG to compressed DMG
echo -e "${YELLOW}[4/5]${NC} Finalizing compressed DMG..."
rm -f "${DMG_PATH}"
diskutil image create from -format UDZO "${RW_DMG_PATH}" "${DMG_PATH}"

echo -e "${YELLOW}[5/6]${NC} Code signing DMG..."
if ma_release_uses_keychain_identity; then
    resolved_identity="$(ma_resolve_codesign_identity "${MA_RELEASE_CODE_SIGN_IDENTITY}")"
    /usr/bin/codesign --force --keychain "${HOME}/Library/Keychains/login.keychain-db" --timestamp=none --sign "${resolved_identity}" "${DMG_PATH}"
else
    /usr/bin/codesign --force --sign - "${DMG_PATH}"
fi
/usr/bin/codesign --verify --verbose=2 "${DMG_PATH}"

# Cleanup temporary files
echo -e "${YELLOW}[6/6]${NC} Cleaning up temporary files..."
rm -rf "${STAGING_DIR}" "${MOUNT_POINT}"
rm -f "${RW_DMG_PATH}"

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ DMG created successfully!${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "File location:"
echo -e "  ${YELLOW}${DMG_PATH}${NC}"
echo ""
echo -e "To open in Finder:"
echo -e "  ${YELLOW}open -R \"${DMG_PATH}\"${NC}"
echo ""

# Ask if user wants to open the DMG (skip in CI mode)
if [ "${INTERACTIVE}" -eq 1 ]; then
    read -p "Do you want to open the new DMG file? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        open "${DMG_PATH}"
    fi
fi
