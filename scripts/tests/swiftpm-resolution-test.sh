#!/bin/bash

set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    cat <<'USAGE'
Usage: ./scripts/tests/swiftpm-resolution-test.sh

Description: Verify that agent SwiftPM resolution is cached and can be explicitly forced.
USAGE
    exit 0
fi

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/verbi-swiftpm-resolution-test.XXXXXX")"
trap 'rm -rf "${TMP_ROOT}"' EXIT

FAKE_SWIFT_LOG="${TMP_ROOT}/swift.log"
FAKE_SWIFT="${TMP_ROOT}/bin/swift"
mkdir -p "${TMP_ROOT}/bin"
printf "%s\n" \
    "#!/bin/sh" \
    "if [ \"\$1\" = \"--version\" ]; then echo \"Swift version fixture-1\"; exit 0; fi" \
    "if [ \"\$1\" = \"package\" ] && [ \"\$2\" = \"resolve\" ]; then" \
    "    index=1" \
    "    while [ \"\${index}\" -le \"\$#\" ]; do" \
    "        eval \"arg=\\\${\$index}\"" \
    "        if [ \"\${arg}\" = \"--scratch-path\" ]; then" \
    "            next=\$((index + 1))" \
    "            eval \"scratch=\\\${\$next}\"" \
    "            mkdir -p \"\${scratch}/checkouts\"" \
    "        fi" \
    "        index=\$((index + 1))" \
    "    done" \
    "    echo resolve >> \"\${FAKE_SWIFT_LOG}\"" \
    "    exit 0" \
    "fi" \
    "if [ \"\$1\" = \"test\" ]; then echo test >> \"\${FAKE_SWIFT_LOG}\"; exit 0; fi" \
    "exit 0" \
    > "${FAKE_SWIFT}"
chmod +x "${FAKE_SWIFT}"

export FAKE_SWIFT_LOG
export PATH="${TMP_ROOT}/bin:${PATH}"
export MA_SWIFTPM_SCRATCH_PATH="${TMP_ROOT}/scratch"
export MA_AGENT_LOG_DIR="${TMP_ROOT}/agent"

"${SCRIPT_ROOT}/scripts/run-tests.sh" --agent --suite dev --no-parallel >/dev/null
"${SCRIPT_ROOT}/scripts/run-tests.sh" --agent --suite dev --no-parallel >/dev/null
test "$(grep -c '^resolve$' "${FAKE_SWIFT_LOG}")" -eq 1
test "$(grep -c '^test$' "${FAKE_SWIFT_LOG}")" -eq 2

MA_SWIFTPM_RESOLVE_FORCE=1 \
    "${SCRIPT_ROOT}/scripts/run-tests.sh" --agent --suite dev --no-parallel >/dev/null
test "$(grep -c '^resolve$' "${FAKE_SWIFT_LOG}")" -eq 2

echo "SWIFTPM_RESOLUTION_TEST_STATUS=PASS"
