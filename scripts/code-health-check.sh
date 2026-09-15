#!/bin/bash
# MARK: - Code Health Check Script for MeetingAssistant
# Comprehensive code quality assessment

set -e
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STYLE_CONFIG_DIR="${AGENT_CONFIG_HOME:-${HOME}/.agents}/skills/swift-conventions/config"

cd "${PROJECT_ROOT}"

echo "🏥 Running comprehensive code health check..."
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Scores and counters
TOTAL_CHECKS=0
PASSED_CHECKS=0
WARNINGS=0

# Function to report check results
check_result() {
    local name="$1"
    local result="$2"
    local message="$3"

    ((TOTAL_CHECKS++))
    if [ "$result" = "PASS" ]; then
        ((PASSED_CHECKS++))
        echo -e "✅ $name: ${GREEN}PASS${NC}"
        [ -n "$message" ] && echo -e "   $message"
    elif [ "$result" = "WARN" ]; then
        ((WARNINGS++))
        echo -e "⚠️  $name: ${YELLOW}WARNING${NC}"
        [ -n "$message" ] && echo -e "   $message"
    else
        echo -e "❌ $name: ${RED}FAIL${NC}"
        [ -n "$message" ] && echo -e "   $message"
    fi
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 CODE QUALITY CHECKS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 1. SwiftLint Check
echo "1️⃣  Running SwiftLint..."
if command -v swiftlint &> /dev/null; then
    LINT_ARGS=(lint --config "${STYLE_CONFIG_DIR}/.swiftlint.yml")
    if [ -f .swiftlint-baseline.json ]; then LINT_ARGS+=(--baseline .swiftlint-baseline.json); fi
    LINT_RESULT=$(swiftlint "${LINT_ARGS[@]}" App Packages/MeetingAssistantCore/Sources 2>&1 | wc -l)
    if [ "$LINT_RESULT" -eq 0 ]; then
        check_result "SwiftLint" "PASS" "No linting violations found"
    else
        check_result "SwiftLint" "FAIL" "Found $LINT_RESULT linting violations"
    fi
else
    check_result "SwiftLint" "FAIL" "SwiftLint not installed"
fi

# 2. SwiftFormat Check
echo ""
echo "2️⃣  Running SwiftFormat..."
if command -v swiftformat &> /dev/null; then
    if swiftformat --lint --config "${STYLE_CONFIG_DIR}/.swiftformat" App Packages/MeetingAssistantCore/Sources 2>/dev/null; then
        check_result "SwiftFormat" "PASS" "Code formatting is correct"
    else
        check_result "SwiftFormat" "WARN" "Code formatting issues found (run 'make lint-fix' to fix)"
    fi
else
    check_result "SwiftFormat" "FAIL" "SwiftFormat not installed"
fi

# 3. Test Coverage
echo ""
echo "3️⃣  Running tests..."
if ./scripts/run-tests.sh --quiet 2>/dev/null; then
    check_result "Unit Tests" "PASS" "All tests pass"
else
    check_result "Unit Tests" "FAIL" "Some tests are failing"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 CODE METRICS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# 4. Code Metrics - Lines of Code
echo "4️⃣  Analyzing code metrics..."
TOTAL_LINES=$(find App Packages/MeetingAssistantCore/Sources -name "*.swift" -exec wc -l {} \; | awk '{sum += $1} END {print sum}')
if [ "$TOTAL_LINES" -lt 10000 ]; then
    check_result "Code Size" "PASS" "Total lines: $TOTAL_LINES (maintainable)"
elif [ "$TOTAL_LINES" -lt 25000 ]; then
    check_result "Code Size" "WARN" "Total lines: $TOTAL_LINES (consider refactoring)"
else
    check_result "Code Size" "FAIL" "Total lines: $TOTAL_LINES (too large, needs refactoring)"
fi

# 5. File Count
SWIFT_FILES=$(find App Packages/MeetingAssistantCore/Sources -name "*.swift" | wc -l)
if [ "$SWIFT_FILES" -lt 100 ]; then
    check_result "File Count" "PASS" "$SWIFT_FILES Swift files"
else
    check_result "File Count" "WARN" "$SWIFT_FILES Swift files (consider organizing better)"
fi

# 6. Documentation Coverage
echo ""
echo "5️⃣  Checking documentation..."
TOTAL_PUBLIC_TYPES=$(grep -r "public " App Packages/MeetingAssistantCore/Sources --include="*.swift" | wc -l)
DOCUMENTED_TYPES=$(grep -r "///" App Packages/MeetingAssistantCore/Sources --include="*.swift" | wc -l)

if [ "$TOTAL_PUBLIC_TYPES" -eq 0 ]; then
    check_result "Documentation" "PASS" "No public types to document"
else
    DOC_PERCENTAGE=$((DOCUMENTED_TYPES * 100 / TOTAL_PUBLIC_TYPES))
    if [ "$DOC_PERCENTAGE" -ge 80 ]; then
        check_result "Documentation" "PASS" "$DOC_PERCENTAGE% of public types documented ($DOCUMENTED_TYPES/$TOTAL_PUBLIC_TYPES)"
    elif [ "$DOC_PERCENTAGE" -ge 50 ]; then
        check_result "Documentation" "WARN" "$DOC_PERCENTAGE% of public types documented ($DOCUMENTED_TYPES/$TOTAL_PUBLIC_TYPES)"
    else
        check_result "Documentation" "FAIL" "Only $DOC_PERCENTAGE% of public types documented ($DOCUMENTED_TYPES/$TOTAL_PUBLIC_TYPES)"
    fi
fi

# 7. Force Unwraps Check
echo ""
echo "6️⃣  Checking for unsafe code patterns..."
FORCE_UNWRAPS=$(grep -r "!\]" App Packages/MeetingAssistantCore/Sources --include="*.swift" | wc -l)
if [ "$FORCE_UNWRAPS" -eq 0 ]; then
    check_result "Force Unwraps" "PASS" "No force unwraps found"
elif [ "$FORCE_UNWRAPS" -le 5 ]; then
    check_result "Force Unwraps" "WARN" "Found $FORCE_UNWRAPS force unwrap(s) - review carefully"
else
    check_result "Force Unwraps" "FAIL" "Found $FORCE_UNWRAPS force unwrap(s) - too many, refactor needed"
fi

# 8. TODO/FIXME Comments
TODO_COMMENTS=$(grep -r "TODO\|FIXME\|XXX" App Packages/MeetingAssistantCore/Sources --include="*.swift" | wc -l)
if [ "$TODO_COMMENTS" -eq 0 ]; then
    check_result "TODO Comments" "PASS" "No TODO/FIXME comments"
elif [ "$TODO_COMMENTS" -le 10 ]; then
    check_result "TODO Comments" "WARN" "$TODO_COMMENTS TODO/FIXME comment(s) found"
else
    check_result "TODO Comments" "FAIL" "$TODO_COMMENTS TODO/FIXME comment(s) - too many unresolved issues"
fi

# 9. Build Check
echo ""
echo "7️⃣  Checking build..."
if make build >/dev/null 2>&1; then
    check_result "Build" "PASS" "Project builds successfully"
else
    check_result "Build" "FAIL" "Project fails to build"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📈 HEALTH SCORE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Calculate health score
if [ "$TOTAL_CHECKS" -gt 0 ]; then
    SCORE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    if [ "$SCORE" -ge 90 ]; then
        echo -e "🏆 Overall Health Score: ${GREEN}${SCORE}%${NC} (${PASSED_CHECKS}/${TOTAL_CHECKS} checks passed)"
        echo -e "${GREEN}Excellent! Code health is very good.${NC}"
    elif [ "$SCORE" -ge 75 ]; then
        echo -e "👍 Overall Health Score: ${YELLOW}${SCORE}%${NC} (${PASSED_CHECKS}/${TOTAL_CHECKS} checks passed)"
        echo -e "${YELLOW}Good, but there are some areas for improvement.${NC}"
    elif [ "$SCORE" -ge 60 ]; then
        echo -e "⚠️  Overall Health Score: ${YELLOW}${SCORE}%${NC} (${PASSED_CHECKS}/${TOTAL_CHECKS} checks passed)"
        echo -e "${YELLOW}Fair. Several issues need attention.${NC}"
    else
        echo -e "❌ Overall Health Score: ${RED}${SCORE}%${NC} (${PASSED_CHECKS}/${TOTAL_CHECKS} checks passed)"
        echo -e "${RED}Poor. Significant improvements needed.${NC}"
    fi
fi

if [ "$WARNINGS" -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}⚠️  ${WARNINGS} warning(s) detected${NC}"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$SCORE" -ge 75 ]; then
    echo -e "${GREEN}🎉 Code health check completed successfully!${NC}"
    exit 0
else
    echo -e "${RED}💥 Code health check found significant issues. Please address them.${NC}"
    exit 1
fi
