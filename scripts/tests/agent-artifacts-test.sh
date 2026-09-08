#!/bin/bash

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'USAGE'
Usage: ./scripts/tests/agent-artifacts-test.sh

Description: Run isolated fixtures for artifact reporting, dry-run protection, and confirmed cleanup.
USAGE
    exit 0
fi

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/verbi-agent-artifacts-test.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

fixture="${TMP_ROOT}/repo"
mkdir -p "${fixture}/.git" "${fixture}/.xcode-build" "${fixture}/.xcode-build-tests" "${fixture}/not-managed"
printf '%s\n' old > "${fixture}/.xcode-build/old.bin"
printf '%s\n' recent > "${fixture}/.xcode-build-tests/recent.bin"
printf '%s\n' ignored > "${fixture}/not-managed/file.bin"
touch -t 202001010000 "${fixture}/.xcode-build/old.bin"
touch -t 202001010000 "${fixture}/.xcode-build"

output="$(python3 "${SCRIPT_ROOT}/scripts/agent-artifacts.py" --root "${fixture}")"
printf '%s\n' "${output}" | grep -Fq "AGENT_ARTIFACTS_STATUS=PASS"
printf '%s\n' "${output}" | grep -Fq "name=.xcode-build"
printf '%s\n' "${output}" | grep -Fq "ARTIFACT_LARGEST rank=1 name=.xcode-build"
printf '%s\n' "${output}" | grep -Fq "ARTIFACT_AGE_BUCKET bucket=30d+"

output="$(python3 "${SCRIPT_ROOT}/scripts/agent-artifacts.py" --root "${fixture}" --clean --dry-run --older-than-days 7)"
printf '%s\n' "${output}" | grep -F "CLEANUP_TARGET" | grep -Fq ".xcode-build size_bytes="
printf '%s\n' "${output}" | grep -F "CLEANUP_PROTECTED" | grep -Fq ".xcode-build-tests"
test -d "${fixture}/.xcode-build"

set +e
python3 "${SCRIPT_ROOT}/scripts/agent-artifacts.py" --root "${fixture}" --clean --older-than-days 7 >/dev/null 2>&1
status=$?
set -e
test "${status}" -eq 2
test -d "${fixture}/.xcode-build"

python3 "${SCRIPT_ROOT}/scripts/agent-artifacts.py" --root "${fixture}" --clean --confirm --older-than-days 7 >/dev/null
test ! -e "${fixture}/.xcode-build"
test -d "${fixture}/.xcode-build-tests"
test -e "${fixture}/not-managed/file.bin"

unowned="${TMP_ROOT}/unowned"
mkdir -p "${unowned}/.xcode-build"
set +e
python3 "${SCRIPT_ROOT}/scripts/agent-artifacts.py" --root "${unowned}" --clean --dry-run >/dev/null 2>&1
status=$?
set -e
test "${status}" -eq 1
test -d "${unowned}/.xcode-build"

echo "AGENT_ARTIFACTS_TEST_STATUS=PASS"
