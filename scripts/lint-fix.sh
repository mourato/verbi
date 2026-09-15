#!/bin/bash
# MARK: - Lint Fix Script for MeetingAssistant
# Automatically fixes lint issues using SwiftFormat and SwiftLint

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STYLE_CONFIG_DIR="${AGENT_CONFIG_HOME:-${HOME}/.agents}/skills/swift-conventions/config"

cd "${PROJECT_ROOT}"

echo "🛠️  Fixing lint issues automatically..."
echo ""

# Check for SwiftFormat
if ! command -v swiftformat &> /dev/null; then
    echo "❌ SwiftFormat not installed. Install with: brew install swiftformat"
    exit 1
fi

# Check for SwiftLint
if ! command -v swiftlint &> /dev/null; then
    echo "❌ SwiftLint not installed. Install with: brew install swiftlint"
    exit 1
fi

# Sources to lint
SOURCES=(
    "App"
    "Packages/MeetingAssistantCore/Sources"
)

# Step 1: Run SwiftFormat (handles most formatting issues)
echo "1️⃣  Running SwiftFormat..."
swiftformat --config "${STYLE_CONFIG_DIR}/.swiftformat" "${SOURCES[@]}"
echo "   ✅ SwiftFormat complete"
echo ""

# Step 2: Run SwiftLint autocorrect
echo "2️⃣  Running SwiftLint autocorrect..."
SWIFTLINT_ARGS=(lint --config "${STYLE_CONFIG_DIR}/.swiftlint.yml" --fix)
if [ -f .swiftlint-baseline.json ]; then
    SWIFTLINT_ARGS+=(--baseline .swiftlint-baseline.json)
fi
swiftlint "${SWIFTLINT_ARGS[@]}" "${SOURCES[@]}"
echo "   ✅ SwiftLint autocorrect complete"
echo ""

# Step 3: Check remaining issues
echo "3️⃣  Checking remaining issues..."
echo "Remaining issues check..." 
REMAINING_ARGS=(lint --config "${STYLE_CONFIG_DIR}/.swiftlint.yml")
if [ -f .swiftlint-baseline.json ]; then
    REMAINING_ARGS+=(--baseline .swiftlint-baseline.json)
fi
REMAINING=$(swiftlint "${REMAINING_ARGS[@]}" "${SOURCES[@]}" 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$REMAINING" -eq "0" ]; then
    echo "🎉 All lint issues fixed!"
else
    echo "📊 Remaining warnings: ${REMAINING}"
    echo ""
    echo "⚠️  The following issues require manual fixes:"
    echo ""
    swiftlint "${REMAINING_ARGS[@]}" "${SOURCES[@]}" 2>/dev/null | head -20
    echo ""
    echo "💡 Common manual fixes:"
    echo "   • no_force_unwrap: Replace '!' with 'guard let' or 'if let'"
    echo "   • function_body_length: Split large functions into smaller ones"
    echo "   • line_length: Break long lines into multiple lines"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
