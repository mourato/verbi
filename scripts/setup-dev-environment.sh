#!/bin/bash
# =============================================================================
# setup-dev-environment.sh - Verify and install first-run developer tools
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

missing_requirements=0

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_step() {
    echo -e "${BLUE}$1${NC}"
}

require_command() {
    local command_name="$1"
    local install_hint="$2"

    if command -v "${command_name}" >/dev/null 2>&1; then
        print_ok "${command_name} found"
        return 0
    fi

    print_error "${command_name} not found"
    echo "  ${install_hint}"
    missing_requirements=1
}

install_brew_formula() {
    local formula="$1"

    if brew list --formula "${formula}" >/dev/null 2>&1; then
        print_ok "${formula} already installed"
        return 0
    fi

    echo -e "${YELLOW}Installing ${formula}...${NC}"
    brew install "${formula}"
    print_ok "${formula} installed"
}

print_step "Checking platform requirements..."

if [ "$(uname -s)" != "Darwin" ]; then
    print_error "Prisma development requires macOS"
    exit 1
fi
print_ok "macOS host detected"

require_command "git" "Install Git from Xcode Command Line Tools or https://git-scm.com/download/mac"
require_command "xcode-select" "Install Xcode Command Line Tools with: xcode-select --install"
require_command "xcodebuild" "Install Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
require_command "make" "Install Xcode Command Line Tools with: xcode-select --install"
require_command "brew" "Install Homebrew from https://brew.sh, then re-run make setup"

if command -v xcode-select >/dev/null 2>&1; then
    if developer_dir="$(xcode-select -p 2>/dev/null)" && [ -n "${developer_dir}" ]; then
        print_ok "Xcode developer directory: ${developer_dir}"
    else
        print_error "Xcode developer directory is not configured"
        echo "  Install/select tools with: xcode-select --install"
        echo "  Or select Xcode with: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
        missing_requirements=1
    fi
fi

if [ "${missing_requirements}" -ne 0 ]; then
    echo ""
    echo -e "${RED}Setup cannot continue until the missing requirements above are installed.${NC}"
    exit 1
fi

echo ""
print_step "Installing Homebrew developer tools..."
install_brew_formula "swiftlint"
install_brew_formula "swiftformat"

echo ""
print_step "Configuring Git hooks..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=lib/configure-git-hooks.sh
source "${SCRIPT_DIR}/lib/configure-git-hooks.sh"
if configure_git_hooks "${PROJECT_ROOT}"; then
    print_ok "Git hooks configured (core.hooksPath=scripts/hooks)"
else
    print_error "Git hooks configuration failed"
    exit 1
fi

echo ""
echo -e "${GREEN}[OK] Development environment setup complete${NC}"
echo ""
echo "Next steps:"
echo "  make build"
echo "  make run"
echo "  make dmg"
echo ""
echo "Notes:"
echo "  SwiftPM dependencies resolve automatically during build."
echo "  Local AI model assets may download on first use."
echo "  For legacy self-signed DMG signing, run: make setup-self-signed-cert"
